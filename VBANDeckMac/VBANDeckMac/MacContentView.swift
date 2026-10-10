import SwiftUI

struct MacContentView: View {
    @ObservedObject var model: MacStreamingViewModel

    var body: some View {
        Form {
            Section("VBAN Destination") {
                TextField("Destination IP", text: $model.host)
                TextField("Port", value: $model.port, format: .number)
                TextField("Stream name", text: $model.streamName)
            }

            Section("Capture") {
                Toggle("Capture system audio", isOn: $model.captureSystemAudio)
                Text(model.status)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Start Streaming") {
                        Task { await model.startStreaming() }
                    }
                    .disabled(model.isStreaming)

                    Button("Stop") {
                        model.stopStreaming()
                    }
                    .disabled(!model.isStreaming)
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 320)
    }
}
