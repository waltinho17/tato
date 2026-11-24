import AppKit
import ObjectiveC

// Private Touch Bar / Control Strip APIs, resolved at runtime (no bridging header).
// Same calls MTMR uses: addSystemTrayItem + DFRElementSetControlStripPresenceForIdentifier.

enum PrivateTouchBar {
    private typealias SetPresenceFn = @convention(c) (NSString, Bool) -> Void
    private typealias CloseBoxFn = @convention(c) (Bool) -> Void

    private static let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)
    private static let setPresenceFn: SetPresenceFn? =
        dfr.flatMap { dlsym($0, "DFRElementSetControlStripPresenceForIdentifier") }.map { unsafeBitCast($0, to: SetPresenceFn.self) }
    private static let closeBoxFn: CloseBoxFn? =
        dfr.flatMap { dlsym($0, "DFRSystemModalShowsCloseBoxWhenFrontMost") }.map { unsafeBitCast($0, to: CloseBoxFn.self) }

    static var functionsAvailable: Bool { setPresenceFn != nil && closeBoxFn != nil }

    static func setControlStripPresence(_ id: NSTouchBarItem.Identifier, _ present: Bool) {
        guard let f = setPresenceFn else { NSLog("TouchBarTemp: DFRElementSetControlStripPresenceForIdentifier unavailable"); return }
        f(id.rawValue as NSString, present)
    }

    static func setShowsCloseBox(_ shows: Bool) {
        guard let f = closeBoxFn else { NSLog("TouchBarTemp: DFRSystemModalShowsCloseBoxWhenFrontMost unavailable"); return }
        f(shows)
    }

    private static func classMethod(_ cls: AnyClass, _ name: String) -> IMP? {
        guard let m = class_getClassMethod(cls, NSSelectorFromString(name)) else {
            NSLog("TouchBarTemp: missing class method %@", name); return nil
        }
        return method_getImplementation(m)
    }

    static func addSystemTrayItem(_ item: NSTouchBarItem) {
        guard let imp = classMethod(NSTouchBarItem.self, "addSystemTrayItem:") else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        unsafeBitCast(imp, to: Fn.self)(NSTouchBarItem.self, NSSelectorFromString("addSystemTrayItem:"), item)
    }

    static func removeSystemTrayItem(_ item: NSTouchBarItem) {
        guard let imp = classMethod(NSTouchBarItem.self, "removeSystemTrayItem:") else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        unsafeBitCast(imp, to: Fn.self)(NSTouchBarItem.self, NSSelectorFromString("removeSystemTrayItem:"), item)
    }

    static func present(_ bar: NSTouchBar, trayItem id: NSTouchBarItem.Identifier) {
        guard let imp = classMethod(NSTouchBar.self, "presentSystemModalTouchBar:systemTrayItemIdentifier:") else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, NSString) -> Void
        unsafeBitCast(imp, to: Fn.self)(NSTouchBar.self, NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:"), bar, id.rawValue as NSString)
    }

    static func minimize(_ bar: NSTouchBar) {
        guard let imp = classMethod(NSTouchBar.self, "minimizeSystemModalTouchBar:") else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        unsafeBitCast(imp, to: Fn.self)(NSTouchBar.self, NSSelectorFromString("minimizeSystemModalTouchBar:"), bar)
    }
}
