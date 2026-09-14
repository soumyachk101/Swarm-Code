import SwiftUI

struct ApprovalCard: View {
    let request: ApprovalRequest
    let runtime: ThreadRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: request.symbol)
                    .foregroundStyle(Chrome.warning)
                Text(request.headline)
                    .font(.headline)
                Spacer()
            }
            switch request.kind {
            case .command:
                Text(request.title)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(8)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10, style: .continuous))
            case .plan:
                Text("Approve the plan above to let the agent start building.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            default:
                Text(request.title)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            if let detail = request.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if let reason = request.reason, !reason.isEmpty {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Spacer()
                ForEach(request.options.reversed()) { option in
                    if option.role == .approve {
                        Button(option.title) { runtime.resolve(request, option: option) }
                            .buttonStyle(.glassProminent)
                            .keyboardShortcut(.return, modifiers: .command)
                    } else {
                        Button(option.title) { runtime.resolve(request, option: option) }
                            .buttonStyle(.glass)
                    }
                }
            }
        }
        .padding(16)
        .glassEffect(.regular.tint(.orange.opacity(0.1)), in: .rect(cornerRadius: 20, style: .continuous))
    }
}

struct QuestionCard: View {
    let request: QuestionRequest
    let runtime: ThreadRuntime

    @State private var selections: [String: [String]] = [:]
    @State private var written: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(request.questions) { question in
                VStack(alignment: .leading, spacing: 8) {
                    if !question.header.isEmpty {
                        Text(question.header)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(question.prompt)
                        .font(.headline)
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
                    }
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Skip") { runtime.answer(request, answers: [:]) }
                    .buttonStyle(.glass)
                Button("Send answer") { runtime.answer(request, answers: answers) }
                    .buttonStyle(.glassProminent)
                    .disabled(!isComplete)
            }
        }
        .padding(16)
        .glassEffect(.regular.tint(.blue.opacity(0.08)), in: .rect(cornerRadius: 20, style: .continuous))
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
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: symbol(selected: isSelected, multiple: question.allowsMultiple))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.label)
                    if let detail = choice.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.35)), in: .rect(cornerRadius: 10, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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

    private var isComplete: Bool {
        request.questions.allSatisfy { !(answers[$0.id] ?? []).isEmpty }
    }
}
