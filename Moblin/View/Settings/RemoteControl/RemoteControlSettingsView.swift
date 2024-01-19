import SwiftUI

struct PasswordView: View {
    @Environment(\.dismiss) var dismiss
    @State var value: String
    var onSubmit: (String) -> Void
    @State private var changed = false
    @State private var submitted = false

    private func submit() {
        submitted = true
        value = value.trim()
        onSubmit(value)
    }

    var body: some View {
        Form {
            Section {
                TextField("", text: $value)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onChange(of: value) { _ in
                        changed = true
                    }
                    .onSubmit {
                        submit()
                        dismiss()
                    }
                    .submitLabel(.done)
                    .onDisappear {
                        if changed && !submitted {
                            submit()
                        }
                    }
                Button {
                    value = randomHumanString()
                } label: {
                    HStack {
                        Spacer()
                        Text("Generate")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Password")
        .toolbar {
            SettingsToolbar()
        }
    }
}

struct RemoteControlSettingsView: View {
    @EnvironmentObject var model: Model

    private func submitClientAddress(value: String) {
        model.database.remoteControl!.client.address = value.trim()
        model.store()
        model.reloadRemoteControlClient()
    }

    private func submitClientPort(value: String) {
        guard let port = UInt16(value.trim()) else {
            return
        }
        model.database.remoteControl!.client.port = port
        model.store()
        model.reloadRemoteControlClient()
    }

    private func submitClientPassword(value: String) {
        model.database.remoteControl!.client.password = value.trim()
        model.store()
        model.reloadRemoteControlClient()
    }

    private func submitServerUrl(value: String) {
        guard isValidWebSocketUrl(url: value) == nil else {
            return
        }
        model.database.remoteControl!.server.url = value
        model.store()
        model.reloadRemoteControlServer()
    }

    private func submitServerPassword(value: String) {
        model.database.remoteControl!.server.password = value.trim()
        model.store()
        model.reloadRemoteControlServer()
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: {
                    model.database.remoteControl!.server.enabled
                }, set: { value in
                    model.database.remoteControl!.server.enabled = value
                    model.store()
                    model.reloadRemoteControlServer()
                })) {
                    Text("Enabled")
                }
                NavigationLink(destination: TextEditView(
                    title: String(localized: "Assistant URL"),
                    value: model.database.remoteControl!.server.url,
                    onSubmit: submitServerUrl,
                    keyboardType: .URL,
                    placeholder: "ws://32.143.32.12:2345"
                )) {
                    TextItemView(
                        name: String(localized: "Assistant URL"),
                        value: model.database.remoteControl!.server.url
                    )
                }
                NavigationLink(destination: PasswordView(
                    value: model.database.remoteControl!.server.password,
                    onSubmit: submitServerPassword
                )) {
                    TextItemView(
                        name: String(localized: "Password"),
                        value: model.database.remoteControl!.server.password,
                        sensitive: true
                    )
                }
            } header: {
                Text("Streamer")
            } footer: {
                Text("""
                     Enable to allow an assistant to monitor and control this device from a \
                     different device.
                     """)
            }
            Section {
                Toggle(isOn: Binding(get: {
                    model.database.remoteControl!.client.enabled
                }, set: { value in
                    model.database.remoteControl!.client.enabled = value
                    model.store()
                    model.reloadRemoteControlClient()
                })) {
                    Text("Enabled")
                }
                NavigationLink(destination: TextEditView(
                    title: String(localized: "Server address"),
                    value: model.database.remoteControl!.client.address,
                    onSubmit: submitClientAddress,
                    placeholder: "32.143.32.12"
                )) {
                    TextItemView(
                        name: String(localized: "Server address"),
                        value: model.database.remoteControl!.client.address
                    )
                }
                NavigationLink(destination: TextEditView(
                    title: String(localized: "Server port"),
                    value: String(model.database.remoteControl!.client.port),
                    onSubmit: submitClientPort,
                    placeholder: "2345"
                )) {
                    TextItemView(
                        name: String(localized: "Server port"),
                        value: String(model.database.remoteControl!.client.port)
                    )
                }
                NavigationLink(destination: TextEditView(
                    title: String(localized: "Streamer password"),
                    value: model.database.remoteControl!.client.password,
                    onSubmit: submitClientPassword
                )) {
                    TextItemView(
                        name: String(localized: "Streamer password"),
                        value: model.database.remoteControl!.client.password,
                        sensitive: true
                    )
                }
            } header: {
                Text("Assistant")
            } footer: {
                Text("""
                     Enable to let a streamer device connect to this device. Once connected, \
                     this device can monitor and control the streamer device.
                     """)
            }
        }
        .navigationTitle("Remote control")
        .toolbar {
            SettingsToolbar()
        }
    }
}
