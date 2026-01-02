import SwiftUI

struct PreviewView: View {
    @ObservedObject var model: PreviewModel
    private let maxChars = 160

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if model.state != .idle {
                Image(systemName: model.state == .recording ? "waveform" : "clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(model.state == .recording ? .green : .orange)
                    .padding(.top, 2)
            }
            Text(displayText())
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .truncationMode(.head)
                .lineLimit(4)
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func displayText() -> String {
        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return model.state.placeholder
        }
        if text.count <= maxChars {
            return text
        }
        let start = text.index(text.endIndex, offsetBy: -maxChars)
        return String(text[start...])
    }
}
