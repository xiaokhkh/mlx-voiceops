import SwiftUI

struct OverlayView: View {
    @EnvironmentObject private var pipeline: PipelineController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(statusTitle)
                    .font(.headline)
                Spacer()
                Text(statusHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Picker("Mode", selection: $pipeline.mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if !pipeline.transcript.isEmpty {
                Text(pipeline.transcript)
                    .font(.body)
                    .lineLimit(3)
            }

            if case .error(let message) = pipeline.state {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(3)
            } else if !pipeline.output.isEmpty {
                Text(pipeline.output)
                    .font(.body)
                    .lineLimit(3)
            }

            HStack {
                Button(primaryButtonTitle) {
                    pipeline.toggleRecord()
                }

                if case .ready = pipeline.state {
                    Button("Insert") {
                        pipeline.insertToFocusedApp()
                    }
                }

                if pipeline.state != .idle {
                    Button("Cancel") {
                        pipeline.cancel()
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusTitle: String {
        switch pipeline.state {
        case .idle:
            return "Idle"
        case .recording:
            return "Recording"
        case .transcribing:
            return "Transcribing"
        case .generating:
            return "Generating"
        case .ready:
            return "Ready"
        case .error:
            return "Error"
        }
    }

    private var statusHint: String {
        switch pipeline.state {
        case .idle:
            return "Option+Space"
        case .recording:
            return "Press again to stop"
        case .transcribing, .generating:
            return "Working..."
        case .ready:
            return "Enter to insert"
        case .error:
            return "Check permissions"
        }
    }

    private var primaryButtonTitle: String {
        switch pipeline.state {
        case .recording:
            return "Stop"
        default:
            return "Record"
        }
    }
}
