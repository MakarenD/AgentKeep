import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let powerManager = PowerManager()
    private let loginItemManager = LoginItemManager()
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let stateItem = NSMenuItem()
    private let toggleItem = NSMenuItem()
    private let refreshItem = NSMenuItem()
    private let launchAtLoginItem = NSMenuItem()
    private let openLoginItemsSettingsItem = NSMenuItem()
    private let quitItem = NSMenuItem()

    private var isKeepAwakeEnabled: Bool?
    private var launchAtLoginState = LoginItemManager.State.unknown
    private var isWorking = false
    private var isUpdatingLaunchAtLogin = false
    private var isPreparingToQuit = false
    private var hasApprovedTermination = false

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureMenu()
        refreshLaunchAtLogin(registerIfNeeded: loginItemManager.isLaunchAtLoginPreferred)
        refreshState()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        guard let button = item.button else {
            return
        }

        button.imagePosition = .imageOnly
        button.toolTip = "AgentKeep"
        updateStatusButton()
    }

    private func configureMenu() {
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

    @objc private func refreshStateFromMenu() {
        refreshState()
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
        updateMenu()
        updateStatusButton()

        let manager = powerManager
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                let currentState = try manager.currentKeepAwakeState()

                if currentState {
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
            presentError(
                title: "AgentKeep could not update sleep prevention.",
                message: error.localizedDescription
            )
        }
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

    private func setWorking(_ value: Bool) {
        isWorking = value
        updateMenu()
        updateStatusButton()
    }

    private func setUpdatingLaunchAtLogin(_ value: Bool) {
        isUpdatingLaunchAtLogin = value
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

        updateLaunchAtLoginMenu()
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
            button.title = ""
        } else {
            button.image = nil
            button.title = "AK"
        }

        button.toolTip = tooltip
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
