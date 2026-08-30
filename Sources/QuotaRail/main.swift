import AppKit
import Combine
import QuotaRailCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var railController: RailWindowController!
    private var store: UsageStore!
    private var state: RailState!
    private var preferences: RailPreferences!
    private var settingsController: SettingsWindowController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let environment = ProcessInfo.processInfo.environment
        let previewMode = environment["QUOTARAIL_PREVIEW"] == "1"
        let previewMotion = previewMode && environment["QUOTARAIL_PREVIEW_MOTION"] == "1"
        let previewExit = previewMode && environment["QUOTARAIL_PREVIEW_EXIT"] == "1"
        let hoverEnabled = !previewMode
            || environment["QUOTARAIL_PREVIEW_HOVER"] == "1"
            || previewMotion
            || previewExit
        let suppressOutsideClick = previewMode && environment["QUOTARAIL_PREVIEW_INTERACTIVE"] != "1"
        preferences = makePreferences(previewMode: previewMode, environment: environment)
        if previewMode, environment["QUOTARAIL_PREVIEW_TRACE_LAYOUT"] == "1" {
            let layout = RailLayout(
                trackScale: preferences.trackScale,
                providerCount: preferences.visibleProviderIDs.count
            )
            let line = "QR_LAYOUT track=\(preferences.trackScale) providers=\(preferences.visibleProviderIDs.count) rail=\(layout.railWidth)x\(layout.railHeight)\n"
            FileHandle.standardOutput.write(Data(line.utf8))
        }
        store = UsageStore(previewMode: previewMode)
        var initialState = initialState(from: environment["QUOTARAIL_PREVIEW_STATE"])
        if environment["QUOTARAIL_PREVIEW_STATE"] == nil, preferences.alwaysVisible {
            initialState = (.rail, nil, nil)
        }
        state = RailState(
            mode: initialState.mode,
            hoverEnabled: hoverEnabled,
            initiallyPinned: initialState.isPinned,
            initialHoverY: initialState.hoverY,
            alwaysVisible: preferences.alwaysVisible
        )
        railController = RailWindowController(
            store: store,
            state: state,
            preferences: preferences,
            suppressOutsideClick: suppressOutsideClick
        )
        settingsController = SettingsWindowController(preferences: preferences)
        railController.show()
        if previewExit {
            runExitPreview()
        } else if previewMotion {
            runMotionPreview()
        }
        if previewMode, environment["QUOTARAIL_PREVIEW_SETTINGS"] == "1" {
            DispatchQueue.main.async { [weak self] in self?.settingsController.show() }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "gauge.with.dots.needle.33percent",
                accessibilityDescription: "QuotaRail"
            ) ?? NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "QuotaRail")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "QuotaRail"
        }

        preferences.$alwaysVisible
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in self?.state.setAlwaysVisible(enabled) }
            .store(in: &cancellables)

        preferences.$visibleProviderIDs
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ids in
                let tools = ToolUsage.Tool.allCases.filter { ids.contains($0.rawValue) }
                self?.state.reconcileVisibleTools(tools)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(store.$items, preferences.$visibleProviderIDs)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items, visibleIDs in
                self?.updateStatusItem(
                    items: items.filter { visibleIDs.contains($0.tool.rawValue) }
                )
            }
            .store(in: &cancellables)
    }

    private func makePreferences(
        previewMode: Bool,
        environment: [String: String]
    ) -> RailPreferences {
        let preferences: RailPreferences
        if previewMode {
            let previewDefaults = UserDefaults(suiteName: "QuotaRail.Preview") ?? .standard
            preferences = RailPreferences(defaults: previewDefaults, persistChanges: false)
        } else {
            preferences = RailPreferences()
        }

        if previewMode {
            if let value = Double(environment["QUOTARAIL_PREVIEW_TRACK_SCALE"] ?? "") {
                preferences.trackScale = value
            }
            if let value = Double(environment["QUOTARAIL_PREVIEW_ICON_SCALE"] ?? "") {
                preferences.iconScale = value
            }
            if let value = Double(environment["QUOTARAIL_PREVIEW_IDLE_SCALE"] ?? "") {
                preferences.idleIconScale = value
            }
            if let value = Double(environment["QUOTARAIL_PREVIEW_HOVER_SCALE"] ?? "") {
                preferences.hoverMaxScale = value
            }
            if let value = environment["QUOTARAIL_PREVIEW_ALWAYS_VISIBLE"] {
                preferences.alwaysVisible = value == "1"
            }
            if let raw = environment["QUOTARAIL_PREVIEW_PROVIDERS"] {
                let requestedNames = Set(
                    raw.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                )
                let requested = Set(
                    RailPreferences.providerIDs.filter {
                        requestedNames.contains($0.lowercased())
                    }
                )
                if !requested.isEmpty {
                    for id in RailPreferences.providerIDs where !requested.contains(id) {
                        preferences.setProviderVisible(id, false)
                    }
                }
            }
        }
        return preferences
    }

    private func initialState(
        from value: String?
    ) -> (mode: RailState.Mode, isPinned: Bool?, hoverY: CGFloat?) {
        switch value {
        case "rail": return (.rail, nil, nil)
        case "hover-codex": return (.detail(.codex), false, 55)
        case "hover-claude": return (.detail(.claude), false, 133)
        case "hover-grok": return (.detail(.grok), false, 211)
        case "hover-cursor": return (.detail(.cursor), false, 289)
        case "detail-codex": return (.detail(.codex), true, nil)
        case "detail-claude": return (.detail(.claude), true, nil)
        case "detail-grok": return (.detail(.grok), true, nil)
        case "detail-cursor": return (.detail(.cursor), true, nil)
        default: return (.collapsed, nil, nil)
        }
    }

    private func updateStatusItem(items: [ToolUsage]) {
        guard let button = statusItem.button else { return }
        let highest = items.compactMap { $0.available ? $0.sessionPercent : nil }.max()
        button.contentTintColor = highest.map { NSColor(StatusColor.forPercent($0)) }
        button.toolTip = highest.map { "QuotaRail · 最高 \(Int(($0 * 100).rounded()))%" } ?? "QuotaRail"
    }

    private func runMotionPreview() {
        state.showRail()
        waitForPreviewFrame { [weak self] in
            guard let self else { return }
            self.writePreviewMarker("QR_MOTION_ARMED")
            if let signalPath = ProcessInfo.processInfo.environment[
                "QUOTARAIL_PREVIEW_MOTION_SIGNAL_PATH"
            ] {
                self.waitForPreviewSignal(at: signalPath) { [weak self] in
                    self?.startMotionPreviewSequence()
                }
            } else {
                self.startMotionPreviewSequence()
            }
        }
    }

    private func startMotionPreviewSequence() {
        let steps: [(TimeInterval, () -> Void)] = [
            (0.00, { [weak self] in self?.state.continuousHoverMoved(y: 55, nearest: .codex) }),
            (0.34, { [weak self] in self?.state.continuousHoverMoved(y: 133, nearest: .claude) }),
            (0.68, { [weak self] in self?.state.continuousHoverMoved(y: 211, nearest: .grok) }),
            (1.02, { [weak self] in self?.state.continuousHoverMoved(y: 289, nearest: .cursor) }),
            (1.36, { [weak self] in self?.state.select(.cursor) }),
            (1.92, { [weak self] in
                self?.writePreviewMarker("QR_MOTION_COLLAPSE_BEGIN")
                self?.state.collapse()
            }),
        ]
        for (delay, action) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
    }

    private func runExitPreview() {
        state.showRail()
        waitForPreviewFrame { [weak self] in
            guard let self else { return }
            self.state.continuousHoverMoved(y: 133, nearest: .claude)
            self.waitForPreviewFrame { [weak self] in
                guard let self else { return }
                self.writePreviewMarker("QR_EXIT_ARMED")
                if let signalPath = ProcessInfo.processInfo.environment[
                    "QUOTARAIL_PREVIEW_EXIT_SIGNAL_PATH"
                ] {
                    self.waitForPreviewSignal(at: signalPath) { [weak self] in
                        self?.triggerPreviewExit()
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) { [weak self] in
                        self?.triggerPreviewExit()
                    }
                }
            }
        }
    }

    private func waitForPreviewFrame(
        remainingAttempts: Int = 200,
        completion: @escaping () -> Void
    ) {
        guard remainingAttempts > 0 else {
            writePreviewMarker("QR_EXIT_TIMEOUT")
            return
        }
        if railController.isPresentedFrameSettled() {
            completion()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.waitForPreviewFrame(
                remainingAttempts: remainingAttempts - 1,
                completion: completion
            )
        }
    }

    private func writePreviewMarker(_ name: String) {
        let uptime = ProcessInfo.processInfo.systemUptime
        FileHandle.standardOutput.write(Data("\(name) \(uptime)\n".utf8))
    }

    private func waitForPreviewSignal(
        at path: String,
        remainingAttempts: Int = 200,
        completion: @escaping () -> Void
    ) {
        guard remainingAttempts > 0 else {
            writePreviewMarker("QR_EXIT_TIMEOUT")
            return
        }
        if FileManager.default.fileExists(atPath: path) {
            completion()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.waitForPreviewSignal(
                at: path,
                remainingAttempts: remainingAttempts - 1,
                completion: completion
            )
        }
    }

    private func triggerPreviewExit() {
        writePreviewMarker("QR_EXIT_BEGIN")
        state.continuousHoverEnded()
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = makeMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            railController.toggle()
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示侧边栏", action: #selector(showRail), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "刷新用量", action: #selector(refreshUsage), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ","))

        let launchItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打开 Grok Usage", action: #selector(openGrokUsage), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 QuotaRail", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func showRail() {
        railController.showRail()
    }

    @objc private func refreshUsage() {
        store.refresh()
    }

    @objc private func showSettings() {
        settingsController.show()
    }

    @objc private func toggleLaunchAtLogin() {
        if case .failure = LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled) {
            NSSound.beep()
        }
    }

    @objc private func openGrokUsage() {
        guard let url = URL(string: "https://grok.com") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
