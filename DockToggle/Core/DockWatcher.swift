import Cocoa
import ApplicationServices

struct DockItem: Sendable {
    let frame: CGRect
    let title: String
    let bundleIdentifier: String?
    let url: URL?
    let subrole: String?
}

nonisolated final class DockWatcher: @unchecked Sendable {
    static let shared = DockWatcher()

    nonisolated(unsafe) private(set) var dockItems: [DockItem] = []
    private var refreshTimer: Timer?
    private var debounceTimer: Timer?

    private init() {}

    func start() {
        refresh()
        setupNotifications()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
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
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = Self.getDockItems()
            print("[DockWatcher] Found \(items.count) dock items")
            for item in items {
                print("  - \"\(item.title)\" bundle=\(item.bundleIdentifier ?? "nil") frame=\(item.frame) subrole=\(item.subrole ?? "nil")")
            }
            DispatchQueue.main.async {
                self?.dockItems = items
            }
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
        AXValueGetValue(posRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String ?? ""

        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        let subrole = subroleRef as? String

        AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlRef)
        var url: URL?
        var bundleIdentifier: String?
        if let urlValue = urlRef {
            if let cfURL = urlValue as! CFURL? {
                let nsURL = cfURL as URL
                url = nsURL
                if let bundle = Bundle(url: nsURL) {
                    bundleIdentifier = bundle.bundleIdentifier
                }
            }
        }

        let frame = CGRect(origin: position, size: size)
        return DockItem(frame: frame, title: title, bundleIdentifier: bundleIdentifier, url: url, subrole: subrole)
    }
}
