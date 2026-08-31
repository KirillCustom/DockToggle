import Cocoa
import ApplicationServices
import os.lock

struct DockItem: Sendable {
    let frame: CGRect
    let title: String
    let bundleIdentifier: String?
    let url: URL?
    let subrole: String?
}

/// Which of a Dock icon's two axes actually tracks the pointer. The Dock's AX frames have
/// been observed shifted on the short axis on newer macOS, so hit-testing trusts only this one.
nonisolated enum DockOrientation: Sendable {
    case horizontal
    case vertical
}

nonisolated final class DockWatcher: @unchecked Sendable {
    static let shared = DockWatcher()

    private struct State: Sendable {
        var items: [DockItem] = []
        var orientation: DockOrientation = .horizontal
    }

    private let lock = OSAllocatedUnfairLock<State>(initialState: State())
    private var refreshTimer: Timer?
    private var debounceTimer: Timer?

    var dockItems: [DockItem] {
        lock.withLock { $0.items }
    }

    var orientation: DockOrientation {
        lock.withLock { $0.orientation }
    }

    private init() {}

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard refreshTimer == nil else { return }
        refresh()
        setupNotifications()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        refreshTimer?.invalidate()
        refreshTimer = nil
        debounceTimer?.invalidate()
        debounceTimer = nil
        let center = NSWorkspace.shared.notificationCenter
        center.removeObserver(self)
    }

    private func setupNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in names {
            center.addObserver(self, selector: #selector(onDockChanged), name: name, object: nil)
        }
    }

    @objc private func onDockChanged() {
        debounceRefresh()
    }

    private func debounceRefresh() {
        DispatchQueue.main.async { [weak self] in
            self?.debounceTimer?.invalidate()
            self?.debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                self?.refresh()
            }
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.getDockItems()
            #if DEBUG
            print("[DockWatcher] Found \(result.items.count) dock items, orientation=\(result.orientation)")
            for item in result.items {
                print("  - \"\(item.title)\" bundle=\(item.bundleIdentifier ?? "nil") frame=\(item.frame) subrole=\(item.subrole ?? "nil")")
            }
            #endif
            self?.lock.withLock {
                $0.items = result.items
                $0.orientation = result.orientation
            }
        }
    }

    /// Asks the Dock what is actually under the pointer right now. Unlike the cached frames
    /// this survives magnification and rearranging, but it is AX IPC — never call it from
    /// the event tap callback.
    ///
    /// Walks the Dock's own item list rather than using `AXUIElementCopyElementAtPosition`,
    /// and matches only along the Dock's long axis: position-based AX hit-testing here has
    /// been observed unreliable on the short axis on newer macOS, while the long-axis
    /// coordinates stay truthful.
    static func itemAt(point: CGPoint) -> DockItem? {
        guard AXIsProcessTrusted(), let dockElement = dockApplicationElement() else { return nil }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        for child in children where roleString(child) == "AXList" {
            guard let listFrame = axFrame(child),
                  let listChildren = elementArray(child, kAXChildrenAttribute) else { continue }
            let horizontal = listFrame.width >= listFrame.height

            for element in listChildren {
                guard let frame = axFrame(element),
                      DockGeometry.longAxisContains(point, itemFrame: frame, horizontal: horizontal) else { continue }
                return parseDockElement(element)
            }
        }
        return nil
    }

    private static func dockApplicationElement() -> AXUIElement? {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }
        return AXUIElementCreateApplication(dockApp.processIdentifier)
    }

    static func getDockItems() -> (items: [DockItem], orientation: DockOrientation) {
        guard let dockElement = dockApplicationElement() else {
            return ([], .horizontal)
        }

        guard let children = elementArray(dockElement, kAXChildrenAttribute) else {
            return ([], .horizontal)
        }

        var items: [DockItem] = []
        var orientation: DockOrientation = .horizontal

        for child in children where roleString(child) == "AXList" {
            if let listFrame = axFrame(child) {
                orientation = listFrame.width >= listFrame.height ? .horizontal : .vertical
            }

            guard let listChildren = elementArray(child, kAXChildrenAttribute) else { continue }

            for element in listChildren {
                guard let item = parseDockElement(element) else { continue }
                items.append(item)
            }
        }

        return (items, orientation)
    }

    private static func roleString(_ element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        return roleRef as? String
    }

    private static func elementArray(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else { return nil }
        return array
    }

    private static func axFrame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, CFGetTypeID(posRef) == AXValueGetTypeID(),
              let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue((posRef as! AXValue), .cgPoint, &position)
        // swiftlint:disable:next force_cast
        AXValueGetValue((sizeRef as! AXValue), .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    private static func parseDockElement(_ element: AXUIElement) -> DockItem? {
        guard let frame = axFrame(element) else { return nil }

        var titleRef: CFTypeRef?
        var subroleRef: CFTypeRef?
        var urlRef: CFTypeRef?

        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String ?? ""

        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        let subrole = subroleRef as? String

        AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlRef)
        var url: URL?
        var bundleIdentifier: String?
        if let urlRef, CFGetTypeID(urlRef as CFTypeRef) == CFURLGetTypeID() {
            // swiftlint:disable:next force_cast
            let nsURL = (urlRef as! CFURL) as URL
            url = nsURL
            if let bundle = Bundle(url: nsURL) {
                bundleIdentifier = bundle.bundleIdentifier
            }
        }

        return DockItem(frame: frame, title: title, bundleIdentifier: bundleIdentifier, url: url, subrole: subrole)
    }
}
