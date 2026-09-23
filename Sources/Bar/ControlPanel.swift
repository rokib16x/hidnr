import AppKit
import Combine
import SwiftUI

/// Live state the control panel shows. `BarController` keeps it current.
final class PanelModel: ObservableObject {
    @Published var isHiding = false
    @Published var hiddenCount: Int?
    @Published var problem: String?
    @Published var needsAccessibility = false
    /// A gentle suggestion (not an error), e.g. to install hidnr properly.
    @Published var tip: String?

    var toggle: () -> Void = {}
    var openSettings: () -> Void = {}
    var organize: () -> Void = {}
    var grantAccess: () -> Void = {}
    /// Called every second while the panel is open, so state (like a permission
    /// granted in System Settings) shows up without reopening it.
    var poll: () -> Void = {}
}

/// hidnr's own panel, opened by right-clicking its menu bar icon.
struct ControlPanel: View {
    @ObservedObject var model: PanelModel
    @AppStorage(Settings.Key.autoHide) private var autoHide = true
    @AppStorage(Settings.Key.autoHideDelay) private var autoHideDelay = 10.0
    @Environment(\.colorScheme) private var scheme

    private let delays: [Double] = [5, 10, 30, 60]
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Image("Wordmark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 26)
                    .foregroundStyle(Brand.text(scheme))
                Spacer()
                StatusPill(model: model)
            }

            Button(action: model.toggle) {
                HStack {
                    Image(systemName: model.isHiding ? "eye" : "eye.slash")
                    Text(model.isHiding ? "Show icons" : "Hide icons")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("click the h")
                        .font(.caption)
                        .opacity(0.6)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .frame(maxWidth: .infinity)
                .foregroundStyle(Brand.onAccent(scheme))
                .background(Brand.accent(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            if let problem = model.problem {
                ProblemBanner(text: problem, showsGrant: model.needsAccessibility, grant: model.grantAccess)
            } else if let tip = model.tip {
                Label(tip, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: model.organize) {
                HStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2")
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Organize icons").fontWeight(.medium)
                        Text("Choose which apps stay visible")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .contentShape(Rectangle())
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Text("Hide again after")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Chip(title: "Never", selected: !autoHide) { autoHide = false }
                    ForEach(delays, id: \.self) { delay in
                        Chip(title: delay < 60 ? "\(Int(delay))s" : "1m",
                             selected: autoHide && autoHideDelay == delay) {
                            autoHideDelay = delay
                            autoHide = true
                        }
                    }
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Divider()

            HStack {
                Button { model.openSettings() } label: { Label("Settings", systemImage: "gearshape") }
                Spacer()
                Button { NSApp.terminate(nil) } label: { Label("Quit", systemImage: "power") }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(16)
        .frame(width: 300)
        .onReceive(ticker) { _ in model.poll() }
    }
}

enum Brand {
    static let ink = Color(red: 0x12 / 255, green: 0x14 / 255, blue: 0x2b / 255)
    static let cream = Color(red: 0xf7 / 255, green: 0xf5 / 255, blue: 0xef / 255)

    static func text(_ scheme: ColorScheme) -> Color { scheme == .dark ? cream : ink }
    static func accent(_ scheme: ColorScheme) -> Color { scheme == .dark ? cream : ink }
    static func onAccent(_ scheme: ColorScheme) -> Color { scheme == .dark ? ink : cream }
}

private struct StatusPill: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        let label: String = {
            guard model.isHiding else { return "All visible" }
            guard let count = model.hiddenCount else { return "Hiding" }
            return count == 1 ? "1 app hidden" : "\(count) apps hidden"
        }()
        HStack(spacing: 5) {
            Circle()
                .fill(model.isHiding ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Text(label).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.6), in: Capsule())
    }
}

private struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 24)
                .foregroundStyle(selected ? Brand.onAccent(scheme) : .primary)
                .background(selected ? AnyShapeStyle(Brand.accent(scheme)) : AnyShapeStyle(.background.opacity(0.6)),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ProblemBanner: View {
    let text: String
    let showsGrant: Bool
    let grant: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if showsGrant {
                    Button("Allow Accessibility", action: grant)
                        .controlSize(.small)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
