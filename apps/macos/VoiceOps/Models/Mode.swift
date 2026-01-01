import Foundation

enum Mode: String, CaseIterable, Identifiable {
    case transcript
    case polish
    case action

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcript:
            return "Transcript"
        case .polish:
            return "Polish"
        case .action:
            return "Action"
        }
    }
}
