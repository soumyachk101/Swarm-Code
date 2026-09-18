import Foundation

// MARK: - BridgeEvent

enum BridgeEvent: Codable, Sendable {
    // Server → Mobile
    case messageDelta(threadID: UUID, content: String, isTool: Bool)
    case messageComplete(threadID: UUID, messageID: String)
    case toolCall(threadID: UUID, tool: String, input: String)
    case toolResult(threadID: UUID, result: String, error: String?)
    case approvalRequest(threadID: UUID, action: String, details: String)
    case thinkingDelta(threadID: UUID, content: String)
    case error(threadID: UUID?, message: String)
    case terminalOutput(threadID: UUID, output: String)
    case threadUpdated(UUID)
    case paired(sessionToken: String)
    case pairFailed(reason: String)

    // Mobile → Server
    case sendMessage(threadID: UUID, content: String)
    case approve(threadID: UUID, actionID: String)
    case reject(threadID: UUID, actionID: String)
    case createThread(projectID: UUID, prompt: String)
    case switchModel(threadID: UUID, model: String)
    case pair(code: String)

    // Shared keys
    private enum CodingKeys: String, CodingKey {
        case type, threadID, content, isTool, messageID, tool, input
        case result, error, action, details, sessionToken, reason
        case projectID, model, code
    }

    enum EventType: String, Codable {
        case messageDelta, messageComplete, toolCall, toolResult
        case approvalRequest, thinkingDelta, error, terminalOutput
        case threadUpdated, paired, pairFailed
        case sendMessage, approve, reject, createThread, switchModel, pair
    }

    var type: EventType {
        switch self {
        case .messageDelta: .messageDelta
        case .messageComplete: .messageComplete
        case .toolCall: .toolCall
        case .toolResult: .toolResult
        case .approvalRequest: .approvalRequest
        case .thinkingDelta: .thinkingDelta
        case .error: .error
        case .terminalOutput: .terminalOutput
        case .threadUpdated: .threadUpdated
        case .paired: .paired
        case .pairFailed: .pairFailed
        case .sendMessage: .sendMessage
        case .approve: .approve
        case .reject: .reject
        case .createThread: .createThread
        case .switchModel: .switchModel
        case .pair: .pair
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EventType.self, forKey: .type)
        let threadID = try container.decodeIfPresent(UUID.self, forKey: .threadID)

        switch type {
        case .messageDelta:
            self = .messageDelta(
                threadID: threadID!,
                content: try container.decode(String.self, forKey: .content),
                isTool: try container.decode(Bool.self, forKey: .isTool)
            )
        case .messageComplete:
            self = .messageComplete(
                threadID: threadID!,
                messageID: try container.decode(String.self, forKey: .messageID)
            )
        case .toolCall:
            self = .toolCall(
                threadID: threadID!,
                tool: try container.decode(String.self, forKey: .tool),
                input: try container.decode(String.self, forKey: .input)
            )
        case .toolResult:
            self = .toolResult(
                threadID: threadID!,
                result: try container.decode(String.self, forKey: .result),
                error: try container.decodeIfPresent(String.self, forKey: .error)
            )
        case .approvalRequest:
            self = .approvalRequest(
                threadID: threadID!,
                action: try container.decode(String.self, forKey: .action),
                details: try container.decode(String.self, forKey: .details)
            )
        case .thinkingDelta:
            self = .thinkingDelta(
                threadID: threadID!,
                content: try container.decode(String.self, forKey: .content)
            )
        case .error:
            self = .error(
                threadID: threadID,
                message: try container.decode(String.self, forKey: .reason)
            )
        case .terminalOutput:
            self = .terminalOutput(
                threadID: threadID!,
                output: try container.decode(String.self, forKey: .content)
            )
        case .threadUpdated:
            self = .threadUpdated(try container.decode(UUID.self, forKey: .threadID))
        case .paired:
            self = .paired(sessionToken: try container.decode(String.self, forKey: .sessionToken))
        case .pairFailed:
            self = .pairFailed(reason: try container.decode(String.self, forKey: .reason))
        case .sendMessage:
            self = .sendMessage(
                threadID: try container.decode(UUID.self, forKey: .threadID),
                content: try container.decode(String.self, forKey: .content)
            )
        case .approve:
            self = .approve(
                threadID: try container.decode(UUID.self, forKey: .threadID),
                actionID: try container.decode(String.self, forKey: .messageID)
            )
        case .reject:
            self = .reject(
                threadID: try container.decode(UUID.self, forKey: .threadID),
                actionID: try container.decode(String.self, forKey: .messageID)
            )
        case .createThread:
            self = .createThread(
                projectID: try container.decode(UUID.self, forKey: .projectID),
                prompt: try container.decode(String.self, forKey: .content)
            )
        case .switchModel:
            self = .switchModel(
                threadID: try container.decode(UUID.self, forKey: .threadID),
                model: try container.decode(String.self, forKey: .model)
            )
        case .pair:
            self = .pair(code: try container.decode(String.self, forKey: .code))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        switch self {
        case .messageDelta(let threadID, let content, let isTool):
            try container.encode(threadID, forKey: .threadID)
            try container.encode(content, forKey: .content)
            try container.encode(isTool, forKey: .isTool)
        case .messageComplete(let threadID, let messageID):
            try container.encode(threadID, forKey: .threadID)
            try container.encode(messageID, forKey: .messageID)
        case .toolCall(let threadID, let tool, let input):
            try container.encode(threadID, forKey: .threadID)
            try container.encode(tool, forKey: .tool)
            try container.encode(input, forKey: .input)
        case .toolResult(let threadID, let result, let error):
            try container.encode(threadID, forKey: .threadID)
            try container.encode(result, forKey: .result)
            try container.encode(error, forKey: .error)
        case .approvalRequest(let threadID, let action, let details):
            try container.encode(threadID, forKey: .threadID)
            try container.encode(action, forKey: .action)
            try container.encode(details, forKey: .details)
        case .thinkingDelta(let threadID, let content):
            try container.encode(threadID, forKey: .threadID)
            try container.encode(content, forKey: .content)
        case .error(let threadID, let message):
            try container.encode(threadID, forKey: .threadID)
            try container.encode(message, forKey: .reason)
        case .terminalOutput(let threadID, let output):
            try container.encode(threadID, forKey: .threadID)
            try container.encode(output, forKey: .content)
        case .threadUpdated(let threadID):
            try container.encode(threadID, forKey: .threadID)
        case .paired(let sessionToken):
            try container.encode(sessionToken, forKey: .sessionToken)
        case .pairFailed(let reason):
            try container.encode(reason, forKey: .reason)
        case .sendMessage(let threadID, let content):
            try container.encode(threadID, forKey: .threadID)
            try container.encode(content, forKey: .content)
        case .approve(let threadID, let actionID):
            try container.encode(threadID, forKey: .threadID)
            try container.encode(actionID, forKey: .messageID)
        case .reject(let threadID, let actionID):
            try container.encode(threadID, forKey: .threadID)
            try container.encode(actionID, forKey: .messageID)
        case .createThread(let projectID, let prompt):
            try container.encode(projectID, forKey: .projectID)
            try container.encode(prompt, forKey: .content)
        case .switchModel(let threadID, let model):
            try container.encode(threadID, forKey: .threadID)
            try container.encode(model, forKey: .model)
        case .pair(let code):
            try container.encode(code, forKey: .code)
        }
    }
}

// MARK: - Serialization

extension BridgeEvent {
    func jsonData() -> Data? {
        try? JSONEncoder().encode(self)
    }

    func jsonString() -> String? {
        jsonData().map { String(decoding: $0, as: UTF8.self) }
    }

    static func fromJSON(_ data: Data) -> BridgeEvent? {
        try? JSONDecoder().decode(BridgeEvent.self, from: data)
    }

    static func fromJSONString(_ string: String) -> BridgeEvent? {
        fromJSON(Data(string.utf8))
    }
}

// MARK: - ThreadSummary

struct BridgeThreadSummary: Codable, Sendable {
    let id: UUID
    let projectID: UUID
    let projectName: String
    let title: String
    let provider: String
    let model: String?
    let lastStatus: String?
    let hasUnread: Bool
    let updatedAt: Date
    let messageCount: Int
    let lastMessagePreview: String?
}

// MARK: - ThreadDetail

struct BridgeThreadDetail: Codable, Sendable {
    let id: UUID
    let projectID: UUID
    let projectPath: String
    let title: String
    let provider: String
    let model: String?
    let runtimeMode: String
    let createdAt: Date
    let updatedAt: Date
    let entries: [BridgeTimelineEntry]
    let approvals: [BridgeApproval]
    let diffRevision: Int
}

struct BridgeTimelineEntry: Codable, Sendable {
    let id: String
    let kind: String
    let date: Date
    let content: BridgeEntryContent
}

enum BridgeEntryContent: Codable, Sendable {
    case user(text: String)
    case assistant(text: String)
    case reasoning(text: String)
    case tool(name: String, input: String, output: String?, error: String?)
    case notice(text: String)
    case turnEnd(summary: String?)

    private enum CodingKeys: String, CodingKey {
        case kind, text, name, input, output, error, summary
    }

    private enum Kind: String, Codable {
        case user, assistant, reasoning, tool, notice, turnEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .user:
            self = .user(text: try container.decode(String.self, forKey: .text))
        case .assistant:
            self = .assistant(text: try container.decode(String.self, forKey: .text))
        case .reasoning:
            self = .reasoning(text: try container.decode(String.self, forKey: .text))
        case .tool:
            self = .tool(
                name: try container.decode(String.self, forKey: .name),
                input: try container.decode(String.self, forKey: .input),
                output: try container.decodeIfPresent(String.self, forKey: .output),
                error: try container.decodeIfPresent(String.self, forKey: .error)
            )
        case .notice:
            self = .notice(text: try container.decode(String.self, forKey: .text))
        case .turnEnd:
            self = .turnEnd(summary: try container.decodeIfPresent(String.self, forKey: .summary))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .user(let text):
            try container.encode(Kind.user, forKey: .kind)
            try container.encode(text, forKey: .text)
        case .assistant(let text):
            try container.encode(Kind.assistant, forKey: .kind)
            try container.encode(text, forKey: .text)
        case .reasoning(let text):
            try container.encode(Kind.reasoning, forKey: .kind)
            try container.encode(text, forKey: .text)
        case .tool(let name, let input, let output, let error):
            try container.encode(Kind.tool, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
            try container.encode(output, forKey: .output)
            try container.encode(error, forKey: .error)
        case .notice(let text):
            try container.encode(Kind.notice, forKey: .kind)
            try container.encode(text, forKey: .text)
        case .turnEnd(let summary):
            try container.encode(Kind.turnEnd, forKey: .kind)
            try container.encode(summary, forKey: .summary)
        }
    }
}

struct BridgeApproval: Codable, Sendable {
    let id: String
    let kind: String
    let title: String
    let detail: String?
    let options: [String]
}
