import AppKit
import Combine
import SwiftUI

/// The single settings window, created on first use.
enum SettingsWindow {
    enum Tab: String, CaseIterable {
        case icons = "Icons"
        case general = "General"
    }

    /// Which tab is showing; shared so `show(_:)` can switch it.
    final class Router: ObservableObject {
        static let shared = Router()
        @Published var tab: Tab = .icons
    }

    private static var window: NSWindow?

    static var isVisible: Bool { window?.isVisible ?? false }

    static func show(_ tab: Tab) {
        Router.shared.tab = tab
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(router: .shared))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "hidnr Settings"
            newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
            newWindow.titlebarAppearsTransparent = true
            newWindow.titleVisibility = .hidden
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static func openAccessibilityPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var router: SettingsWindow.Router
    @State private var isTrusted = StatusItemScanner.isTrusted
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader()
            Picker("", selection: $router.tab) {
                ForEach(SettingsWindow.Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .padding(.vertical, 14)

            Group {
                switch router.tab {
                case .icons: IconsPage(isTrusted: isTrusted)
                case .general: GeneralPage(isTrusted: isTrusted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 480, height: 600)
        .ignoresSafeArea(edges: .top)
        .onReceive(ticker) { _ in isTrusted = StatusItemScanner.isTrusted }
    }
}

private struct BrandHeader: View {
    var body: some View {
        HStack(alignment: .bottom) {
            Image("Wordmark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: 34)
                .foregroundStyle(Brand.cream)
            Spacer()
            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Brand.cream.opacity(0.6))
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(Brand.ink)
    }
}

// MARK: - Icons page

/// Every app that has a menu bar icon, split into "visible" and "hidden".
final class IconsModel: ObservableObject {
    struct App: Identifiable {
        let id: String
        let name: String
        let icon: NSImage
        let iconCount: Int
    }

    @Published private(set) var apps: [App] = []
    @Published private(set) var hidden: Set<String> = IconLayout.hiddenApps
    @Published private(set) var isLoading = false

    func reload() {
        hidden = IconLayout.hiddenApps
        guard StatusItemScanner.isTrusted, !isLoading else { return }
        isLoading = true
        StatusItemScanner.scan { [weak self] icons in
            guard let self else { return }
            let me = Bundle.main.bundleIdentifier
            var counts: [String: Int] = [:]
            for icon in icons where icon.bundleID != me && !StatusItemScanner.isSystemOwned(icon.bundleID) {
                counts[icon.bundleID, default: 0] += 1
            }
            let running = NSWorkspace.shared.runningApplications
            // Hidden apps may not report their icons while hidden; keep them listed.
            for id in IconLayout.hiddenApps where counts[id] == nil && running.contains(where: { $0.bundleIdentifier == id }) {
                counts[id] = 0
            }
            self.apps = counts.compactMap { id, count in
                guard let app = running.first(where: { $0.bundleIdentifier == id }) else { return nil }
                let icon = app.icon ?? NSWorkspace.shared.icon(for: .application)
                return App(id: id, name: app.localizedName ?? id, icon: icon, iconCount: count)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.isLoading = false
        }
    }

    func setHidden(_ app: App, _ hide: Bool) {
        IconLayout.setHidden(app.id, hide)
        hidden = IconLayout.hiddenApps
    }
}

private struct IconsPage: View {
    let isTrusted: Bool
    @StateObject private var model = IconsModel()

    var body: some View {
        Group {
            if !HidingStrategies.usesAllowList {
                ScrollView { dragInstructions.padding(20) }
            } else if !isTrusted {
                ScrollView { PermissionGuide().padding(20) }
            } else {
                lists
            }
        }
        .onAppear { model.reload() }
        .onChange(of: isTrusted) { _, trusted in if trusted { model.reload() } }
    }

    private var visible: [IconsModel.App] { model.apps.filter { !model.hidden.contains($0.id) } }
    private var hidden: [IconsModel.App] { model.apps.filter { model.hidden.contains($0.id) } }

    private var lists: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Pick where each app's icon goes. Changes apply right away.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Look for icons again")
                        .disabled(model.isLoading)
                }

                AppSection(title: "Always visible",
                           subtitle: "Stay in the menu bar.",
                           symbol: "eye",
                           apps: visible,
                           emptyText: "Every app is hidden.",
                           actionTitle: "Hide",
                           actionSymbol: "eye.slash") { model.setHidden($0, true) }

                AppSection(title: "Hidden",
                           subtitle: "Tucked away until you click the h.",
                           symbol: "eye.slash",
                           apps: hidden,
                           emptyText: "Nothing is hidden yet. Click Hide on an app above.",
                           actionTitle: "Show",
                           actionSymbol: "eye") { model.setHidden($0, false) }

                Text("macOS's own icons (clock, Wi-Fi, battery, Control Center) always stay visible. An app with several icons shows or hides them together.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var dragInstructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Arrange by dragging", systemImage: "hand.draw").font(.headline)
            Text("On this version of macOS, hold ⌘ and drag icons to the left of the thin divider next to the h. Everything past the divider hides when you click the h.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AppSection: View {
    let title: String
    let subtitle: String
    let symbol: String
    let apps: [IconsModel.App]
    let emptyText: String
    let actionTitle: String
    let actionSymbol: String
    let action: (IconsModel.App) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(.secondary)
                Text(title).font(.headline)
                Text("\(apps.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                if apps.isEmpty {
                    Text(emptyText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    if index > 0 { Divider().padding(.leading, 46) }
                    HStack(spacing: 10) {
                        Image(nsImage: app.icon).resizable().frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name)
                            if app.iconCount > 1 {
                                Text("\(app.iconCount) icons").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button { action(app) } label: {
                            Label(actionTitle, systemImage: actionSymbol)
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

/// Step-by-step help for the Accessibility permission, including the case where
/// System Settings shows hidnr switched on but macOS still says no (it's holding
/// an entry for an older copy of the app).
private struct PermissionGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("hidnr needs Accessibility", systemImage: "lock.shield")
                .font(.headline)
            Text("It uses it only to see which apps have menu bar icons and where they sit. Nothing leaves your Mac.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Step(number: 1, text: "Click **Open Accessibility Settings** below.")
                Step(number: 2, text: "Turn on the switch next to **hidnr**.")
                Step(number: 3, text: "**Already on, but this page still asks?** macOS is holding a permission for an older copy of hidnr. Select hidnr in the list, click **–** to remove it, then click the button below again and turn the new entry on.")
            }

            Button("Open Accessibility Settings") {
                StatusItemScanner.askForTrust()
                SettingsWindow.openAccessibilityPane()
            }
            .controlSize(.large)

            Label("This page updates by itself as soon as the permission works.", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private struct Step: View {
        let number: Int
        let text: LocalizedStringKey
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .frame(width: 20, height: 20)
                    .background(Brand.accent(scheme), in: Circle())
                    .foregroundStyle(Brand.onAccent(scheme))
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - General page

private struct GeneralPage: View {
    let isTrusted: Bool
    @AppStorage(Settings.Key.hideOnLaunch) private var hideOnLaunch = true
    @AppStorage(Settings.Key.autoHide) private var autoHide = true
    @AppStorage(Settings.Key.autoHideDelay) private var autoHideDelay = 10.0
    @State private var launchAtLogin = LoginItem.isEnabled

    private let delays: [Double] = [5, 10, 15, 30, 60]

    var body: some View {
        Form {
            Section {
                Toggle("Open hidnr when I log in", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        LoginItem.setEnabled(on)
                        launchAtLogin = LoginItem.isEnabled
                    }))
                Toggle("Hide icons when hidnr starts", isOn: $hideOnLaunch)
            }
            Section {
                Toggle("Hide icons again automatically", isOn: $autoHide)
                Picker("After", selection: $autoHideDelay) {
                    ForEach(delays, id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                }
                .disabled(!autoHide)
            }
            if HidingStrategies.usesAllowList {
                Section("Permission") {
                    HStack {
                        Label(isTrusted ? "Accessibility allowed" : "Accessibility needed",
                              systemImage: isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(isTrusted ? .green : .orange)
                        Spacer()
                        if !isTrusted {
                            Button("Fix…") { SettingsWindow.show(.icons) }
                        }
                    }
                }
            }
            Section {
                Text("Click the h in your menu bar to hide or show icons. Right-click it for the quick panel. If icons ever get stuck hidden, open hidnr again from Spotlight or quit it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
