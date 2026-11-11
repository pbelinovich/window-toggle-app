import AppKit
import ApplicationServices
import Carbon

let warpID = "dev.warp.Warp-Stable"

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
    // Shrink before moving so a large window can cross onto a smaller display.
    _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size)
    let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size)
    return moved == .success && resized == .success
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

struct SavedWindow {
    let element: AXUIElement
    let frame: CGRect
}

final class Controller: NSObject, NSApplicationDelegate {
    var status: NSStatusItem!
    var hotKey: EventHotKeyRef?
    var eventHandler: EventHandlerRef?
    var saved: [SavedWindow] = []
    var savedScreens: [CGRect] = []
    var busy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "◧"
        status.button?.toolTip = "Warp Window Toggle — ⌃⌥⌘W"
        let menu = NSMenu()
        let toggleItem = menu.addItem(withTitle: "Разложить / вернуть окна Warp (⌃⌥⌘W)", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        let permissionItem = menu.addItem(withTitle: "Разрешение на управление окнами…", action: #selector(openPermissions), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(NSMenuItem.separator())
        let quitItem = menu.addItem(withTitle: "Завершить", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        status.menu = menu
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<Controller>.fromOpaque(context).takeUnretainedValue().toggle()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_W), UInt32(controlKey | optionKey | cmdKey),
            EventHotKeyID(signature: 0x57575447, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr { message("Не удалось назначить ⌃⌥⌘W", "Возможно, сочетание уже занято другой программой. Код: \(result).") }
        if !AXIsProcessTrusted() {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
    }

    func message(_ title: String, _ detail: String) {
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

    @objc func toggle() {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        guard AXIsProcessTrusted() else {
            message("Разреши управление окнами", "В настройках macOS включи Warp Window Toggle в разделе «Конфиденциальность и безопасность → Универсальный доступ», затем снова нажми ⌃⌥⌘W.")
            openPermissions()
            return
        }
        let screens = visibleScreens()
        guard !screens.isEmpty else { return }
        if !saved.isEmpty {
            var failed: [SavedWindow] = []
            for item in saved {
                guard windowFrame(item.element) != nil else { continue } // Closed windows need no restoration.
                let target = screens == savedScreens || screens.contains(where: { $0.contains(item.frame) })
                    ? item.frame : contained(item.frame, in: bestScreen(item.frame, in: screens))
                if !setFrame(item.element, target) { failed.append(item) }
            }
            saved = failed
            if !failed.isEmpty { message("Не удалось вернуть часть окон", "Повтори хоткей. Если окно находится в полноэкранном режиме, сначала выйди из него.") }
            return
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: warpID).first else {
            message("Warp не запущен", "Открой два отдельных окна Warp и нажми ⌃⌥⌘W.")
            return
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 2)
        let windows = (attribute(appElement, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter {
            (attribute($0, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole &&
            (attribute($0, kAXMinimizedAttribute) as? Bool) != true && windowFrame($0) != nil
        }
        guard windows.count >= 2 else {
            message("Нужны два окна Warp", "Открой два отдельных окна Warp (⌘N) и разверни свёрнутые окна. Затем нажми ⌃⌥⌘W.")
            return
        }
        let selected = Array(windows.prefix(2))
        if selected.contains(where: { (attribute($0, "AXFullScreen") as? Bool) == true }) {
            message("Выйди из полноэкранного режима", "Для изменения размеров нужны обычные окна Warp. Затем снова нажми ⌃⌥⌘W.")
            return
        }
        saved = selected.map { SavedWindow(element: $0, frame: windowFrame($0)!) }
        savedScreens = screens
        let firstScreen = bestScreen(saved[0].frame, in: screens)
        let targets: [CGRect]
        if screens.count == 1 {
            targets = split(firstScreen)
        } else {
            let others = screens.filter { $0 != firstScreen }
            targets = [firstScreen, bestScreen(saved[1].frame, in: others)]
        }
        var success = true
        for (item, target) in zip(saved, targets) {
            if !setFrame(item.element, target) { success = false }
            _ = AXUIElementPerformAction(item.element, kAXRaiseAction as CFString)
        }
        app.activate(options: [])
        if !success { message("Не удалось изменить размер части окон", "Повторный хоткей вернёт прежнее положение. Проверь, что окна Warp доступны для изменения размера.") }
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
    print("PASS: equal halves, odd widths, negative display coordinates, disconnected-display fallback")
    exit(0)
}
if CommandLine.arguments.contains("--diagnose") {
    print("Accessibility: \(AXIsProcessTrusted()); displays: \(visibleScreens())")
    if AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: warpID).first {
        let windows = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement] ?? []
        print("Warp windows: \(windows.count)")
        for window in windows { print("Frame: \(String(describing: windowFrame(window)))") }
    }
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
app.delegate = controller
app.run()
