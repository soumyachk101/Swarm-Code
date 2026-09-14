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
