import Foundation
import Network

enum ControlType: UInt16 {
    case handshake = 0
    case keepalive = 1
    case ack = 2
    case nak = 3
    case congestion_warning = 4
    case shutdown = 5
    case ackack = 6
    case dropreq = 7
    case peererror = 8
}

class Srtla {
    private var queue = DispatchQueue(label: "com.eerimoq.network", qos: .userInitiated)
    private var remoteConnections: [RemoteConnection] = []
    private var localListener: LocalListener
    private weak var delegate: (any SrtlaDelegate)?
    private var currentConnection: RemoteConnection?

    init(delegate: SrtlaDelegate, passThrough: Bool) {
        self.delegate = delegate
        localListener = LocalListener(queue: queue, delegate: delegate)
        if passThrough {
            remoteConnections.append(RemoteConnection(queue: queue, type: nil))
        } else {
            remoteConnections.append(RemoteConnection(queue: queue, type: .cellular))
            remoteConnections.append(RemoteConnection(queue: queue, type: .wifi))
            remoteConnections.append(RemoteConnection(queue: queue, type: .wiredEthernet))
        }
    }

    func start(uri: String) {
        guard
            let url = URL(string: uri),
            let host = url.host,
            let port = url.port
        else {
            logger.error("srtla: Failed to start srtla")
            return
        }
        localListener.packetHandler = handleLocalPacket(packet:)
        localListener.start()
        for connection in remoteConnections {
            connection.packetHandler = handleRemotePacket(packet:)
            connection.start(host: host, port: UInt16(port))
        }
    }

    func stop() {
        for connection in remoteConnections {
            connection.stop()
            connection.packetHandler = nil
        }
        localListener.stop()
        localListener.packetHandler = nil
    }

    func handleLocalPacket(packet: Data) {
        guard let connection = findBestRemoteConnection() else {
            logger.warning("srtla: local: No remote connection found. Dropping packet.")
            return
        }
        connection.sendPacket(packet: packet)
        delegate?.srtlaPacketSent(byteCount: packet.count)
    }

    func handleRemotePacket(packet: Data) {
        localListener.sendPacket(packet: packet)
        delegate?.srtlaPacketReceived(byteCount: packet.count)
    }

    func typeString(connection: RemoteConnection?) -> String {
        return connection?.typeString ?? "None"
    }

    func findBestRemoteConnection() -> RemoteConnection? {
        var bestConnection: RemoteConnection?
        var bestScore = -1
        for connection in remoteConnections {
            let score = connection.score()
            if score > bestScore {
                bestConnection = connection
                bestScore = score
            }
        }
        if bestConnection !== currentConnection {
            let lastType = typeString(connection: currentConnection)
            let bestType = typeString(connection: bestConnection)
            logger
                .info(
                    "srtla: remote: Best connection changed from \(lastType) to \(bestType)"
                )
            currentConnection = bestConnection
            delegate?.srtlaConnectionTypeChanged(type: bestType)
        }
        return bestConnection
    }
}
