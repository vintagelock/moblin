import AVFoundation
import SwiftUI

private let imageBackground = Color(red: 0.25, green: 0.25, blue: 0.25)
private let singleButtonSize: CGFloat = 45

struct ButtonImage: View {
    var image: String
    var on: Bool
    var buttonSize: CGFloat
    var slash: Bool = false
    var pause: Bool = false
    var overlayColor: Color = .white

    var body: some View {
        let image = Image(systemName: image)
            .frame(width: buttonSize, height: buttonSize)
            .foregroundColor(.white)
            .background(imageBackground)
            .clipShape(Circle())
        ZStack {
            if on {
                image.overlay(
                    Circle()
                        .stroke(.white)
                )
            } else {
                image
            }
            if slash {
                // Button press animation not perfect.
                Image(systemName: "line.diagonal")
                    .frame(width: buttonSize, height: buttonSize)
                    .foregroundColor(.white)
                    .rotationEffect(Angle(degrees: 90))
                    .shadow(color: imageBackground, radius: 0, x: 1, y: 0)
                    .shadow(color: imageBackground, radius: 0, x: -1, y: 0)
                    .shadow(color: imageBackground, radius: 0, x: 0, y: 1)
                    .shadow(color: imageBackground, radius: 0, x: 0, y: -1)
                    .shadow(color: imageBackground, radius: 0, x: -2, y: -2)
            }
            if pause {
                // Button press animation not perfect.
                Image(systemName: "pause")
                    .bold()
                    .font(.system(size: 9))
                    .frame(width: buttonSize, height: buttonSize)
                    .offset(y: -1)
                    .foregroundColor(overlayColor)
            }
        }
    }
}

struct ButtonPlaceholderImage: View {
    var body: some View {
        Button {} label: {
            Image(systemName: "pawprint")
                .frame(width: buttonSize, height: buttonSize)
                .foregroundColor(.black)
        }
        .opacity(0.0)
    }
}

struct MicButtonView: View {
    @EnvironmentObject var model: Model
    @State var selectedMic: Mic
    var done: () -> Void
    @State var micFollowsScene: Bool = false
    @State var externalMicOverrides: Bool = false

    var body: some View {
        Form {
            Section {
                Picker("", selection: Binding(get: {
                    model.mic
                }, set: { mic, _ in
                    selectedMic = mic
                })) {
                    ForEach(model.listMics()) { mic in
                        Text(mic.name).tag(mic)
                    }
                }
                .onChange(of: selectedMic) { mic in
                    model.selectMicById(id: mic.id)
                    done()
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            if model.database.debug!.sceneMic! {
                Section {
                    Toggle("Mic follows scene", isOn: $micFollowsScene)
                    Toggle("External mic overrides follow scene toggle", isOn: $externalMicOverrides)
                }
            }
        }
        .navigationTitle("Mic")
        .toolbar {
            QuickSettingsToolbar(done: done)
        }
    }
}

struct StreamSwitcherView: View {
    @EnvironmentObject var model: Model
    var done: () -> Void

    var body: some View {
        Form {
            Section {
                Picker("", selection: $model.currentStreamId) {
                    ForEach(model.database.streams) { stream in
                        Text(stream.name)
                    }
                }
                .onChange(of: model.currentStreamId) { _ in
                    model.stopStream()
                    model.stopRecording()
                    if model.setCurrentStream(streamId: model.currentStreamId) {
                        model.reloadStream()
                        model.sceneUpdated()
                        model.isLive = true
                        DispatchQueue.main
                            .asyncAfter(deadline: .now() + 3) {
                                model.startStream(delayed: true)
                            }
                    } else {
                        model.makeErrorToast(title: "Failed to switch scene")
                    }
                    done()
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("Automatically goes live when switching stream.")
            }
        }
        .navigationTitle("Stream")
        .toolbar {
            QuickSettingsToolbar(done: done)
        }
    }
}

struct ImageView: View {
    @EnvironmentObject var model: Model
    var done: () -> Void

    var body: some View {
        Form {
            Section("Exposure bias") {
                HStack {
                    Slider(
                        value: $model.bias,
                        in: -2 ... 2,
                        step: 0.2,
                        onEditingChanged: { begin in
                            guard !begin else {
                                return
                            }
                            model.setExposureBias(bias: model.bias)
                        }
                    )
                    .onChange(of: model.bias) { _ in
                        model.setExposureBias(bias: model.bias)
                    }
                    Text("\(formatOneDecimal(value: model.bias)) EV")
                        .frame(width: 60)
                }
            }
        }
        .navigationTitle("Camera")
        .toolbar {
            QuickSettingsToolbar(done: done)
        }
    }
}

struct ObsView: View {
    @EnvironmentObject var model: Model
    var done: () -> Void

    var body: some View {
        Form {
            if model.obsStreaming {
                Section {
                    HStack {
                        Spacer()
                        Button(action: {
                            model.obsStopStream()
                        }, label: {
                            Text("Stop streaming")
                        })
                        Spacer()
                    }
                }
                .foregroundColor(.white)
                .listRowBackground(Color.blue)
            } else {
                Section {
                    HStack {
                        Spacer()
                        Button(action: {
                            model.obsStartStream()
                        }, label: {
                            Text("Start streaming")
                        })
                        Spacer()
                    }
                }
            }
            Section {
                Picker("", selection: $model.obsCurrentScene) {
                    ForEach(model.obsScenes, id: \.self) { scene in
                        Text(scene)
                    }
                }
                .onChange(of: model.obsCurrentScene) { _ in
                    model.setObsScene(name: model.obsCurrentScene)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Scenes")
            }
            if !model.stream.obsSourceName!.isEmpty {
                Section {
                    if model.isLive {
                        if let image = model.obsScreenshot {
                            Image(image, scale: 1, label: Text(""))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        }
                    } else {
                        Text("Go live to see snapshot")
                    }
                } header: {
                    Text("\(model.stream.obsSourceName!) source snapshot")
                }
                Section {
                    if model.isLive && !model.obsAudioVolume.isEmpty {
                        Text(model.obsAudioVolume)
                    } else {
                        Text("Go live to see audio levels")
                    }
                } header: {
                    Text("\(model.stream.obsSourceName!) source audio levels")
                }
            } else {
                Text("""
                Cannot show snapshot and audio levels. Configure source name in \
                Settings → Streams → \(model.stream.name) → OBS remote control
                """)
            }
        }
        .navigationTitle("OBS")
        .toolbar {
            QuickSettingsToolbar(done: done)
        }
    }
}

private func startStopText(button: ButtonState) -> String {
    return button.isOn ? "Stop" : "Start"
}

struct ButtonsView: View {
    @EnvironmentObject var model: Model
    @State private var isPresentingRecordConfirm: Bool = false

    private func getImage(state: ButtonState) -> String {
        if state.isOn {
            return state.button.systemImageNameOn
        } else {
            return state.button.systemImageNameOff
        }
    }

    private func torchAction(state: ButtonState) {
        state.button.isOn.toggle()
        model.toggleTorch()
        model.updateButtonStates()
    }

    private func muteAction(state: ButtonState) {
        state.button.isOn.toggle()
        model.toggleMute()
        model.updateButtonStates()
    }

    private func widgetAction(state: ButtonState) {
        state.button.isOn.toggle()
        model.sceneUpdated(store: false)
    }

    private func chatAction(state: ButtonState) {
        state.button.isOn.toggle()
        model.showChatMessages.toggle()
        model.sceneUpdated(store: false)
    }

    private func pauseChatAction(state: ButtonState) {
        state.button.isOn.toggle()
        model.toggleChatPaused()
        model.sceneUpdated(store: false)
    }

    private func pauseChatOverlayColor() -> Color {
        if model.chatPaused {
            return imageBackground
        } else {
            return .white
        }
    }

    private func blackScreenAction(state _: ButtonState) {
        model.toggleBlackScreen()
        model.makeToast(
            title: String(localized: "Black screen"),
            subTitle: String(localized: "Double tap to return to main view")
        )
        model.updateButtonStates()
    }

    private func recordAction(state _: ButtonState) {
        if !model.isRecording {
            model.startRecording()
        } else {
            model.stopRecording()
        }
        model.updateButtonStates()
    }

    private func movieAction(state: ButtonState) {
        state.button.isOn.toggle()
        model.setGlobalButtonState(type: .movie, isOn: state.button.isOn)
        model.sceneUpdated(store: false)
    }

    private func grayScaleAction(state: ButtonState) {
        state.button.isOn.toggle()
        model.setGlobalButtonState(type: .grayScale, isOn: state.button.isOn)
        model.sceneUpdated(store: false)
    }

    private func sepiaAction(state: ButtonState) {
        state.button.isOn.toggle()
        model.setGlobalButtonState(type: .sepia, isOn: state.button.isOn)
        model.sceneUpdated(store: false)
    }

    private func randomAction(state: ButtonState) {
        state.button.isOn.toggle()
        model.setGlobalButtonState(type: .random, isOn: state.button.isOn)
        model.sceneUpdated(store: false)
    }

    private func tripleAction(state: ButtonState) {
        state.button.isOn.toggle()
        model.setGlobalButtonState(type: .triple, isOn: state.button.isOn)
        model.sceneUpdated(store: false)
    }

    private func pixellateAction(state: ButtonState) {
        state.button.isOn.toggle()
        model.setGlobalButtonState(type: .pixellate, isOn: state.button.isOn)
        model.sceneUpdated(store: false)
    }

    private func streamAction(state _: ButtonState) {
        model.showingStreamSwitcher = true
    }

    private func gridAction(state: ButtonState) {
        state.button.isOn.toggle()
        model.showingGrid.toggle()
        model.sceneUpdated(store: false)
    }

    private func obsAction(state _: ButtonState) {
        guard model.isObsRemoteControlConfigured() else {
            model.makeErrorToast(
                title: String(localized: "OBS remote control is not configured"),
                subTitle: String(
                    localized: """
                    Configure it in Settings → Streams → \(model.stream.name) → \
                    OBS remote control.
                    """
                )
            )
            return
        }
        model.listObsScenes(onComplete: { ok in
            model.showingObs = ok
            model.startObsSourceScreenshot()
            model.startObsAudioVolume()
        })
    }

    var body: some View {
        VStack {
            ForEach(model.buttonPairs) { pair in
                if model.database.quickButtons!.twoColumns {
                    HStack(alignment: .top) {
                        if let second = pair.second {
                            VStack {
                                switch second.button.type {
                                case .torch:
                                    Button(action: {
                                        torchAction(state: second)
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                case .mute:
                                    Button(action: {
                                        muteAction(state: second)
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                case .bitrate:
                                    Button(action: {
                                        model.showingBitrate = true
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                case .widget:
                                    Button(action: {
                                        widgetAction(state: second)
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                case .mic:
                                    Button(action: {
                                        model.showingMic = true
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                case .chat:
                                    Button(action: {
                                        chatAction(state: second)
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize,
                                            slash: true
                                        )
                                    })
                                case .pauseChat:
                                    Button(action: {
                                        pauseChatAction(state: second)
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize,
                                            pause: true,
                                            overlayColor: pauseChatOverlayColor()
                                        )
                                    })
                                case .blackScreen:
                                    Button(action: {
                                        blackScreenAction(state: second)
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                case .obsScene:
                                    ButtonPlaceholderImage()
                                case .obsStartStopStream:
                                    ButtonPlaceholderImage()
                                case .record:
                                    Button(action: {
                                        isPresentingRecordConfirm = true
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                    .confirmationDialog("", isPresented: $isPresentingRecordConfirm) {
                                        Button(startStopText(button: second)) {
                                            recordAction(state: second)
                                        }
                                    }
                                case .image:
                                    Button(action: {
                                        model.showingImage = true
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                case .movie:
                                    Button(action: {
                                        movieAction(state: second)
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                case .grayScale:
                                    Button(action: {
                                        grayScaleAction(state: second)
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                case .sepia:
                                    Button(action: {
                                        sepiaAction(state: second)
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                case .random:
                                    Button(action: {
                                        randomAction(state: second)
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                case .triple:
                                    Button(action: {
                                        tripleAction(state: second)
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                case .pixellate:
                                    Button(action: {
                                        pixellateAction(state: second)
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                case .stream:
                                    Button(action: {
                                        streamAction(state: second)
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                case .grid:
                                    Button(action: {
                                        gridAction(state: second)
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                case .obs:
                                    Button(action: {
                                        obsAction(state: second)
                                    }, label: {
                                        ButtonImage(
                                            image: getImage(state: second),
                                            on: second.isOn,
                                            buttonSize: buttonSize
                                        )
                                    })
                                }
                                if model.database.quickButtons!.showName {
                                    Text(second.button.name)
                                        .foregroundColor(.white)
                                        .font(.system(size: 10))
                                }
                            }
                        } else {
                            ButtonPlaceholderImage()
                        }
                        VStack {
                            switch pair.first.button.type {
                            case .torch:
                                Button(action: {
                                    torchAction(state: pair.first)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .mute:
                                Button(action: {
                                    muteAction(state: pair.first)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .bitrate:
                                Button(action: {
                                    model.showingBitrate = true
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .widget:
                                Button(action: {
                                    widgetAction(state: pair.first)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .mic:
                                Button(action: {
                                    model.showingMic = true
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .chat:
                                Button(action: {
                                    chatAction(state: pair.first)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize,
                                        slash: true
                                    )
                                })
                            case .pauseChat:
                                Button(action: {
                                    pauseChatAction(state: pair.first)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize,
                                        pause: true,
                                        overlayColor: pauseChatOverlayColor()
                                    )
                                })
                            case .blackScreen:
                                Button(action: {
                                    blackScreenAction(state: pair.first)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .obsScene:
                                ButtonPlaceholderImage()
                            case .obsStartStopStream:
                                ButtonPlaceholderImage()
                            case .record:
                                Button(action: {
                                    isPresentingRecordConfirm = true
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                                .confirmationDialog("", isPresented: $isPresentingRecordConfirm) {
                                    Button(startStopText(button: pair.first)) {
                                        recordAction(state: pair.first)
                                    }
                                }
                            case .image:
                                Button(action: {
                                    model.showingImage = true
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .movie:
                                Button(action: {
                                    movieAction(state: pair.first)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .grayScale:
                                Button(action: {
                                    grayScaleAction(state: pair.first)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .sepia:
                                Button(action: {
                                    sepiaAction(state: pair.first)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .random:
                                Button(action: {
                                    randomAction(state: pair.first)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .triple:
                                Button(action: {
                                    tripleAction(state: pair.first)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .pixellate:
                                Button(action: {
                                    pixellateAction(state: pair.first)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .stream:
                                Button(action: {
                                    streamAction(state: pair.first)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .grid:
                                Button(action: {
                                    gridAction(state: pair.first)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .obs:
                                Button(action: {
                                    obsAction(state: pair.first)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: pair.first),
                                        on: pair.first.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            }
                            if model.database.quickButtons!.showName {
                                Text(pair.first.button.name)
                                    .foregroundColor(.white)
                                    .font(.system(size: 10))
                            }
                        }
                    }
                    .id(pair.first.button.id)
                } else {
                    if let second = pair.second {
                        VStack {
                            switch second.button.type {
                            case .torch:
                                Button(action: {
                                    torchAction(state: second)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: singleButtonSize
                                    )
                                })
                            case .mute:
                                Button(action: {
                                    muteAction(state: second)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: singleButtonSize
                                    )
                                })
                            case .bitrate:
                                Button(action: {
                                    model.showingBitrate = true
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: singleButtonSize
                                    )
                                })
                            case .widget:
                                Button(action: {
                                    widgetAction(state: second)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: singleButtonSize
                                    )
                                })
                            case .mic:
                                Button(action: {
                                    model.showingMic = true
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: singleButtonSize
                                    )
                                })
                            case .chat:
                                Button(action: {
                                    chatAction(state: second)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: singleButtonSize,
                                        slash: true
                                    )
                                })
                            case .pauseChat:
                                Button(action: {
                                    pauseChatAction(state: second)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: singleButtonSize,
                                        pause: true,
                                        overlayColor: pauseChatOverlayColor()
                                    )
                                })
                            case .blackScreen:
                                Button(action: {
                                    blackScreenAction(state: second)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: singleButtonSize
                                    )
                                })
                            case .obsScene:
                                ButtonPlaceholderImage()
                            case .obsStartStopStream:
                                ButtonPlaceholderImage()
                            case .record:
                                Button(action: {
                                    isPresentingRecordConfirm = true
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                                .confirmationDialog("", isPresented: $isPresentingRecordConfirm) {
                                    Button(startStopText(button: second)) {
                                        recordAction(state: second)
                                    }
                                }
                            case .image:
                                Button(action: {
                                    model.showingImage = true
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .movie:
                                Button(action: {
                                    movieAction(state: second)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .grayScale:
                                Button(action: {
                                    grayScaleAction(state: second)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .sepia:
                                Button(action: {
                                    sepiaAction(state: second)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .random:
                                Button(action: {
                                    randomAction(state: second)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .triple:
                                Button(action: {
                                    tripleAction(state: second)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .pixellate:
                                Button(action: {
                                    pixellateAction(state: second)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .stream:
                                Button(action: {
                                    streamAction(state: second)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .grid:
                                Button(action: {
                                    gridAction(state: second)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            case .obs:
                                Button(action: {
                                    obsAction(state: second)
                                }, label: {
                                    ButtonImage(
                                        image: getImage(state: second),
                                        on: second.isOn,
                                        buttonSize: buttonSize
                                    )
                                })
                            }
                            if model.database.quickButtons!.showName {
                                Text(second.button.name)
                                    .foregroundColor(.white)
                                    .font(.system(size: 10))
                            }
                        }
                    } else {
                        EmptyView()
                    }
                    VStack {
                        switch pair.first.button.type {
                        case .torch:
                            Button(action: {
                                torchAction(state: pair.first)
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: singleButtonSize
                                )
                            })
                        case .mute:
                            Button(action: {
                                muteAction(state: pair.first)
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: singleButtonSize
                                )
                            })
                        case .bitrate:
                            Button(action: {
                                model.showingBitrate = true
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: singleButtonSize
                                )
                            })
                        case .widget:
                            Button(action: {
                                widgetAction(state: pair.first)
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: singleButtonSize
                                )
                            })
                        case .mic:
                            Button(action: {
                                model.showingMic = true
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: singleButtonSize
                                )
                            })
                        case .chat:
                            Button(action: {
                                chatAction(state: pair.first)
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: singleButtonSize,
                                    slash: true
                                )
                            })
                        case .pauseChat:
                            Button(action: {
                                pauseChatAction(state: pair.first)
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: singleButtonSize,
                                    pause: true,
                                    overlayColor: pauseChatOverlayColor()
                                )
                            })
                        case .blackScreen:
                            Button(action: {
                                blackScreenAction(state: pair.first)
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: singleButtonSize
                                )
                            })
                        case .obsScene:
                            ButtonPlaceholderImage()
                        case .obsStartStopStream:
                            ButtonPlaceholderImage()
                        case .record:
                            Button(action: {
                                isPresentingRecordConfirm = true
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: buttonSize
                                )
                            })
                            .confirmationDialog("", isPresented: $isPresentingRecordConfirm) {
                                Button(startStopText(button: pair.first)) {
                                    recordAction(state: pair.first)
                                }
                            }
                        case .image:
                            Button(action: {
                                model.showingImage = true
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: buttonSize
                                )
                            })
                        case .movie:
                            Button(action: {
                                movieAction(state: pair.first)
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: buttonSize
                                )
                            })
                        case .grayScale:
                            Button(action: {
                                grayScaleAction(state: pair.first)
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: buttonSize
                                )
                            })
                        case .sepia:
                            Button(action: {
                                sepiaAction(state: pair.first)
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: buttonSize
                                )
                            })
                        case .random:
                            Button(action: {
                                randomAction(state: pair.first)
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: buttonSize
                                )
                            })
                        case .triple:
                            Button(action: {
                                tripleAction(state: pair.first)
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: buttonSize
                                )
                            })
                        case .pixellate:
                            Button(action: {
                                pixellateAction(state: pair.first)
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: buttonSize
                                )
                            })
                        case .stream:
                            Button(action: {
                                streamAction(state: pair.first)
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: buttonSize
                                )
                            })
                        case .grid:
                            Button(action: {
                                gridAction(state: pair.first)
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: buttonSize
                                )
                            })
                        case .obs:
                            Button(action: {
                                obsAction(state: pair.first)
                            }, label: {
                                ButtonImage(
                                    image: getImage(state: pair.first),
                                    on: pair.first.isOn,
                                    buttonSize: buttonSize
                                )
                            })
                        }
                        if model.database.quickButtons!.showName {
                            Text(pair.first.button.name)
                                .foregroundColor(.white)
                                .font(.system(size: 10))
                        }
                    }
                    .id(pair.first.button.id)
                }
            }
        }
    }
}
