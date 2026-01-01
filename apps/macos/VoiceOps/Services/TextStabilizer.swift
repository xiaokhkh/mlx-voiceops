import Foundation

final class TextStabilizer {
    private(set) var committedText: String = ""
    private var lastText: String = ""
    private var candidateText: String = ""
    private var candidateCount: Int = 0
    private let confirmations: Int

    init(confirmations: Int = 2) {
        self.confirmations = max(1, confirmations)
    }

    func reset() {
        committedText = ""
        lastText = ""
        candidateText = ""
        candidateCount = 0
    }

    func update(_ newText: String) -> String {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousCommitted = committedText

        let common = longestCommonPrefix(a: lastText, b: trimmed)
        if common.count < committedText.count {
            candidateText = ""
            candidateCount = 0
        } else if common.count > committedText.count {
            if common == candidateText {
                candidateCount += 1
            } else {
                candidateText = common
                candidateCount = 1
            }
            if candidateCount >= confirmations {
                committedText = candidateText
                candidateText = ""
                candidateCount = 0
            }
        }

        lastText = trimmed
        return String(committedText.dropFirst(previousCommitted.count))
    }

    func forceCommit(_ newText: String) -> String {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousCommitted = committedText
        if trimmed.count >= committedText.count {
            committedText = trimmed
        }
        lastText = trimmed
        candidateText = ""
        candidateCount = 0
        return String(committedText.dropFirst(previousCommitted.count))
    }

    private func longestCommonPrefix(a: String, b: String) -> String {
        if a.isEmpty || b.isEmpty {
            return ""
        }
        let aChars = Array(a)
        let bChars = Array(b)
        let limit = min(aChars.count, bChars.count)
        var i = 0
        while i < limit, aChars[i] == bChars[i] {
            i += 1
        }
        if i == 0 {
            return ""
        }
        return String(aChars[0..<i])
    }
}
