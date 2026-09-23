import Foundation
import Security

/// Where and how this copy of hidnr is installed, which decides whether macOS
/// 27 keeps hidnr's own menu bar item visible while it hides everything else.
enum Installation {
    /// macOS 27's allow-list keeps an allowed app's icon only when the app is
    /// signed by a developer team *and* lives in /Applications (tested: the
    /// notarized build stays visible from /Applications and disappears when run
    /// from anywhere else; ad-hoc builds disappear everywhere). When this is
    /// false, hidnr draws its stand-in h instead.
    static let isKeptVisibleWhileHiding: Bool = isInApplicationsFolder && hasDeveloperTeam

    static var isInApplicationsFolder: Bool {
        Bundle.main.bundleURL.resolvingSymlinksInPath().path.hasPrefix("/Applications/")
    }

    /// Signed by a registered Apple developer team (Developer ID or Apple Development).
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
