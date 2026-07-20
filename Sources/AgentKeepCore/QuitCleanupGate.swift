enum QuitCleanupGate {
    static func shouldStart(
        isPreparingToQuit: Bool,
        isWorking: Bool,
        isCleanupRunning: Bool
    ) -> Bool {
        isPreparingToQuit && !isWorking && !isCleanupRunning
    }

    static func shouldDisableKeepAwake(currentState: Bool) -> Bool {
        currentState
    }
}
