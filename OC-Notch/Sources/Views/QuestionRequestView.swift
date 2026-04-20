import SwiftUI

struct QuestionRequestView: View {
    let request: OCQuestionRequest
    @Environment(SessionMonitorService.self) private var monitor

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sectionSpacing) {
            ForEach(Array(request.questions.enumerated()), id: \.offset) { _, question in
                questionSection(question)
            }
        }
        .dsCardBackground()
    }

    private func questionSection(_ question: OCQuestionInfo) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.cardInnerSpacing) {
            HStack(spacing: DS.Spacing.sectionSpacing) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(DS.Colors.accentBlue)
                Text(question.header.isEmpty ? "Question" : question.header)
                    .font(DS.Typography.title())
                    .foregroundStyle(DS.Colors.textPrimary)
                Spacer()
            }

            Text(question.question)
                .font(DS.Typography.body())
                .foregroundStyle(DS.Colors.textPrimary.opacity(0.9))
                .lineLimit(4)

            VStack(spacing: DS.Spacing.tightSpacing) {
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
                    .font(DS.Typography.caption())
                    .foregroundStyle(DS.Colors.textPrimary)

                if option.description.isEmpty == false {
                    Text(option.description)
                        .font(DS.Typography.caption())
                        .foregroundStyle(DS.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if let key = shortcutKey {
                    Text("⌘\(key.uppercased())").dsShortcutBadge()
                }
            }
            .padding(.horizontal, DS.Spacing.cardInnerSpacing)
            .padding(.vertical, DS.Spacing.elementSpacing)
            .background(
                RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
                    .fill(DS.Colors.elevatedSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
                            .strokeBorder(DS.Colors.separator, lineWidth: 0.5)
                    )
            )
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
