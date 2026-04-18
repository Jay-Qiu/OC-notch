import SwiftUI

struct QuestionRequestView: View {
    let request: OCQuestionRequest
    @Environment(SessionMonitorService.self) private var monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(request.questions.enumerated()), id: \.offset) { _, question in
                questionSection(question)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }

    private func questionSection(_ question: OCQuestionInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.blue)
                Text(question.header.isEmpty ? "Question" : question.header)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }

            Text(question.question)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(4)

            VStack(spacing: 4) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    optionButton(option: option, index: index)
                }
            }
        }
    }

    private func optionButton(option: OCQuestionOption, index: Int) -> some View {
        let shortcutKey = shortcutForIndex(index)

        return Button {
            Task {
                await monitor.replyQuestion(
                    requestID: request.id,
                    answers: [[option.label]]
                )
            }
        } label: {
            HStack {
                Text(option.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)

                if option.description.isEmpty == false {
                    Text(option.description)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                if let key = shortcutKey {
                    Text("⌘\(key.uppercased())")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .applyShortcut(shortcutKey)
    }

    private func shortcutForIndex(_ index: Int) -> String? {
        guard index < 9 else { return nil }
        return "\(index + 1)"
    }
}

private extension View {
    @ViewBuilder
    func applyShortcut(_ key: String?) -> some View {
        if let key, let char = key.first {
            self.keyboardShortcut(KeyEquivalent(char), modifiers: .command)
        } else {
            self
        }
    }
}
