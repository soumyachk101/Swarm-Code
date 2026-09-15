import SwiftUI

/// The agent's questions as a tab rising from the top of the chat box, exactly like the
/// queue tab: while it asks, it takes the queue's slot (the queue, the changes tab or the
/// working line moves aside), and the moment the answer is sent the slot goes back to
/// whatever held it. It has no fold: it stays open until the questions are answered or
/// skipped. Past a screenful the questions scroll.
struct QuestionTab: View {
    static let overlap: CGFloat = ThreadChangesTab.overlap
    /// The most the questions take before they scroll.
    private static let maxHeight: CGFloat = 320

    let request: QuestionRequest
    let runtime: ThreadRuntime

    @State private var selections: [String: [String]] = [:]
    @State private var written: [String: String] = [:]
    /// The questions' natural height, so the tab grows to exactly it and no further than the cap.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous)
        let count = request.questions.count
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "questionmark.bubble")
                    .font(Chrome.inlineIconFont)
                    .foregroundStyle(Chrome.secondaryText)
                Text(verbatim: count == 1 ? "1 question" : "\(count) questions")
                    .foregroundStyle(Chrome.primaryText.opacity(0.9))
                Text(verbatim: "to answer")
                    .foregroundStyle(Chrome.secondaryText)
                Spacer(minLength: 8)
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .frame(height: 22)
            .accessibilityLabel(Text(verbatim: count == 1 ? "1 question from the agent" : "\(count) questions from the agent"))

            VStack(alignment: .leading, spacing: 4) {
                Divider().opacity(0.5)
                // The questions report their height and the clip takes exactly it, up to the
                // cap; only then does the scroll view have anything to scroll.
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(request.questions) { question in
                            questionView(question)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(contentHeight, Self.maxHeight))
                .animation(Chrome.panelSlide, value: contentHeight)

                HStack(spacing: 8) {
                    // Why Send is off, rather than a dead button and no reason for it.
                    if unansweredCount > 0 {
                        Text(verbatim: unansweredCount == 1 ? "1 question still to answer" : "\(unansweredCount) questions still to answer")
                            .font(.system(size: 11))
                            .foregroundStyle(Chrome.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button("Skip these questions") { runtime.answer(request, answers: [:]) }
                        .buttonStyle(.glass)
                        .help("Sends no answers and lets the agent carry on")
                    Button("Send answer") { runtime.answer(request, answers: answers) }
                        .buttonStyle(.glassProminent)
                        .disabled(!isComplete)
                        .help(isComplete
                            ? "Sends your answers"
                            : (count == 1 ? "Answer the question to send" : "Answer all \(count) questions to send"))
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 7 + Self.overlap)
        .frame(maxWidth: 560)
        .glassEffect(.regular, in: shape)
        .contentShape(shape)
    }

    @ViewBuilder
    private func questionView(_ question: QuestionRequest.Question) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !question.header.isEmpty {
                Text(verbatim: question.header)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Chrome.secondaryText)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: question.prompt)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Chrome.primaryText.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                // A quiet dot marks the questions still waiting, so a long list shows at
                // a glance which one is holding Send back.
                if !isAnswered(question) {
                    Circle()
                        .fill(Chrome.warning)
                        .frame(width: 5, height: 5)
                        .help("Not answered yet")
                        .accessibilityLabel(Text("Not answered yet"))
                }
                Spacer(minLength: 0)
            }
            ForEach(question.choices, id: \.self) { choice in
                choiceRow(question, choice)
            }
            if question.allowsOther || question.choices.isEmpty {
                let binding = Binding(
                    get: { written[question.id] ?? "" },
                    set: { written[question.id] = $0 }
                )
                Group {
                    if question.isSecret {
                        SecureField("Your answer", text: binding)
                    } else {
                        TextField(question.choices.isEmpty ? "Your answer" : "Something else", text: binding)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit { if isComplete { runtime.answer(request, answers: answers) } }
            }
        }
    }

    private func choiceRow(_ question: QuestionRequest.Question, _ choice: QuestionRequest.Choice) -> some View {
        let isSelected = selections[question.id, default: []].contains(choice.label)
        return Button {
            var current = selections[question.id, default: []]
            if question.allowsMultiple {
                if isSelected { current.removeAll { $0 == choice.label } } else { current.append(choice.label) }
            } else {
                current = isSelected ? [] : [choice.label]
            }
            selections[question.id] = current
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol(selected: isSelected, multiple: question.allowsMultiple))
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Chrome.accent) : AnyShapeStyle(Chrome.secondaryText))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: choice.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.primaryText.opacity(0.9))
                    if let detail = choice.detail, !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Chrome.secondaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isSelected ? AnyShapeStyle(Chrome.accent.opacity(0.14)) : AnyShapeStyle(Chrome.overlay(0.05)),
                in: .rect(cornerRadius: 8, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(Chrome.hover, value: isSelected)
    }

    private func symbol(selected: Bool, multiple: Bool) -> String {
        switch (selected, multiple) {
        case (true, true): "checkmark.square.fill"
        case (false, true): "square"
        case (true, false): "largecircle.fill.circle"
        case (false, false): "circle"
        }
    }

    private var answers: [String: [String]] {
        var result: [String: [String]] = [:]
        for question in request.questions {
            var values = selections[question.id, default: []]
            if let text = written[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                values.append(text)
            }
            result[question.id] = values
        }
        return result
    }

    private func isAnswered(_ question: QuestionRequest.Question) -> Bool {
        !(answers[question.id] ?? []).isEmpty
    }

    private var unansweredCount: Int {
        let answers = answers
        return request.questions.filter { (answers[$0.id] ?? []).isEmpty }.count
    }

    private var isComplete: Bool {
        unansweredCount == 0
    }
}
