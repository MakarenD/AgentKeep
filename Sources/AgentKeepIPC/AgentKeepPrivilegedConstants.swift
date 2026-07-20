public enum AgentKeepPrivilegedConstants {
    // Increment whenever the helper executable or launch daemon plist changes.
    public static let helperVersion = 1
    public static let daemonPlistName = "com.agentkeep.AgentKeep.PrivilegedHelper.plist"
    public static let machServiceName = "com.agentkeep.AgentKeep.PrivilegedHelper"
    public static let appSigningIdentifier = "com.agentkeep.AgentKeep"
    public static let helperSigningIdentifier = "com.agentkeep.AgentKeep.PrivilegedHelper"
    public static let helperExecutableName = "AgentKeepPrivilegedHelper"
}
