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

nonisolated final class DockWatcher: @unchecked Sendable {
    static let shared = DockWatcher()

    private struct State: Sendable {
        var items: [DockItem] = []
    }

    private let lock = OSAllocatedUnfairLock<State>(initialState: State())
    private var refreshTimer: Timer?
    private var debounceTimer: Timer?

    var dockItems: [DockItem] {
        lock.withLock { $0.items }
    }

    private init() {}

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
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
            let items = Self.getDockItems()
            #if DEBUG
            print("[DockWatcher] Found \(items.count) dock items")
            for item in items {
                print("  - \"\(item.title)\" bundle=\(item.bundleIdentifier ?? "nil") frame=\(item.frame) subrole=\(item.subrole ?? "nil")")
            }
            #endif
            self?.lock.withLock { $0.items = items }
        }
    }

    static func getDockItems() -> [DockItem] {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return []
        }

        let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return []
        }

        var items: [DockItem] = []

        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            guard let role = roleRef as? String, role == "AXList" else { continue }

            var listChildrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &listChildrenRef) == .success,
                  let listChildren = listChildrenRef as? [AXUIElement] else { continue }

            for element in listChildren {
                guard let item = parseDockElement(element) else { continue }
                items.append(item)
            }
        }

        return items
    }

    private static func parseDockElement(_ element: AXUIElement) -> DockItem? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var titleRef: CFTypeRef?
        var subroleRef: CFTypeRef?
        var urlRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard let posRef, CFGetTypeID(posRef) == AXValueGetTypeID(),
              let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return nil
        }
        // swiftlint:disable:next force_cast
        let posValue = posRef as! AXValue
        // swiftlint:disable:next force_cast
        let sizeValue = sizeRef as! AXValue
        AXValueGetValue(posValue, .cgPoint, &position)
        AXValueGetValue(sizeValue, .cgSize, &size)

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

        let frame = CGRect(origin: position, size: size)
        return DockItem(frame: frame, title: title, bundleIdentifier: bundleIdentifier, url: url, subrole: subrole)
    }
}
