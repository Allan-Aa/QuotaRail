import Foundation

public enum ProviderRefreshStatus: Equatable, Sendable {
    case refreshing
    case fresh
    case stale
    case unavailable
}

public struct ProviderRefreshState: Equatable, Sendable {
    public let status: ProviderRefreshStatus
    public let lastAttempt: Date?
    public let lastSuccess: Date?
    public let error: String?

    public var isShowingCachedValue: Bool {
        lastSuccess != nil && status != .fresh
    }

    public static let unavailable = ProviderRefreshState(
        status: .unavailable,
        lastAttempt: nil,
        lastSuccess: nil,
        error: nil
    )

    public static func begin(
        previous: ProviderRefreshState?,
        at date: Date
    ) -> ProviderRefreshState {
        ProviderRefreshState(
            status: .refreshing,
            lastAttempt: date,
            lastSuccess: previous?.lastSuccess,
            error: nil
        )
    }

    public static func finish(
        succeeded: Bool,
        error: String?,
        previous: ProviderRefreshState,
        at date: Date
    ) -> ProviderRefreshState {
        if succeeded {
            return ProviderRefreshState(
                status: .fresh,
                lastAttempt: previous.lastAttempt,
                lastSuccess: date,
                error: nil
            )
        }

        return ProviderRefreshState(
            status: previous.lastSuccess == nil ? .unavailable : .stale,
            lastAttempt: previous.lastAttempt,
            lastSuccess: previous.lastSuccess,
            error: error
        )
    }
}

public struct ProviderRefreshValue<Value> {
    public let display: Value
    public let state: ProviderRefreshState

    public init(display: Value, state: ProviderRefreshState) {
        self.display = display
        self.state = state
    }

    public static func begin(
        previous: ProviderRefreshValue<Value>?,
        loadingValue: Value,
        at date: Date
    ) -> ProviderRefreshValue<Value> {
        return ProviderRefreshValue(
            display: previous?.display ?? loadingValue,
            state: .begin(previous: previous?.state, at: date)
        )
    }

    public static func finish(
        incoming: Value,
        succeeded: Bool,
        error: String?,
        previous: ProviderRefreshValue<Value>,
        at date: Date
    ) -> ProviderRefreshValue<Value> {
        let state = ProviderRefreshState.finish(
            succeeded: succeeded,
            error: error,
            previous: previous.state,
            at: date
        )
        return ProviderRefreshValue(
            display: state.status == .stale ? previous.display : incoming,
            state: state
        )
    }
}
