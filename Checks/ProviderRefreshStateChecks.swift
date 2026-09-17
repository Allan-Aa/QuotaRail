import Foundation
import QuotaRailCore

func runProviderRefreshStateChecks(_ runner: inout CheckRunner) {
    let firstAttempt = Date(timeIntervalSince1970: 1_000)
    let secondAttempt = Date(timeIntervalSince1970: 2_000)
    let prior = ProviderRefreshState.finish(
        succeeded: true,
        error: nil,
        previous: .begin(previous: nil, at: firstAttempt),
        at: firstAttempt
    )
    let stale = ProviderRefreshState.finish(
        succeeded: false,
        error: "用量接口暂时不可用。",
        previous: .begin(previous: prior, at: secondAttempt),
        at: secondAttempt
    )
    runner.expect(stale.status == .stale, "Refresh failure after success becomes stale")
    runner.expect(stale.lastAttempt == secondAttempt, "Refresh failure retains latest attempt")
    runner.expect(stale.lastSuccess == firstAttempt, "Refresh failure retains last success")
    runner.expect(stale.error == "用量接口暂时不可用。", "Refresh failure retains reason")

    let unavailable = ProviderRefreshState.finish(
        succeeded: false,
        error: "未找到 Cursor 登录状态。",
        previous: .begin(previous: nil, at: firstAttempt),
        at: firstAttempt
    )
    runner.expect(unavailable.status == .unavailable, "Initial refresh failure is unavailable")
    runner.expect(unavailable.lastAttempt == firstAttempt, "Initial refresh failure records attempt")
    runner.expect(unavailable.lastSuccess == nil, "Initial refresh failure has no success")
    runner.expect(unavailable.error == "未找到 Cursor 登录状态。", "Initial refresh failure exposes reason")

    let codex = ProviderRefreshState.finish(
        succeeded: true,
        error: nil,
        previous: .begin(previous: nil, at: firstAttempt),
        at: secondAttempt
    )
    let grok = ProviderRefreshState.begin(previous: nil, at: firstAttempt)
    runner.expect(codex.status == .fresh, "Fast provider becomes fresh")
    runner.expect(codex.lastSuccess == secondAttempt, "Fast provider records its own success")
    runner.expect(grok.status == .refreshing, "Slow provider remains refreshing")
    runner.expect(grok.lastSuccess == nil, "Slow provider does not inherit fast provider success")

    let loadingValue = -1
    let firstValueAttempt = Date(timeIntervalSince1970: 3_000)
    let secondValueAttempt = Date(timeIntervalSince1970: 4_000)
    let firstValue = ProviderRefreshValue<Int>.finish(
        incoming: 42,
        succeeded: true,
        error: nil,
        previous: .begin(previous: nil, loadingValue: loadingValue, at: firstValueAttempt),
        at: firstValueAttempt
    )
    let staleValue = ProviderRefreshValue<Int>.finish(
        incoming: loadingValue,
        succeeded: false,
        error: "接口暂时不可用。",
        previous: .begin(
            previous: firstValue,
            loadingValue: loadingValue,
            at: secondValueAttempt
        ),
        at: secondValueAttempt
    )
    runner.expect(staleValue.display == 42, "Refresh failure preserves successful display value")
    runner.expect(staleValue.state.status == .stale, "Refresh failure marks preserved value stale")

    let cachedRefreshingValue = ProviderRefreshValue<Int>.begin(
        previous: firstValue,
        loadingValue: loadingValue,
        at: secondValueAttempt
    )
    runner.expect(cachedRefreshingValue.display == 42, "Next refresh preserves successful display value")
    runner.expect(cachedRefreshingValue.state.isShowingCachedValue, "Next refresh marks displayed value cached")
    runner.expect(!firstValue.state.isShowingCachedValue, "Fresh value is not marked cached")

    let initialFailure = ProviderRefreshValue<Int>.finish(
        incoming: loadingValue,
        succeeded: false,
        error: "未找到登录状态。",
        previous: .begin(previous: nil, loadingValue: loadingValue, at: firstValueAttempt),
        at: firstValueAttempt
    )
    runner.expect(initialFailure.display == loadingValue, "Initial failure displays unavailable value")
    runner.expect(initialFailure.state.status == .unavailable, "Initial failure marks unavailable")

    let initialRefreshingValue = ProviderRefreshValue<Int>.begin(
        previous: nil,
        loadingValue: loadingValue,
        at: firstValueAttempt
    )
    runner.expect(!initialRefreshingValue.state.isShowingCachedValue, "Initial refresh is not marked cached")

    let fastValue = ProviderRefreshValue<Int>.finish(
        incoming: 42,
        succeeded: true,
        error: nil,
        previous: .begin(previous: nil, loadingValue: loadingValue, at: firstValueAttempt),
        at: secondValueAttempt
    )
    let slowValue = ProviderRefreshValue<Int>.begin(
        previous: nil,
        loadingValue: loadingValue,
        at: firstValueAttempt
    )
    runner.expect(fastValue.display == 42 && fastValue.state.status == .fresh, "Fast display succeeds independently")
    runner.expect(slowValue.display == loadingValue && slowValue.state.status == .refreshing, "Slow display remains loading independently")
}
