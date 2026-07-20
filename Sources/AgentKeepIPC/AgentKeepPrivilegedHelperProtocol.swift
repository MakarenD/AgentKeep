import Foundation

@objc public protocol AgentKeepPrivilegedHelperProtocol {
    func helperVersion(withReply reply: @escaping (Int) -> Void)
    func setKeepAwake(_ enabled: Bool, withReply reply: @escaping (NSError?) -> Void)
}
