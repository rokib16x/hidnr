import Foundation
import Security

/// Facts about how this copy of hidnr is signed.
enum CodeSignature {
    /// True when signed by a registered Apple developer team (Apple Development
    /// or Developer ID). Ad-hoc local builds have no team, and macOS 27's
    /// allow-list then hides hidnr's own menu bar item along with the rest.
    static let hasDeveloperTeam: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return false }
        return (dict[kSecCodeInfoTeamIdentifier as String] as? String)?.isEmpty == false
    }()
}
