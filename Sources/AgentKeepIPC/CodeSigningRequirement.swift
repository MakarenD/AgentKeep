import Foundation
import Security

public enum CodeSigningRequirementError: Error, Equatable, LocalizedError {
    case copySelfFailed(OSStatus)
    case invalidSelfSignature(OSStatus)
    case copyStaticCodeFailed(OSStatus)
    case copySigningInformationFailed(OSStatus)
    case missingTeamIdentifier
    case malformedTeamIdentifier(String)
    case malformedSigningIdentifier(String)
    case malformedRequirement(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .copySelfFailed(let status):
            return "Could not inspect this process's code signature (\(status))."
        case .invalidSelfSignature(let status):
            return "This process's code signature is invalid (\(status))."
        case .copyStaticCodeFailed(let status):
            return "Could not inspect this process's static code signature (\(status))."
        case .copySigningInformationFailed(let status):
            return "Could not read this process's signing information (\(status))."
        case .missingTeamIdentifier:
            return "This process has no code-signing team identifier."
        case .malformedTeamIdentifier:
            return "This process has an invalid code-signing team identifier."
        case .malformedSigningIdentifier:
            return "The expected peer signing identifier is invalid."
        case .malformedRequirement(let status):
            return "Could not create a peer code-signing requirement (\(status))."
        }
    }
}

public enum CodeSigningRequirement {
    public static func sameTeam(signingIdentifier: String) throws -> String {
        try sameTeam(
            signingIdentifier: signingIdentifier,
            teamIdentifier: currentTeamIdentifier()
        )
    }

    static func sameTeam(
        signingIdentifier: String,
        teamIdentifier: String?
    ) throws -> String {
        guard isValidSigningIdentifier(signingIdentifier) else {
            throw CodeSigningRequirementError.malformedSigningIdentifier(signingIdentifier)
        }

        guard let teamIdentifier else {
            throw CodeSigningRequirementError.missingTeamIdentifier
        }

        guard isValidTeamIdentifier(teamIdentifier) else {
            throw CodeSigningRequirementError.malformedTeamIdentifier(teamIdentifier)
        }

        let requirement = "anchor apple generic and identifier \"\(signingIdentifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        var parsedRequirement: SecRequirement?
        let status = SecRequirementCreateWithString(
            requirement as CFString,
            SecCSFlags(),
            &parsedRequirement
        )

        guard status == errSecSuccess, parsedRequirement != nil else {
            throw CodeSigningRequirementError.malformedRequirement(status)
        }

        return requirement
    }

    private static func currentTeamIdentifier() throws -> String? {
        var dynamicCode: SecCode?
        let copySelfStatus = SecCodeCopySelf(SecCSFlags(), &dynamicCode)

        guard copySelfStatus == errSecSuccess, let dynamicCode else {
            throw CodeSigningRequirementError.copySelfFailed(copySelfStatus)
        }

        let validityStatus = SecCodeCheckValidity(dynamicCode, SecCSFlags(), nil)

        guard validityStatus == errSecSuccess else {
            throw CodeSigningRequirementError.invalidSelfSignature(validityStatus)
        }

        var staticCode: SecStaticCode?
        let copyStaticCodeStatus = SecCodeCopyStaticCode(
            dynamicCode,
            SecCSFlags(),
            &staticCode
        )

        guard copyStaticCodeStatus == errSecSuccess, let staticCode else {
            throw CodeSigningRequirementError.copyStaticCodeFailed(copyStaticCodeStatus)
        }

        var signingInformation: CFDictionary?
        let signingInformationStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )

        guard signingInformationStatus == errSecSuccess, let signingInformation else {
            throw CodeSigningRequirementError.copySigningInformationFailed(signingInformationStatus)
        }

        let information = signingInformation as NSDictionary
        return information[kSecCodeInfoTeamIdentifier] as? String
    }

    private static func isValidTeamIdentifier(_ value: String) -> Bool {
        value.count == 10 && value.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57) || ($0.value >= 65 && $0.value <= 90)
        }
    }

    private static func isValidSigningIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 255 else {
            return false
        }

        return value.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57)
                || ($0.value >= 65 && $0.value <= 90)
                || ($0.value >= 97 && $0.value <= 122)
                || $0 == "."
                || $0 == "-"
        }
    }
}
