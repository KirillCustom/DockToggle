import CoreGraphics

/// The window server's own front-to-back window order — AX-free and cheap, and the only
/// place this stacking can be read at all: the AX windows array does not reliably report it.
nonisolated enum OnScreenWindows {
    static func ids(forPID pid: pid_t) -> [CGWindowID] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                     kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return info.compactMap { entry -> CGWindowID? in
            guard entry[kCGWindowOwnerPID as String] as? pid_t == pid,
                  entry[kCGWindowLayer as String] as? Int == 0,
                  let number = entry[kCGWindowNumber as String] as? CGWindowID else { return nil }
            return number
        }
    }
}
