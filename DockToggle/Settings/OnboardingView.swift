import SwiftUI
import Combine

// MARK: - Draggable App Icon (NSViewRepresentable)

struct DraggableAppIcon: NSViewRepresentable {
    let size: CGFloat

    func makeNSView(context: Context) -> DraggableIconView {
        let view = DraggableIconView(iconSize: size)
        return view
    }

    func updateNSView(_ nsView: DraggableIconView, context: Context) {}
}

final class DraggableIconView: NSView, NSDraggingSource {
    init(iconSize: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: iconSize, height: iconSize))
        let imageView = NSImageView(frame: bounds)
        imageView.image = NSApp.applicationIconImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let bundleURL = Bundle.main.bundleURL as NSURL
        let draggingItem = NSDraggingItem(pasteboardWriter: bundleURL)
        let iconImage = NSApp.applicationIconImage ?? NSImage()
        draggingItem.setDraggingFrame(bounds, contents: iconImage)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var page = 0
    @State private var accessibilityGranted = AccessibilityHelper.checkAccessibility()
    @State private var showDragHint = false

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

            ZStack {
                DraggableAppIcon(size: 80)
                    .frame(width: 80, height: 80)
                    .shadow(color: .accentColor.opacity(showDragHint ? 0.4 : 0), radius: 12)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: showDragHint)

                if showDragHint {
                    Image(systemName: "arrow.up.right")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                        .offset(x: 50, y: -40)
                        .transition(.opacity)
                }
            }

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

                Text("or drag the app icon into\nSystem Settings → Accessibility")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, 48)
        .onReceive(timer) { _ in
            if !accessibilityGranted {
                accessibilityGranted = AccessibilityHelper.checkAccessibility()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !accessibilityGranted && !showDragHint {
                withAnimation { showDragHint = true }
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
