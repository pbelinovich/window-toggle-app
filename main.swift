import AppKit
import ApplicationServices

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
    return result
}

func windowFrame(_ window: AXUIElement) -> CGRect? {
    guard let position = attribute(window, kAXPositionAttribute),
          let size = attribute(window, kAXSizeAttribute),
          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    var s = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &p),
          AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
    return CGRect(origin: p, size: s)
}

func setFrame(_ window: AXUIElement, _ frame: CGRect) -> Bool {
    var p = frame.origin
    var s = frame.size
    let position = AXValueCreate(.cgPoint, &p)!
    let size = AXValueCreate(.cgSize, &s)!
    // Some applications apply AX changes asynchronously. Verify actual geometry,
    // instead of treating acceptance of the request as a completed resize.
    for _ in 0..<10 {
        _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size)
        _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size)
        Thread.sleep(forTimeInterval: 0.06)
        if let actual = windowFrame(window), closeFrame(actual, frame) { return true }
    }
    return false
}

func closeFrame(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 &&
    abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
}

func axRect(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
}

func split(_ rect: CGRect) -> [CGRect] {
    let half = floor(rect.width / 2)
    return [CGRect(x: rect.minX, y: rect.minY, width: half, height: rect.height),
            CGRect(x: rect.minX + half, y: rect.minY, width: rect.width - half, height: rect.height)]
}

func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }

func visibleScreens() -> [CGRect] {
    guard let first = NSScreen.screens.first else { return [] }
    return NSScreen.screens.map { axRect($0.visibleFrame, primaryTop: first.frame.maxY) }
}

func bestScreen(_ frame: CGRect, in screens: [CGRect]) -> CGRect {
    screens.max { area($0.intersection(frame)) < area($1.intersection(frame)) }!
}

func contained(_ frame: CGRect, in screen: CGRect) -> CGRect {
    let w = min(frame.width, screen.width), h = min(frame.height, screen.height)
    return CGRect(x: max(screen.minX, min(frame.minX, screen.maxX - w)),
                  y: max(screen.minY, min(frame.minY, screen.maxY - h)), width: w, height: h)
}

func layoutTargets(frames: [CGRect], screens: [CGRect], expanded: Bool) -> [CGRect] {
    let firstScreen = bestScreen(frames[0], in: screens)
    if screens.count > 1 {
        return [firstScreen, bestScreen(frames[1], in: screens.filter { $0 != firstScreen })]
    }
    return expanded ? [firstScreen, firstScreen] : split(firstScreen)
}

func standardWindows(_ app: NSRunningApplication) -> [AXUIElement] {
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 1)
    return (attribute(element, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter {
        (attribute($0, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole &&
        (attribute($0, kAXMinimizedAttribute) as? Bool) != true && windowFrame($0) != nil
    }
}

final class Controller: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var status: NSStatusItem!
    var contextMenu: NSMenu!
    var toggleItem: NSMenuItem!
    var swapItem: NSMenuItem!
    var expandItem: NSMenuItem!
    var applicationItem: NSMenuItem!
    var menuApp: NSRunningApplication?
    var lastApp: NSRunningApplication?
    var activationObserver: NSObjectProtocol?
    var busy = false
    var testing = false

    func activeApp() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() {
            lastApp = front
        }
        return lastApp?.isTerminated == false ? lastApp : nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        lastApp = NSWorkspace.shared.frontmostApplication
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.processIdentifier != getpid() { self?.lastApp = app }
        }
        status = NSStatusBar.system.statusItem(withLength: 22)
        let icon = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor.labelColor.setStroke()
            let outer = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 2), xRadius: 2, yRadius: 2)
            outer.lineWidth = 1.1
            outer.stroke()
            let divider = NSBezierPath()
            divider.lineWidth = 1.1
            divider.move(to: NSPoint(x: 7, y: 2))
            divider.line(to: NSPoint(x: 7, y: 12))
            divider.stroke()
            return true
        }
        icon.isTemplate = true
        status.button?.image = icon
        status.button?.imageScaling = .scaleNone
        status.button?.toolTip = "Выровнять два окна активного приложения. Правый клик — меню."
        status.button?.target = self
        status.button?.action = #selector(clicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        contextMenu = NSMenu()
        contextMenu.autoenablesItems = false
        contextMenu.delegate = self
        applicationItem = contextMenu.addItem(withTitle: "Приложение: —", action: nil, keyEquivalent: "")
        applicationItem.isEnabled = false
        contextMenu.addItem(NSMenuItem.separator())
        toggleItem = contextMenu.addItem(withTitle: "Выровнять два окна", action: #selector(toggle(_:)), keyEquivalent: "")
        toggleItem.target = self
        expandItem = contextMenu.addItem(withTitle: "Расширить окна", action: #selector(expand(_:)), keyEquivalent: "")
        expandItem.target = self
        swapItem = contextMenu.addItem(withTitle: "Поменять окна местами", action: #selector(swap(_:)), keyEquivalent: "")
        swapItem.target = self
        let permissionItem = contextMenu.addItem(withTitle: "Разрешение на управление окнами…", action: #selector(openPermissions), keyEquivalent: "")
        permissionItem.target = self
        contextMenu.addItem(NSMenuItem.separator())
        let quitItem = contextMenu.addItem(withTitle: "Завершить", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        if !AXIsProcessTrusted() {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menuApp = activeApp()
        toggleItem.title = "Выровнять два окна"
        if let app = menuApp {
            applicationItem.title = "Приложение: \(app.localizedName ?? "без названия")"
            applicationItem.image = app.icon
            applicationItem.image?.size = NSSize(width: 16, height: 16)
            toggleItem.isEnabled = true
            swapItem.isEnabled = true
            expandItem.isEnabled = true
        } else {
            applicationItem.title = "Приложение не выбрано"
            applicationItem.image = nil
            toggleItem.isEnabled = false
            swapItem.isEnabled = false
            expandItem.isEnabled = false
        }
    }

    @objc func clicked() {
        _ = activeApp()
        if NSApp.currentEvent?.type == .rightMouseUp {
            guard let button = status.button else { return }
            contextMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        } else { toggle(nil) }
    }

    func message(_ title: String, _ detail: String) {
        if testing { print("ERROR: \(title): \(detail)"); return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func quit() { NSApp.terminate(nil) }
    func commandApp(_ sender: Any?) -> NSRunningApplication? {
        let app = sender is NSMenuItem ? menuApp : activeApp()
        return app?.isTerminated == false ? app : nil
    }

    @objc func toggle(_ sender: Any?) {
        guard let app = commandApp(sender) else { return }
        performToggle(app)
    }

    @objc func swap(_ sender: Any?) {
        guard let app = commandApp(sender) else { return }
        performSwap(app)
    }

    func performSwap(_ app: NSRunningApplication) {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        guard AXIsProcessTrusted() else {
            message("Разреши управление окнами", "Включи Window Toggle в настройках macOS → Конфиденциальность и безопасность → Универсальный доступ.")
            if !testing { openPermissions() }
            return
        }
        let windows = Array(standardWindows(app).prefix(2))
        guard windows.count == 2,
              let first = windowFrame(windows[0]), let second = windowFrame(windows[1]) else {
            message("Нужны два окна", "Открой два обычных окна активного приложения.")
            return
        }
        guard !windows.contains(where: {
            (attribute($0, "AXFullScreen") as? Bool) == true ||
            (attribute($0, kAXMinimizedAttribute) as? Bool) == true
        }) else {
            message("Разверни оба окна", "Выйди из полноэкранного режима и разверни свёрнутые окна.")
            return
        }
        let firstMoved = setFrame(windows[0], second)
        let secondMoved = setFrame(windows[1], first)
        if !firstMoved || !secondMoved {
            _ = setFrame(windows[0], first)
            _ = setFrame(windows[1], second)
            message("Не удалось поменять окна местами", "Приложение ограничивает размер или перемещение окон.")
        }
    }

    @objc func expand(_ sender: Any?) {
        guard let app = commandApp(sender) else { return }
        performLayout(app, expanded: true)
    }

    func performToggle(_ app: NSRunningApplication) {
        performLayout(app, expanded: false)
    }

    func performLayout(_ app: NSRunningApplication, expanded: Bool) {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        guard AXIsProcessTrusted() else {
            message("Разреши управление окнами", "Включи Window Toggle в настройках macOS → Privacy & Security → Accessibility. Затем снова нажми значок.")
            if !testing { openPermissions() }
            return
        }
        let screens = visibleScreens()
        guard !screens.isEmpty else { return }
        let windows = standardWindows(app)
        guard windows.count >= 2 else {
            message("Нужны два окна", "Открой два обычных окна приложения «\(app.localizedName ?? "")», разверни свёрнутые окна и снова нажми значок.")
            return
        }
        // Position, rather than focus order, determines which window stays left.
        let selected = Array(windows.prefix(2)).sorted {
            let a = windowFrame($0)!, b = windowFrame($1)!
            return a.minX == b.minX ? a.minY < b.minY : a.minX < b.minX
        }
        if selected.contains(where: { (attribute($0, "AXFullScreen") as? Bool) == true }) {
            message("Выйди из полноэкранного режима", "Для изменения размеров нужны обычные окна приложения.")
            return
        }
        let targets = layoutTargets(frames: selected.map { windowFrame($0)! }, screens: screens, expanded: expanded)
        var success = true
        for (window, target) in zip(selected, targets) {
            if !setFrame(window, target) { success = false }
        }
        if !success {
            message("Приложение ограничивает размер окна", "Не все окна приняли нужные размеры.")
        }
    }

}

if CommandLine.arguments.contains("--self-test") {
    let normal = CGRect(x: 0, y: 25, width: 1512, height: 900)
    let halves = split(normal)
    precondition(halves[0].maxX == halves[1].minX && halves[1].maxX == normal.maxX)
    precondition(halves[0].width == halves[1].width)
    let odd = split(CGRect(x: -1200, y: -800, width: 1199, height: 800))
    precondition(odd[0].width + odd[1].width == 1199 && odd[0].maxX == odd[1].minX)
    precondition(axRect(CGRect(x: -1200, y: 900, width: 1200, height: 800), primaryTop: 900).minY == -800)
    precondition(normal.contains(contained(CGRect(x: 2500, y: -800, width: 2000, height: 1400), in: normal)))
    let external = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
    let frames = [CGRect(x: 10, y: 40, width: 500, height: 400), CGRect(x: -1800, y: -100, width: 500, height: 400)]
    precondition(layoutTargets(frames: frames, screens: [normal, external], expanded: true) == [normal, external])
    precondition(layoutTargets(frames: frames, screens: [normal, external], expanded: false) == [normal, external])
    precondition(layoutTargets(frames: frames, screens: [normal], expanded: true) == [normal, normal])
    print("PASS: halves, odd widths, negative coordinates, one-screen expansion, two-screen layouts")
    exit(0)
}
if CommandLine.arguments.contains("--diagnose") {
    print("Accessibility: \(AXIsProcessTrusted()); displays: \(visibleScreens())")
    if AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication {
        let windows = standardWindows(app)
        print("Active app: \(app.localizedName ?? "unknown"); windows: \(windows.count)")
        for window in windows { print("Frame: \(String(describing: windowFrame(window)))") }
    }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
if CommandLine.arguments.contains("--integration-test") {
    guard AXIsProcessTrusted() else { print("SKIP: Accessibility permission required"); exit(2) }
    app.finishLaunching()
    let screen = NSScreen.screens.first!.visibleFrame
    let first = NSWindow(contentRect: CGRect(x: screen.minX + 70, y: screen.minY + 100, width: 510, height: 430),
                         styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
    let second = NSWindow(contentRect: CGRect(x: screen.minX + 650, y: screen.minY + 170, width: 620, height: 510),
                          styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
    first.title = "Window Toggle verification A"
    second.title = "Window Toggle verification B"
    first.orderFront(nil)
    second.orderFront(nil)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
    let ownApp = NSRunningApplication.current
    let windows = standardWindows(ownApp)
    precondition(windows.count == 2, "Fixture needs exactly two windows")
    let test = Controller()
    test.testing = true
    test.performToggle(ownApp)
    let expected = visibleScreens().count == 1 ? split(visibleScreens()[0]) : visibleScreens()
    for window in windows {
        precondition(expected.contains(where: { closeFrame(windowFrame(window)!, $0) }), "Window was not tiled")
    }
    let beforeSwap = windows.map { windowFrame($0)! }
    test.performSwap(ownApp)
    precondition(closeFrame(windowFrame(windows[0])!, beforeSwap[1]), "First window did not swap")
    precondition(closeFrame(windowFrame(windows[1])!, beforeSwap[0]), "Second window did not swap")
    let swapped = windows.map { windowFrame($0)! }
    first.orderFront(nil)
    test.performToggle(ownApp)
    for (window, frame) in zip(windows, swapped) {
        precondition(closeFrame(windowFrame(window)!, frame), "Align after swap must preserve positions")
    }
    test.performToggle(ownApp)
    for (window, frame) in zip(windows, swapped) {
        precondition(closeFrame(windowFrame(window)!, frame), "Repeated alignment must be idempotent")
    }
    test.performLayout(ownApp, expanded: true)
    let screens = visibleScreens()
    for window in windows {
        precondition(screens.contains(where: { closeFrame(windowFrame(window)!, $0) }), "Expanded window must fill available screen")
    }
    test.performToggle(ownApp)
    let aligned = windows.map { windowFrame($0)! }
    precondition(!closeFrame(aligned[0], aligned[1]), "Alignment must separate expanded windows")
    print("PASS: align, swap, align preserves swapped positions, repeat alignment, expand, align again")
    exit(0)
}
let controller = Controller()
app.delegate = controller
app.run()
