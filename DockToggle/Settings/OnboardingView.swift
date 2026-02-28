import SwiftUI
import Combine

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var page = 0
    @State private var accessibilityGranted = AccessibilityHelper.checkAccessibility()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let totalPages = 3

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcomePage
                case 1: accessibilityPage
                case 2: readyPage
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Text("Step \(page + 1) of \(totalPages)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                if page > 0 {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.2)) { page -= 1 }
                    }
                    .keyboardShortcut(.cancelAction)
                }
                if page < totalPages - 1 {
                    Button("Continue") {
                        withAnimation(.easeInOut(duration: 0.2)) { page += 1 }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get Started") { onComplete() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 28)
        }
        .frame(width: 500, height: 400)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "dock.rectangle")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Welcome to DockToggle")
                .font(.title.bold())

            Text("Brings Windows-like behavior to your Dock.\nClick an active app's icon to minimize it.\nClick again to restore.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            Spacer()
        }
        .padding(.horizontal, 48)
    }

    private var accessibilityPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

            Text("Accessibility Permission")
                .font(.title2.bold())

            Text("DockToggle needs Accessibility access to detect\nDock clicks and control app windows.\n\nEverything stays on your Mac — no data is collected.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            if accessibilityGranted {
                Label("Permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body.weight(.medium))
            } else {
                Button("Grant Accessibility Access") {
                    AccessibilityHelper.requestAccessibility()
                }
                .controlSize(.large)
            }
            Spacer()
        }
        .padding(.horizontal, 48)
        .onReceive(timer) { _ in
            if !accessibilityGranted {
                accessibilityGranted = AccessibilityHelper.checkAccessibility()
            }
        }
    }

    private var readyPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title2.bold())

            Text("DockToggle will run quietly in your menu bar.\nClick any active app in the Dock to minimize it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            HStack(spacing: 6) {
                Image(systemName: "dock.rectangle")
                Text("Look for this icon in the menu bar")
            }
            .foregroundStyle(.secondary)
            .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 48)
    }
}
