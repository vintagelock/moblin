import SwiftUI

struct StreamsSettingsView: View {
    @ObservedObject var model: Model
    var toolbar: Toolbar

    var database: Database {
        model.database
    }

    var body: some View {
        VStack {
            Form {
                Section {
                    ForEach(database.streams) { stream in
                        NavigationLink(destination: StreamSettingsView(
                            stream: stream,
                            model: model,
                            toolbar: toolbar
                        )) {
                            HStack {
                                DraggableItemPrefixView()
                                Toggle(stream.name, isOn: Binding(get: {
                                    stream.enabled
                                }, set: { value in
                                    stream.enabled = value
                                    for ostream in database.streams
                                        where ostream.id != stream.id
                                    {
                                        ostream.enabled = false
                                    }
                                    model.reloadStream()
                                    model.sceneUpdated()
                                    model.objectWillChange.send()
                                }))
                                .disabled(stream.enabled)
                            }
                        }
                        .deleteDisabled(stream.enabled)
                    }
                    .onMove(perform: { froms, to in
                        database.streams.move(fromOffsets: froms, toOffset: to)
                        model.store()
                    })
                    .onDelete(perform: { offsets in
                        database.streams.remove(atOffsets: offsets)
                        model.store()
                        model.reloadStream()
                        model.objectWillChange.send()
                    })
                    CreateButtonView(action: {
                        database.streams.append(SettingsStream(name: "My stream"))
                        model.store()
                        model.objectWillChange.send()
                    })
                } footer: {
                    Text("Only one stream can be used at a time.")
                }
            }
        }
        .navigationTitle("Streams")
        .toolbar {
            toolbar
        }
    }
}
