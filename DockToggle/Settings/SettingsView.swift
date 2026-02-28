import SwiftUI
import Combine

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case apps
    case about

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .apps: return "Excluded Apps"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .apps: return "app.badge.checkmark"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section {
                    ForEach(SettingsTab.allCases) { tab in
                        Label(tab.label, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .apps:
                    AppsSettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage("isEnabled") private var isEnabled = true
    @AppStorage("toggleMode") private var toggleMode = ToggleMode.minimize.rawValue
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @State private var accessibilityGranted = AccessibilityHelper.checkAccessibility()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Enable DockToggle", isOn: $isEnabled)
                Picker("Toggle mode", selection: $toggleMode) {
                    Text("Minimize windows").tag(ToggleMode.minimize.rawValue)
                    Text("Hide application").tag(ToggleMode.hide.rawValue)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        Preferences.shared.updateLoginItem(newValue)
                    }
            }

            Section("Accessibility") {
                HStack(spacing: 12) {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(accessibilityGranted ? .green : .red)
                        .imageScale(.large)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(accessibilityGranted ? "Permission granted" : "Permission required")
                        if !accessibilityGranted {
                            Text("Required to intercept Dock clicks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !accessibilityGranted {
                        Button("Grant Access") {
                            AccessibilityHelper.requestAccessibility()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onReceive(timer) { _ in
            if !accessibilityGranted {
                accessibilityGranted = AccessibilityHelper.checkAccessibility()
            }
        }
    }
}

// MARK: - Apps

struct AppsSettingsView: View {
    @State private var excludedBundleIds: [String] = Preferences.shared.excludedBundleIds
    @State private var showingAppPicker = false

    var body: some View {
        Form {
            Section {
                if excludedBundleIds.isEmpty {
                    Text("No excluded apps")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(excludedBundleIds, id: \.self) { bundleId in
                        HStack(spacing: 10) {
                            AppIconView(bundleId: bundleId)
                            if let info = appInfo(for: bundleId) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(info.name)
                                    Text(bundleId)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text(bundleId)
                                    .font(.system(.body, design: .monospaced))
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Preferences.shared.removeExclusion(bundleId)
                                excludedBundleIds = Preferences.shared.excludedBundleIds
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } footer: {
                Text("DockToggle won't intercept clicks for these apps.")
            }

            Section {
                Button {
                    showingAppPicker = true
                } label: {
                    Label("Add App…", systemImage: "plus.circle")
                }
                .popover(isPresented: $showingAppPicker, arrowEdge: .bottom) {
                    RunningAppsPicker(excludedBundleIds: $excludedBundleIds)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func appInfo(for bundleId: String) -> (name: String, icon: NSImage?)? {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
            return (app.localizedName ?? bundleId, app.icon)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let name = FileManager.default.displayName(atPath: url.path)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return (name, icon)
        }
        return nil
    }
}

// MARK: - App Icon

struct AppIconView: View {
    let bundleId: String
    private let size: CGFloat = 24

    var body: some View {
        Group {
            if let icon = resolveIcon() {
                Image(nsImage: icon)
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private func resolveIcon() -> NSImage? {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
            return app.icon
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
}

// MARK: - Running Apps Picker

struct RunningAppsPicker: View {
    @Binding var excludedBundleIds: [String]
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var availableApps: [(bundleId: String, name: String, icon: NSImage?)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String, NSImage?)? in
                guard let bundleId = app.bundleIdentifier,
                      !excludedBundleIds.contains(bundleId) else { return nil }
                return (bundleId, app.localizedName ?? bundleId, app.icon)
            }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    private var filteredApps: [(bundleId: String, name: String, icon: NSImage?)] {
        if searchText.isEmpty { return availableApps }
        return availableApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleId.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search apps…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(10)

            Divider()

            if filteredApps.isEmpty {
                Text("No apps found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                List(filteredApps, id: \.bundleId) { app in
                    Button {
                        Preferences.shared.addExclusion(app.bundleId)
                        excludedBundleIds = Preferences.shared.excludedBundleIds
                    } label: {
                        HStack(spacing: 10) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                Text(app.bundleId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 320, height: 360)
    }
}

// MARK: - About

struct AboutSettingsView: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
            Text("DockToggle")
                .font(.title2.bold())
            Text("Version \(version) (\(build))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Windows-like Dock toggle for macOS")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\u{00A9} 2026 DockToggle")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
    }
}
