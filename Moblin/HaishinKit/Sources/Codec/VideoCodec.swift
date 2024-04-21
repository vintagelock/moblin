import AVFoundation
import CoreFoundation
import UIKit
import VideoToolbox

protocol VideoCodecDelegate: AnyObject {
    func videoCodec(_ codec: VideoCodec, didOutput formatDescription: CMFormatDescription?)
    func videoCodec(_ codec: VideoCodec, didOutput sampleBuffer: CMSampleBuffer)
}

class VideoCodec {
    init(lockQueue: DispatchQueue) {
        self.lockQueue = lockQueue
    }

    static var defaultAttributes: [NSString: AnyObject]? = [
        kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(),
        kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue,
    ]

    var settings: VideoCodecSettings = .init() {
        didSet {
            if settings.shouldInvalidateSession(oldValue) {
                invalidateSession = true
            } else {
                settings.apply(self)
            }
        }
    }

    /// The running value indicating whether the VideoCodec is running.
    private(set) var isRunning: Atomic<Bool> = .init(false)

    private var lockQueue: DispatchQueue
    var expectedFrameRate = IOMixer.defaultFrameRate
    var formatDescription: CMFormatDescription? {
        didSet {
            guard !CMFormatDescriptionEqual(formatDescription, otherFormatDescription: oldValue) else {
                return
            }
            delegate?.videoCodec(self, didOutput: formatDescription)
        }
    }

    private var needsSync: Atomic<Bool> = .init(true)
    var attributes: [NSString: AnyObject]? {
        guard VideoCodec.defaultAttributes != nil else {
            return nil
        }
        var attributes: [NSString: AnyObject] = [:]
        for (key, value) in VideoCodec.defaultAttributes ?? [:] {
            attributes[key] = value
        }
        attributes[kCVPixelBufferWidthKey] = NSNumber(value: settings.videoSize.width)
        attributes[kCVPixelBufferHeightKey] = NSNumber(value: settings.videoSize.height)
        return attributes
    }

    weak var delegate: (any VideoCodecDelegate)?
    private(set) var session: (any VTSessionConvertible)? {
        didSet {
            oldValue?.invalidate()
            invalidateSession = false
        }
    }

    private var invalidateSession = true

    func appendImageBuffer(_ imageBuffer: CVImageBuffer, presentationTimeStamp: CMTime, duration: CMTime) {
        guard isRunning.value else {
            return
        }
        if invalidateSession {
            session = makeVideoCompressionSession(self)
        }
        _ = session?.encodeFrame(
            imageBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration
        ) { [unowned self] status, _, sampleBuffer in
            guard let sampleBuffer, status == noErr else {
                logger.info("Failed to encode frame status \(status) an got buffer \(sampleBuffer != nil)")
                return
            }
            formatDescription = sampleBuffer.formatDescription
            delegate?.videoCodec(self, didOutput: sampleBuffer)
        }
    }

    func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRunning.value else {
            return
        }
        if invalidateSession {
            session = makeVideoDecompressionSession(self)
            needsSync.mutate { $0 = true }
        }
        if !sampleBuffer.isNotSync {
            needsSync.mutate { $0 = false }
        }
        _ = session?
            .decodeFrame(sampleBuffer) { [
                unowned self
            ] status, _, imageBuffer, presentationTimeStamp, duration in
                guard let imageBuffer, status == noErr else {
                    logger.info("Failed to decode frame status \(status)")
                    return
                }
                guard let formatDescription = CMVideoFormatDescription.create(imageBuffer: imageBuffer) else {
                    return
                }
                var timingInfo = CMSampleTimingInfo(
                    duration: duration,
                    presentationTimeStamp: presentationTimeStamp,
                    decodeTimeStamp: sampleBuffer.decodeTimeStamp
                )
                var sampleBuffer: CMSampleBuffer?
                let status = CMSampleBufferCreateForImageBuffer(
                    allocator: kCFAllocatorDefault,
                    imageBuffer: imageBuffer,
                    dataReady: true,
                    makeDataReadyCallback: nil,
                    refcon: nil,
                    formatDescription: formatDescription,
                    sampleTiming: &timingInfo,
                    sampleBufferOut: &sampleBuffer
                )
                guard let buffer = sampleBuffer, status == noErr else {
                    logger
                        .info("Failed to decode frame status \(status) an got buffer \(sampleBuffer != nil)")
                    return
                }
                delegate?.videoCodec(self, didOutput: buffer)
            }
    }

    @objc
    private func applicationWillEnterForeground(_: Notification) {
        invalidateSession = true
    }

    @objc
    private func didAudioSessionInterruption(_ notification: Notification) {
        guard
            let userInfo: [AnyHashable: Any] = notification.userInfo,
            let value: NSNumber = userInfo[AVAudioSessionInterruptionTypeKey] as? NSNumber,
            let type = AVAudioSession.InterruptionType(rawValue: value.uintValue)
        else {
            return
        }
        switch type {
        case .ended:
            invalidateSession = true
        default:
            break
        }
    }

    func startRunning() {
        lockQueue.async {
            self.isRunning.mutate { $0 = true }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.didAudioSessionInterruption),
                name: AVAudioSession.interruptionNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.applicationWillEnterForeground),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
        }
    }

    func stopRunning() {
        lockQueue.async {
            self.session = nil
            self.invalidateSession = true
            self.needsSync.mutate { $0 = true }
            self.formatDescription = nil
            NotificationCenter.default.removeObserver(
                self,
                name: AVAudioSession.interruptionNotification,
                object: nil
            )
            NotificationCenter.default.removeObserver(
                self,
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
            self.isRunning.mutate { $0 = false }
        }
    }
}

func makeVideoCompressionSession(_ videoCodec: VideoCodec) -> (any VTSessionConvertible)? {
    var session: VTCompressionSession?
    for attribute in videoCodec.attributes ?? [:] {
        logger.info("video codec attribute: \(attribute.key) \(attribute.value)")
    }
    var status = VTCompressionSessionCreate(
        allocator: kCFAllocatorDefault,
        width: videoCodec.settings.videoSize.width,
        height: videoCodec.settings.videoSize.height,
        codecType: videoCodec.settings.format.codecType,
        encoderSpecification: nil,
        imageBufferAttributes: videoCodec.attributes as CFDictionary?,
        compressedDataAllocator: nil,
        outputCallback: nil,
        refcon: nil,
        compressionSessionOut: &session
    )
    guard status == noErr, let session else {
        logger.info("Failed to create status \(status)")
        return nil
    }
    status = session.setOptions(videoCodec.settings.options(videoCodec))
    guard status == noErr else {
        logger.info("Failed to prepare status \(status)")
        return nil
    }
    status = session.prepareToEncodeFrames()
    guard status == noErr else {
        logger.info("Failed to prepare status \(status)")
        return nil
    }
    return session
}

func makeVideoDecompressionSession(_ videoCodec: VideoCodec) -> (any VTSessionConvertible)? {
    guard let formatDescription = videoCodec.formatDescription else {
        logger.info("Failed to create status \(kVTParameterErr)")
        return nil
    }
    var attributes = videoCodec.attributes
    attributes?.removeValue(forKey: kCVPixelBufferWidthKey)
    attributes?.removeValue(forKey: kCVPixelBufferHeightKey)
    var session: VTDecompressionSession?
    let status = VTDecompressionSessionCreate(
        allocator: kCFAllocatorDefault,
        formatDescription: formatDescription,
        decoderSpecification: nil,
        imageBufferAttributes: attributes as CFDictionary?,
        outputCallback: nil,
        decompressionSessionOut: &session
    )
    guard status == noErr else {
        logger.info("Failed to create status \(status)")
        return nil
    }
    return session
}
