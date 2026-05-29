
// MARK: - AgentMessage

/// A typed message sent to any agent in the pipeline.
public struct AgentMessage: Sendable {
    /// Raw natural-language input from the user (transcript or text).
    public let text: String
    /// Optional conversation history for multi-turn context.
    public let history: [AgentTurn]

    public init(text: String, history: [AgentTurn] = []) {
        self.text = text
        self.history = history
    }
}

/// One completed turn in the conversation history.
public struct AgentTurn: Sendable {
    public enum Role: String, Sendable { case user, assistant }
    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - AgentResponse

/// A typed response returned from any agent.
public struct AgentResponse: Sendable {
    /// Primary text content. Nil for pure-routing agents that produce metadata only.
    public let text: String?
    /// Arbitrary metadata produced by the agent (e.g. intent, filters).
    public let metadata: [String: String]

    public init(text: String? = nil, metadata: [String: String] = [:]) {
        self.text = text
        self.metadata = metadata
    }
}

// MARK: - Agent protocol

/// Typed agent that processes an AgentMessage and returns an AgentResponse.
public protocol Agent: Sendable {
    func handle(_ message: AgentMessage) async throws -> AgentResponse
}
