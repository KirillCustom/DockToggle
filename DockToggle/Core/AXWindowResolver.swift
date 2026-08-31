import ApplicationServices
import Darwin

/// Resolves an `AXUIElement` window to its `CGWindowID` via the undocumented
/// `_AXUIElementGetWindow`. There is still no public API for this; it is what every
/// AX-based window manager on macOS relies on for the same reason (Rectangle, Contexts, and
/// others all resolve it the same way).
///
/// Looked up with `dlsym` rather than linked directly: if some future macOS renames or
/// removes the symbol, the lookup returns nil once at startup and every caller here already
/// treats "no window ID" as "skip the z-order refinement" rather than crashing or failing to
/// launch.
nonisolated enum AXWindowResolver {
    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    /// `RTLD_DEFAULT` — not reliably visible as a Swift symbol across SDKs since it is a C
    /// macro, so its known pointer value is used directly.
    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

    private static let getWindow: GetWindowFn? = {
        guard let symbol = dlsym(rtldDefault, "_AXUIElementGetWindow") else {
            return nil
        }
        return unsafeBitCast(symbol, to: GetWindowFn.self)
    }()

    static func windowID(for element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var windowID: CGWindowID = 0
        guard getWindow(element, &windowID) == .success else { return nil }
        return windowID
    }
}
