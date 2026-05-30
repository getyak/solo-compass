/// Strict state machine for the chat overlay UI.
/// Each case maps to a distinct visual presentation in ChatStateModifier.
public enum ChatUIState: Equatable {
    case idle
    case listening
    case processing
    case responding(String)
    case error(ChatError)
    case unconfigured
}

/// Errors surfaced in the chat overlay.
public enum ChatError: Equatable {
    case network
    case apiKey
    case permission
    case unknown
}
