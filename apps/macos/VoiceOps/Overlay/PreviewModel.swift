import Foundation

@MainActor
final class PreviewModel: ObservableObject {
    enum State {
        case idle
        case recording
        case processing

        var title: String {
            switch self {
            case .idle:
                return "Idle"
            case .recording:
                return "Listening"
            case .processing:
                return "Processing"
            }
        }

        var placeholder: String {
            switch self {
            case .idle:
                return ""
            case .recording:
                return "Listening..."
            case .processing:
                return "Finalizing..."
            }
        }
    }

    @Published var text: String = ""
    @Published var state: State = .idle
}
