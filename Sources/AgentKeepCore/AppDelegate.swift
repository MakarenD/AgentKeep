import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let powerManager = PowerManager()
    private let loginItemManager = LoginItemManager()
    private let localServerMonitor = LocalServerMonitor()
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let stateItem = NSMenuItem()
    private let toggleItem = NSMenuItem()
    private let refreshItem = NSMenuItem()
    private let localServersHeaderItem = NSMenuItem()
    private let refreshLocalServersItem = NSMenuItem()
    private let stopLocalServersItem = NSMenuItem()
    private let launchAtLoginItem = NSMenuItem()
    private let openLoginItemsSettingsItem = NSMenuItem()
    private let quitItem = NSMenuItem()

    private var isKeepAwakeEnabled: Bool?
    private var localServers: [LocalServerProcess] = []
    private var localServerItems: [NSMenuItem] = []
    private var localServerError: Error?
    private var launchAtLoginState = LoginItemManager.State.unknown
    private var isWorking = false
    private var isRefreshingLocalServers = false
    private var isStoppingLocalServers = false
    private var shouldPresentLocalServerRefreshError = false
    private var isUpdatingLaunchAtLogin = false
    private var isPreparingToQuit = false
    private var isQuitCleanupRunning = false
    private var hasApprovedTermination = false
    private var localServerRefreshTimer: Timer?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureMenu()
        refreshLaunchAtLogin(registerIfNeeded: loginItemManager.isLaunchAtLoginPreferred)
        refreshState()
        refreshLocalServers()
        startLocalServerRefreshTimer()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        guard let button = item.button else {
            return
        }

        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        button.toolTip = "AgentKeep"
        updateStatusButton()
    }

    private func configureMenu() {
        menu.delegate = self

        stateItem.isEnabled = false
        menu.addItem(stateItem)

        toggleItem.target = self
        toggleItem.action = #selector(toggleKeepAwake)
        menu.addItem(toggleItem)

        refreshItem.title = "Refresh"
        refreshItem.target = self
        refreshItem.action = #selector(refreshStateFromMenu)
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        localServersHeaderItem.isEnabled = false
        menu.addItem(localServersHeaderItem)

        refreshLocalServersItem.title = "Refresh Local Servers"
        refreshLocalServersItem.target = self
        refreshLocalServersItem.action = #selector(refreshLocalServersFromMenu)
        menu.addItem(refreshLocalServersItem)

        stopLocalServersItem.title = "Stop All Local Servers..."
        stopLocalServersItem.target = self
        stopLocalServersItem.action = #selector(stopAllLocalServers)
        menu.addItem(stopLocalServersItem)

        menu.addItem(.separator())

        launchAtLoginItem.target = self
        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)
        menu.addItem(launchAtLoginItem)

        openLoginItemsSettingsItem.title = "Open Login Items Settings"
        openLoginItemsSettingsItem.target = self
        openLoginItemsSettingsItem.action = #selector(openLoginItemsSettings)
        menu.addItem(openLoginItemsSettingsItem)

        menu.addItem(.separator())

        quitItem.title = "Quit AgentKeep"
        quitItem.action = #selector(quit)
        quitItem.keyEquivalent = "q"
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        updateMenu()
    }

    public func menuWillOpen(_ menu: NSMenu) {
        refreshLocalServers()
    }

    @objc private func refreshStateFromMenu() {
        refreshState()
    }

    @objc private func refreshLocalServersFromMenu() {
        refreshLocalServers(presentErrors: true)
    }

    @objc private func stopAllLocalServers() {
        guard !isStoppingLocalServers, !localServers.isEmpty else {
            return
        }

        let serversToStop = localServers

        guard confirmStopLocalServers(serversToStop) else {
            return
        }

        setStoppingLocalServers(true)

        let monitor = localServerMonitor
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = monitor.stop(serversToStop)

            DispatchQueue.main.async {
                self?.handleStopLocalServersResult(result)
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        guard !isUpdatingLaunchAtLogin else {
            return
        }

        let targetValue: Bool

        switch launchAtLoginState {
        case .enabled:
            targetValue = false
        case .notRegistered, .notFound, .requiresApproval, .unknown:
            targetValue = true
        }

        setUpdatingLaunchAtLogin(true)

        let manager = loginItemManager
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try manager.setLaunchAtLoginPreferred(targetValue)
                return manager.currentState()
            }

            DispatchQueue.main.async {
                self?.handleLaunchAtLoginResult(result)
            }
        }
    }

    @objc private func openLoginItemsSettings() {
        loginItemManager.openLoginItemsSettings()
    }

    @objc private func toggleKeepAwake() {
        guard !isWorking else {
            return
        }

        guard let isKeepAwakeEnabled else {
            refreshState()
            return
        }

        let targetValue = !isKeepAwakeEnabled
        setWorking(true)

        let manager = powerManager
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try manager.setKeepAwake(enabled: targetValue)
                return try manager.currentKeepAwakeState()
            }

            DispatchQueue.main.async {
                self?.handleStateResult(result)
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if hasApprovedTermination {
            return .terminateNow
        }

        guard !isPreparingToQuit else {
            return .terminateLater
        }

        prepareToQuit()
        return .terminateLater
    }

    private func refreshState() {
        guard !isWorking else {
            return
        }

        setWorking(true)

        let manager = powerManager
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try manager.currentKeepAwakeState()
            }

            DispatchQueue.main.async {
                self?.handleStateResult(result)
            }
        }
    }

    private func refreshLocalServers(presentErrors: Bool = false) {
        guard !isRefreshingLocalServers, !isStoppingLocalServers else {
            return
        }

        shouldPresentLocalServerRefreshError = shouldPresentLocalServerRefreshError || presentErrors
        setRefreshingLocalServers(true)

        let monitor = localServerMonitor
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result {
                try monitor.currentServers()
            }

            DispatchQueue.main.async {
                self?.handleLocalServerResult(result)
            }
        }
    }

    private func startLocalServerRefreshTimer() {
        localServerRefreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refreshLocalServers()
        }
        localServerRefreshTimer?.tolerance = 5
    }

    private func refreshLaunchAtLogin(registerIfNeeded: Bool) {
        guard !isUpdatingLaunchAtLogin else {
            return
        }

        setUpdatingLaunchAtLogin(true)

        let manager = loginItemManager
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                if registerIfNeeded {
                    try manager.registerIfPreferred()
                }

                return manager.currentState()
            }

            DispatchQueue.main.async {
                self?.handleLaunchAtLoginResult(result)
            }
        }
    }

    private func prepareToQuit() {
        isPreparingToQuit = true
        localServerRefreshTimer?.invalidate()
        updateMenu()
        updateStatusButton()

        startQuitCleanupIfReady()
    }

    private func startQuitCleanupIfReady() {
        guard QuitCleanupGate.shouldStart(
            isPreparingToQuit: isPreparingToQuit,
            isWorking: isWorking,
            isCleanupRunning: isQuitCleanupRunning
        ) else {
            return
        }

        isQuitCleanupRunning = true

        let manager = powerManager
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                let currentState = try manager.currentKeepAwakeState()

                if QuitCleanupGate.shouldDisableKeepAwake(currentState: currentState) {
                    try manager.setKeepAwake(enabled: false)
                }

                return try manager.currentKeepAwakeState()
            }

            DispatchQueue.main.async {
                self?.finishPreparingToQuit(result)
            }
        }
    }

    private func finishPreparingToQuit(_ result: Result<Bool, Error>) {
        isQuitCleanupRunning = false

        switch result {
        case .success(let isEnabled):
            isKeepAwakeEnabled = isEnabled

            if isEnabled {
                finishTerminationAfterFailure("Keep-Awake is still enabled after AgentKeep tried to disable it.")
            } else {
                finishTermination(shouldQuit: true)
            }
        case .failure(let error):
            finishTerminationAfterFailure(error.localizedDescription)
        }
    }

    private func finishTerminationAfterFailure(_ message: String) {
        let shouldQuit = presentQuitFailure(message)
        finishTermination(shouldQuit: shouldQuit)
    }

    private func finishTermination(shouldQuit: Bool) {
        if shouldQuit {
            hasApprovedTermination = true
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }

        isPreparingToQuit = false
        updateMenu()
        updateStatusButton()
        NSApp.reply(toApplicationShouldTerminate: false)
    }

    private func handleStateResult(_ result: Result<Bool, Error>) {
        setWorking(false)

        switch result {
        case .success(let isEnabled):
            isKeepAwakeEnabled = isEnabled
            updateMenu()
            updateStatusButton()
        case .failure(let error):
            updateMenu()
            updateStatusButton()

            if isPreparingToQuit {
                startQuitCleanupIfReady()
                return
            }

            if let helperError = error as? PrivilegedHelperClientError,
               helperError.requiresApproval {
                powerManager.openHelperApprovalSettings()
            }

            presentError(
                title: "AgentKeep could not update sleep prevention.",
                message: error.localizedDescription
            )
        }

        startQuitCleanupIfReady()
    }

    private func handleLaunchAtLoginResult(_ result: Result<LoginItemManager.State, Error>) {
        setUpdatingLaunchAtLogin(false)

        switch result {
        case .success(let state):
            launchAtLoginState = state
            updateMenu()
        case .failure(let error):
            launchAtLoginState = loginItemManager.currentState()
            updateMenu()
            presentError(
                title: "AgentKeep could not update Launch at Login.",
                message: error.localizedDescription
            )
        }
    }

    private func handleLocalServerResult(_ result: Result<[LocalServerProcess], Error>) {
        setRefreshingLocalServers(false)

        switch result {
        case .success(let servers):
            localServers = servers
            localServerError = nil
            shouldPresentLocalServerRefreshError = false
            updateMenu()
            updateStatusButton()
        case .failure(let error):
            localServers = []
            localServerError = error
            let shouldPresentError = shouldPresentLocalServerRefreshError
            shouldPresentLocalServerRefreshError = false
            updateMenu()
            updateStatusButton()

            if shouldPresentError {
                presentError(
                    title: "AgentKeep could not scan local servers.",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func handleStopLocalServersResult(_ result: LocalServerStopResult) {
        setStoppingLocalServers(false)

        if !result.failures.isEmpty {
            presentError(
                title: "AgentKeep could not stop every local server.",
                message: stopFailureMessage(for: result.failures)
            )
        }

        refreshLocalServers()
    }

    private func setWorking(_ value: Bool) {
        isWorking = value
        updateMenu()
        updateStatusButton()
    }

    private func setUpdatingLaunchAtLogin(_ value: Bool) {
        isUpdatingLaunchAtLogin = value
        updateMenu()
    }

    private func setRefreshingLocalServers(_ value: Bool) {
        isRefreshingLocalServers = value
        updateMenu()
    }

    private func setStoppingLocalServers(_ value: Bool) {
        isStoppingLocalServers = value
        updateMenu()
    }

    private func updateMenu() {
        if isPreparingToQuit {
            stateItem.title = "Disabling Keep-Awake before quitting..."
            toggleItem.title = "Quitting..."
            toggleItem.isEnabled = false
            refreshItem.isEnabled = false
            quitItem.title = "Quitting..."
            quitItem.isEnabled = false
            updateLocalServersMenu()
            updateLaunchAtLoginMenu()
            return
        }

        quitItem.title = "Quit AgentKeep"
        quitItem.isEnabled = true

        if isWorking {
            stateItem.title = "Checking sleep prevention..."
            toggleItem.title = "Working..."
            toggleItem.isEnabled = false
            refreshItem.isEnabled = false
        } else {
            refreshItem.isEnabled = true

            switch isKeepAwakeEnabled {
            case .some(true):
                stateItem.title = "Keep Mac Awake: On"
                toggleItem.title = "Disable Keep-Awake"
                toggleItem.isEnabled = true
            case .some(false):
                stateItem.title = "Keep Mac Awake: Off"
                toggleItem.title = "Enable Keep-Awake"
                toggleItem.isEnabled = true
            case .none:
                stateItem.title = "Keep Mac Awake: Unknown"
                toggleItem.title = "Refresh Status"
                toggleItem.isEnabled = true
            }
        }

        updateLocalServersMenu()
        updateLaunchAtLoginMenu()
    }

    private func updateLocalServersMenu() {
        for item in localServerItems {
            menu.removeItem(item)
        }

        localServerItems = makeLocalServerMenuItems()

        if let insertionIndex = menu.items.firstIndex(of: refreshLocalServersItem) {
            for (offset, item) in localServerItems.enumerated() {
                menu.insertItem(item, at: insertionIndex + offset)
            }
        }

        if isPreparingToQuit {
            localServersHeaderItem.title = "Local Servers"
            refreshLocalServersItem.isEnabled = false
            stopLocalServersItem.isEnabled = false
            return
        }

        if isStoppingLocalServers {
            localServersHeaderItem.title = "Local Servers: Stopping..."
            refreshLocalServersItem.isEnabled = false
            stopLocalServersItem.title = "Stopping Local Servers..."
            stopLocalServersItem.isEnabled = false
            return
        }

        if isRefreshingLocalServers, localServers.isEmpty {
            localServersHeaderItem.title = "Local Servers: Checking..."
        } else if localServerError != nil {
            localServersHeaderItem.title = "Local Servers: Scan Failed"
        } else {
            localServersHeaderItem.title = "Local Servers: \(localServers.count) Running"
        }

        refreshLocalServersItem.isEnabled = !isRefreshingLocalServers
        stopLocalServersItem.title = "Stop All Local Servers..."
        stopLocalServersItem.isEnabled = !localServers.isEmpty && !isRefreshingLocalServers
    }

    private func makeLocalServerMenuItems() -> [NSMenuItem] {
        if isPreparingToQuit {
            return [disabledMenuItem(title: "Unavailable while quitting")]
        }

        if let localServerError {
            let item = disabledMenuItem(title: "Could not scan local servers")
            item.toolTip = localServerError.localizedDescription
            return [item]
        }

        if localServers.isEmpty {
            if isRefreshingLocalServers {
                return [disabledMenuItem(title: "Scanning localhost listeners...")]
            }

            return [disabledMenuItem(title: "No local dev servers detected")]
        }

        return localServers.map { server in
            let item = disabledMenuItem(title: menuTitle(for: server))
            item.toolTip = tooltip(for: server)
            return item
        }
    }

    private func disabledMenuItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func updateLaunchAtLoginMenu() {
        if isPreparingToQuit {
            launchAtLoginItem.title = "Launch at Login"
            launchAtLoginItem.state = launchAtLoginState == .enabled ? .on : .off
            launchAtLoginItem.isEnabled = false
            openLoginItemsSettingsItem.isHidden = true
            return
        }

        if isUpdatingLaunchAtLogin {
            launchAtLoginItem.title = "Launch at Login: Updating..."
            launchAtLoginItem.state = .off
            launchAtLoginItem.isEnabled = false
            openLoginItemsSettingsItem.isHidden = true
            return
        }

        launchAtLoginItem.isEnabled = true

        switch launchAtLoginState {
        case .enabled:
            launchAtLoginItem.title = "Launch at Login"
            launchAtLoginItem.state = .on
            openLoginItemsSettingsItem.isHidden = true
        case .notRegistered:
            launchAtLoginItem.title = "Launch at Login"
            launchAtLoginItem.state = .off
            openLoginItemsSettingsItem.isHidden = true
        case .requiresApproval:
            launchAtLoginItem.title = "Launch at Login: Needs Approval"
            launchAtLoginItem.state = .off
            openLoginItemsSettingsItem.isHidden = false
        case .notFound:
            launchAtLoginItem.title = "Launch at Login: Build App First"
            launchAtLoginItem.state = .off
            launchAtLoginItem.isEnabled = false
            openLoginItemsSettingsItem.isHidden = true
        case .unknown:
            launchAtLoginItem.title = "Launch at Login: Unknown"
            launchAtLoginItem.state = .off
            openLoginItemsSettingsItem.isHidden = true
        }
    }

    private func updateStatusButton() {
        guard let button = statusItem?.button else {
            return
        }

        let symbolName: String
        let tooltip: String
        let presentation = StatusItemPresentation(
            localServerCount: localServerError == nil ? localServers.count : nil
        )

        if isPreparingToQuit {
            symbolName = "hourglass"
            tooltip = "AgentKeep is disabling sleep prevention before quitting"
        } else if isWorking {
            symbolName = "hourglass"
            tooltip = "AgentKeep is checking sleep prevention"
        } else if isKeepAwakeEnabled == true {
            symbolName = "bolt.circle.fill"
            tooltip = "AgentKeep is keeping this Mac awake"
        } else {
            symbolName = "moon.zzz"
            tooltip = "AgentKeep is not preventing sleep"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip) {
            image.isTemplate = true
            button.image = image
            button.title = presentation.title
        } else {
            button.image = nil
            button.title = presentation.fallbackTitle
        }

        button.toolTip = "\(tooltip). \(presentation.processSummary)."
        button.setAccessibilityLabel("\(tooltip). \(presentation.processSummary).")
    }

    private func menuTitle(for server: LocalServerProcess) -> String {
        let ports = server.sortedPorts.map { ":\($0)" }.joined(separator: ", ")
        let project = server.projectName ?? "Unknown folder"

        return "\(ports) - \(server.kind.rawValue) - \(project) (PID \(server.pid))"
    }

    private func tooltip(for server: LocalServerProcess) -> String {
        [
            "Process: \(server.processName)",
            "Command: \(server.commandLine ?? "Unknown")",
            "Folder: \(displayPath(server.workingDirectory))",
            "Listeners: \(server.listeners.map(\.rawName).joined(separator: ", "))"
        ].joined(separator: "\n")
    }

    private func displayPath(_ path: String?) -> String {
        guard let path else {
            return "Unknown"
        }

        let homeDirectory = NSHomeDirectory()

        if path == homeDirectory {
            return "~"
        }

        if path.hasPrefix(homeDirectory + "/") {
            return "~" + path.dropFirst(homeDirectory.count)
        }

        return path
    }

    private func confirmStopLocalServers(_ servers: [LocalServerProcess]) -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Stop all local development servers?"
        alert.informativeText = stopConfirmationMessage(for: servers)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Stop All")

        return alert.runModal() == .alertSecondButtonReturn
    }

    private func stopConfirmationMessage(for servers: [LocalServerProcess]) -> String {
        let serverLines = servers.prefix(8).map { server in
            "- \(menuTitle(for: server)) in \(displayPath(server.workingDirectory))"
        }

        let remainingCount = servers.count - serverLines.count
        let remainingText = remainingCount > 0 ? "\n- And \(remainingCount) more." : ""

        return """
        AgentKeep will send SIGTERM to these processes and use SIGKILL if any of them keep running:

        \(serverLines.joined(separator: "\n"))\(remainingText)
        """
    }

    private func stopFailureMessage(for failures: [LocalServerStopFailure]) -> String {
        failures
            .map { failure in
                "\(menuTitle(for: failure.process)): \(failure.message)"
            }
            .joined(separator: "\n")
    }

    private func presentError(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentQuitFailure(_ message: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "AgentKeep could not disable Keep-Awake before quitting."
        alert.informativeText = "\(message)\n\nKeep AgentKeep running to avoid leaving this Mac in SleepDisabled mode, or quit anyway."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit Anyway")

        return alert.runModal() == .alertSecondButtonReturn
    }
}
