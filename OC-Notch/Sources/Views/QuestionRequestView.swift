import SwiftUI

struct QuestionRequestView: View {
    let request: OCQuestionRequest
    @Environment(SessionMonitorService.self) private var monitor

    @State private var currentIndex = 0
    @State private var collectedAnswers: [[String]] = []
    @State private var currentSelections: Set<String> = []
    @State private var customText: String = ""
    @State private var isSubmitting = false

    private var totalQuestions: Int { request.questions.count }
    private var isMultiQuestion: Bool { totalQuestions > 1 }
    private var isLastQuestion: Bool { currentIndex >= totalQuestions - 1 }
    private var currentQuestion: OCQuestionInfo? {
        guard currentIndex < request.questions.count else { return nil }
        return request.questions[currentIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sectionSpacing) {
            if isMultiQuestion {
                stepperHeader
            }

            if let question = currentQuestion {
                questionContent(question)
                    .transition(.blurFade())
            }
        }
        .dsCardBackground()
        .animation(DS.Animations.snappy, value: currentIndex)
        .onAppear { resetState() }
        .onChange(of: request.id) { _, _ in resetState() }
    }

    // MARK: - Stepper Header

    private var stepperHeader: some View {
        HStack(spacing: DS.Spacing.elementSpacing) {
            if currentIndex > 0 {
                Button { goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(DS.Typography.micro())
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            ForEach(0..<totalQuestions, id: \.self) { index in
                Circle()
                    .fill(stepDotColor(for: index))
                    .frame(width: 5, height: 5)
            }

            Text("\(currentIndex + 1)/\(totalQuestions)")
                .font(DS.Typography.micro())
                .foregroundStyle(DS.Colors.textTertiary)

            Spacer()
        }
    }

    private func stepDotColor(for index: Int) -> Color {
        if index == currentIndex { return DS.Colors.accentBlue }
        if index < currentIndex { return DS.Colors.accentGreen }
        return DS.Colors.textTertiary
    }

    // MARK: - Question Content

    private func questionContent(_ question: OCQuestionInfo) -> some View {
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
                    if question.multiple {
                        multiSelectButton(option: option, index: index)
                    } else {
                        singleSelectButton(option: option, index: index)
                    }
                }
            }

            if question.custom {
                customInputField(question: question)
            }

            if question.multiple {
                advanceButton
            }
        }
    }

    // MARK: - Single Select (auto-advance on tap)

    private func singleSelectButton(option: OCQuestionOption, index: Int) -> some View {
        let shortcutKey = shortcutForIndex(index)

        return Button {
            selectAndAdvance([option.label])
        } label: {
            optionLabel(option: option, shortcutKey: shortcutKey, isSelected: false)
        }
        .buttonStyle(.plain)
        .applyShortcut(shortcutKey)
        .disabled(isSubmitting)
    }

    // MARK: - Multi Select (toggle, then explicit Next/Submit)

    private func multiSelectButton(option: OCQuestionOption, index: Int) -> some View {
        let isSelected = currentSelections.contains(option.label)
        let shortcutKey = shortcutForIndex(index)

        return Button {
            toggleSelection(option.label)
        } label: {
            optionLabel(option: option, shortcutKey: shortcutKey, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .applyShortcut(shortcutKey)
        .disabled(isSubmitting)
    }

    // MARK: - Custom Input

    private func customInputField(question: OCQuestionInfo) -> some View {
        TextField("Type your answer…", text: $customText)
            .textFieldStyle(.plain)
            .font(DS.Typography.caption())
            .foregroundStyle(DS.Colors.textPrimary)
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
            .onSubmit {
                let trimmed = customText.trimmingCharacters(in: .whitespaces)
                guard trimmed.isEmpty == false else { return }
                if question.multiple {
                    currentSelections.insert(trimmed)
                    selectAndAdvance(Array(currentSelections))
                } else {
                    selectAndAdvance([trimmed])
                }
            }
            .disabled(isSubmitting)
    }

    // MARK: - Advance / Submit Button

    private var advanceButton: some View {
        Button {
            selectAndAdvance(Array(currentSelections))
        } label: {
            HStack(spacing: DS.Spacing.tightSpacing) {
                Text(isLastQuestion ? "Submit" : "Next")
                    .font(DS.Typography.caption())
                    .foregroundStyle(DS.Colors.textPrimary)
                if !isLastQuestion {
                    Image(systemName: "chevron.right")
                        .font(DS.Typography.micro())
                        .foregroundStyle(DS.Colors.textPrimary)
                }
            }
            .padding(.horizontal, DS.Spacing.cardInnerSpacing)
            .padding(.vertical, DS.Spacing.elementSpacing)
            .background(
                RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
                    .fill(currentSelections.isEmpty ? DS.Colors.elevatedSurface : DS.Colors.accentBlue.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
                            .strokeBorder(
                                currentSelections.isEmpty ? DS.Colors.separator : DS.Colors.accentBlue.opacity(0.5),
                                lineWidth: 0.5
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(currentSelections.isEmpty || isSubmitting)
    }

    // MARK: - Shared Option Label

    private func optionLabel(option: OCQuestionOption, shortcutKey: String?, isSelected: Bool) -> some View {
        HStack {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Colors.accentBlue)
            }

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
                .fill(isSelected ? DS.Colors.accentBlue.opacity(0.15) : DS.Colors.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
                        .strokeBorder(
                            isSelected ? DS.Colors.accentBlue.opacity(0.3) : DS.Colors.separator,
                            lineWidth: 0.5
                        )
                )
        )
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func toggleSelection(_ label: String) {
        if currentSelections.contains(label) {
            currentSelections.remove(label)
        } else {
            currentSelections.insert(label)
        }
    }

    private func selectAndAdvance(_ answers: [String]) {
        collectedAnswers[currentIndex] = answers

        if isLastQuestion {
            submitAll()
        } else {
            withAnimation(DS.Animations.snappy) {
                currentIndex += 1
                currentSelections = Set(collectedAnswers[currentIndex])
                customText = ""
            }
        }
    }

    private func goBack() {
        withAnimation(DS.Animations.snappy) {
            if !currentSelections.isEmpty {
                collectedAnswers[currentIndex] = Array(currentSelections)
            }
            currentIndex -= 1
            currentSelections = Set(collectedAnswers[currentIndex])
            customText = ""
        }
    }

    private func submitAll() {
        isSubmitting = true
        Task {
            await monitor.replyQuestion(
                requestID: request.id,
                answers: collectedAnswers
            )
        }
    }

    private func resetState() {
        currentIndex = 0
        collectedAnswers = Array(repeating: [], count: max(totalQuestions, 1))
        currentSelections = []
        customText = ""
        isSubmitting = false
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
