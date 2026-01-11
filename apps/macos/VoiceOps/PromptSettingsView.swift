import SwiftUI

struct PromptSettingsView: View {
    @AppStorage(OfflineLLMClient.translationSystemPromptDefaultsKey) private var translationSystemPrompt = ""
    @AppStorage(OfflineLLMClient.translationUserPromptDefaultsKey) private var translationUserPrompt = ""
    @AppStorage(OfflineLLMClient.voiceSystemPromptDefaultsKey) private var voiceSystemPrompt = ""
    @AppStorage(OfflineLLMClient.voiceUserPromptDefaultsKey) private var voiceUserPrompt = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("LLM Prompts")
                            .font(.title2.weight(.semibold))
                        Spacer()
                        Button("Reset All") {
                            translationSystemPrompt = OfflineLLMClient.defaultTranslationSystemPrompt
                            translationUserPrompt = OfflineLLMClient.defaultTranslationUserPromptTemplate
                            voiceSystemPrompt = OfflineLLMClient.defaultVoiceSystemPrompt
                            voiceUserPrompt = OfflineLLMClient.defaultVoiceUserPromptTemplate
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Text("Tune how the local Ollama model translates text and handles voice input.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                PromptSection(title: "Translation", subtitle: "Used when translating selected text.") {
                    PromptCard(
                        title: "System Prompt",
                        caption: "Defines tone, constraints, and output style.",
                        text: $translationSystemPrompt,
                        minHeight: 190
                    )
                    PromptCard(
                        title: "User Template",
                        caption: "Use `{{text}}` as the placeholder for the selected text.",
                        text: $translationUserPrompt,
                        minHeight: 150
                    )
                }

                PromptSection(title: "Voice", subtitle: "Used for spoken input processing.") {
                    PromptCard(
                        title: "System Prompt",
                        caption: "Sets the voice workflow behavior.",
                        text: $voiceSystemPrompt,
                        minHeight: 190
                    )
                    PromptCard(
                        title: "User Template",
                        caption: "Use `{{text}}` as the placeholder for the spoken input.",
                        text: $voiceUserPrompt,
                        minHeight: 150
                    )
                }
            }
            .padding(20)
        }
        .onAppear {
            if translationSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                translationSystemPrompt = OfflineLLMClient.defaultTranslationSystemPrompt
            }
            if translationUserPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                translationUserPrompt = OfflineLLMClient.defaultTranslationUserPromptTemplate
            }
            if voiceSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                voiceSystemPrompt = OfflineLLMClient.defaultVoiceSystemPrompt
            }
            if voiceUserPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                voiceUserPrompt = OfflineLLMClient.defaultVoiceUserPromptTemplate
            }
        }
    }
}

private struct PromptSection<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                content
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.12))
        )
    }
}

private struct PromptCard: View {
    let title: String
    let caption: String
    @Binding var text: String
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(caption)
                .font(.caption)
                .foregroundColor(.secondary)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: minHeight)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18))
                )
        }
    }
}
