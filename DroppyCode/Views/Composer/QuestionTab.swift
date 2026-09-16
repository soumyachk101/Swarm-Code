import SwiftUI

/// The agent's questions as a badge at the end of the conversation, answered in
/// its popover; it leaves with the answer.
struct QuestionBadgeRow: View {
    let request: QuestionRequest
    let runtime: ThreadRuntime
    @State private var isShowingQuestions = false

    var body: some View {
        let count = request.questions.count
        ChatBadge(
            title: count == 1 ? "1 question" : "\(count) questions",
            caption: "to answer",
            needsAttention: true,
            isPresented: $isShowingQuestions,
            glyph: { Image(systemName: "questionmark.bubble").foregroundStyle(.tint) },
            detail: { QuestionSheet(request: request, runtime: runtime) }
        )
    }
}

/// The agent's questions, answered in the badge's popover. It stays open until
/// the questions are answered or skipped. Past a screenful the questions scroll.
///
/// The popover freezes the sheet at the size it opens with (see `BadgePopoverCoordinator`),
/// so the sheet knows its own height before it opens: the questions are measured once,
/// here, and nothing in it changes size afterwards; picking, typing and scrolling leave
/// the popover where it is.
struct QuestionSheet: View {
    /// The most the questions take before they scroll.
    private static let maxHeight: CGFloat = 360
    private static let width: CGFloat = 460

    let request: QuestionRequest
    let runtime: ThreadRuntime
    /// The questions' natural height at the sheet's width, capped: a scroll view offered
    /// no height collapses, so the popover's measuring pass needs it given outright.
    private let listHeight: CGFloat

    @State private var selections: [String: [String]] = [:]
    @State private var written: [String: String] = [:]

    init(request: QuestionRequest, runtime: ThreadRuntime) {
        self.request = request
        self.runtime = runtime
        let probe = QuestionList(request: request, selections: .constant([:]), written: .constant([:]), onSubmit: {})
            .frame(width: Self.width)
        let natural = NSHostingView(rootView: probe).fittingSize.height
        listHeight = min(natural > 0 ? natural : Self.maxHeight, Self.maxHeight)
    }

    var body: some View {
        let count = request.questions.count
        let answers = QuestionAnswers.collect(request, selections: selections, written: written)
        let unanswered = QuestionAnswers.unansweredCount(request, answers: answers)
        let isComplete = unanswered == 0
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical) {
                QuestionList(request: request, selections: $selections, written: $written) {
                    if isComplete { runtime.answer(request, answers: answers) }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: listHeight)

            Divider()

            HStack(spacing: 8) {
                if unanswered > 0 {
                    Text(verbatim: unanswered == 1 ? "1 question still to answer" : "\(unanswered) questions still to answer")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Skip") { runtime.answer(request, answers: [:]) }
                    .buttonStyle(.bordered)
                    .help("Sends no answers and lets the agent carry on")
                Button("Send") { runtime.answer(request, answers: answers) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isComplete)
                    .help(isComplete
                        ? "Sends your answers"
                        : (count == 1 ? "Answer the question to send" : "Answer all \(count) questions to send"))
            }
            .controlSize(.regular)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: Self.width)
    }
}

/// The questions themselves, in order: header, prompt, choices, a field for anything
/// else. Its own view so the sheet can measure it before the popover opens.
private struct QuestionList: View {
    let request: QuestionRequest
    @Binding var selections: [String: [String]]
    @Binding var written: [String: String]
    /// Return in a field sends the answers, when they are complete.
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(request.questions) { question in
                questionView(question)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func questionView(_ question: QuestionRequest.Question) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !question.header.isEmpty {
                Text(verbatim: question.header)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            Text(verbatim: question.prompt)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            // Keyed by index, so two identically worded choices both work.
            ForEach(Array(question.choices.enumerated()), id: \.offset) { _, choice in
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
                .controlSize(.regular)
                .onSubmit(onSubmit)
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
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: choice.label)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    if let detail = choice.detail, !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func symbol(selected: Bool, multiple: Bool) -> String {
        switch (selected, multiple) {
        case (true, true): "checkmark.square.fill"
        case (false, true): "square"
        case (true, false): "checkmark.circle.fill"
        case (false, false): "circle"
        }
    }
}

/// What the sheet sends: per question, the picked choices and anything written.
private enum QuestionAnswers {
    static func collect(_ request: QuestionRequest, selections: [String: [String]], written: [String: String]) -> [String: [String]] {
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

    static func unansweredCount(_ request: QuestionRequest, answers: [String: [String]]) -> Int {
        request.questions.filter { (answers[$0.id] ?? []).isEmpty }.count
    }
}
