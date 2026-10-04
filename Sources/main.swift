import AppKit
import ApplicationServices

final class SelectionApp: NSObject, NSApplicationDelegate {
    private let system = AXUIElementCreateSystemWide()
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggle = NSMenuItem(title: "Выделение по словам", action: #selector(toggleSelection), keyEquivalent: "")
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pendingDoubleClick: CGPoint?
    private var interceptedDown: CGEvent?
    private var dragElement: AXUIElement?
    private var dragAnchor: NSRange?
    private var anchor: Int?
    private var caret: Int?
    private var lastElement: AXUIElement?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = NSImage(named: "WordSelection") {
            NSApplication.shared.applicationIconImage = icon
        }
        status.button?.image = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "Выделение по словам")
        let menu = NSMenu()
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выход", action: #selector(quit), keyEquivalent: "q"))
        menu.items.last?.target = self
        status.menu = menu
        if UserDefaults.standard.bool(forKey: "enabled") { enable() }
        updateMenu()
    }

    private func updateMenu() {
        toggle.state = tap == nil ? .off : .on
    }

    @objc private func toggleSelection() {
        if tap == nil { enable() } else { disable() }
        updateMenu()
    }

    private func enable() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            showAlert("Нужен доступ для выделения текста",
                      message: "WordSelection должен управлять выделением в других приложениях.\n\n1. Откройте Системные настройки → Конфиденциальность и безопасность → Управление устройством и доступ к данным.\n2. Разрешите доступ для WordSelection.\n3. Вернитесь в меню приложения и включите «Выделение по словам».")
            return
        }
        let mask = [CGEventType.keyDown, .leftMouseDown, .leftMouseUp, .leftMouseDragged]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let app = Unmanaged<SelectionApp>.fromOpaque(refcon).takeUnretainedValue()
            return app.handle(proxy: proxy, type: type, event: event)
        }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                            options: .defaultTap, eventsOfInterest: mask,
                                            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            showAlert("Не удалось включить выделение",
                      message: "Проверьте разрешение для WordSelection:\n\nСистемные настройки → Конфиденциальность и безопасность → Управление устройством и доступ к данным.\n\nЗатем попробуйте включить «Выделение по словам» снова.")
            return
        }
        let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        source = newSource
        UserDefaults.standard.set(true, forKey: "enabled")
    }

    private func disable(persist: Bool = true) {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        pendingDoubleClick = nil
        interceptedDown = nil
        dragElement = nil
        dragAnchor = nil
        anchor = nil
        caret = nil
        lastElement = nil
        if persist { UserDefaults.standard.set(false, forKey: "enabled") }
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDown {
            interceptedDown = nil
            dragElement = nil
            dragAnchor = nil
            pendingDoubleClick = nil
            anchor = nil
            if event.getIntegerValueField(.mouseEventClickState) == 2 &&
                event.flags.intersection([.maskShift, .maskCommand, .maskAlternate, .maskControl]).isEmpty {
                if let (element, word) = selectWord(at: event.location) {
                    interceptedDown = event
                    dragElement = element
                    dragAnchor = word
                    return nil
                }
                pendingDoubleClick = event.location
            }
        } else if type == .leftMouseDragged, let down = interceptedDown {
            if let element = dragElement, let anchor = dragAnchor,
               let text = stringValue(of: element),
               let index = characterIndex(at: event.location, in: element) {
                let selection = WordBoundaries.dragSelection(from: anchor, to: index, in: text)
                if setRange(selection, on: element) { return nil }
            }
            // If AX stops supporting this field, fall back to a normal character drag.
            interceptedDown = nil
            dragElement = nil
            dragAnchor = nil
            if let singleClick = down.copy() {
                singleClick.setIntegerValueField(.mouseEventClickState, value: 1)
                singleClick.tapPostEvent(proxy)
            }
        } else if type == .leftMouseUp, interceptedDown != nil {
            interceptedDown = nil
            dragElement = nil
            dragAnchor = nil
            return nil
        } else if type == .leftMouseUp, let position = pendingDoubleClick {
            pendingDoubleClick = nil
            guard hypot(event.location.x - position.x, event.location.y - position.y) < 4 else {
                return Unmanaged.passUnretained(event)
            }
            // Let the target app finish its own double-click selection first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                guard let self, self.tap != nil else { return }
                _ = self.selectWord(at: position)
            }
        } else if type == .keyDown && handleArrow(event) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func selectWord(at point: CGPoint) -> (AXUIElement, NSRange)? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        let focused = attribute(of: system, name: kAXFocusedUIElementAttribute as String)
        let target: AXUIElement
        if let focused, CFGetTypeID(focused) == AXUIElementGetTypeID(),
           CFEqual(focused, hit) || stringValue(of: hit) == nil {
            target = focused as! AXUIElement
        } else {
            target = hit
        }
        guard let text = stringValue(of: target),
              let index = characterIndex(at: point, in: target),
              index >= 0, index < (text as NSString).length else { return nil }
        let word = WordBoundaries.word(at: index, in: text)
            ?? NSRange(location: index, length: 1)
        return setRange(word, on: target) ? (target, word) : nil
    }

    private func characterIndex(at point: CGPoint, in element: AXUIElement) -> Int? {
        var position = CGPoint(x: point.x, y: point.y)
        guard let parameter = AXValueCreate(.cgPoint, &position),
              let result = parameterValue(of: element, name: kAXRangeForPositionParameterizedAttribute as String,
                                          parameter: parameter),
              let indexRange = range(from: result) else { return nil }
        return indexRange.location
    }

    private func handleArrow(_ event: CGEvent) -> Bool {
        let flags = event.flags
        guard flags.contains(.maskAlternate), !flags.contains(.maskCommand),
              !flags.contains(.maskControl) else { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        guard key == 123 || key == 124,
              let focused = attribute(of: system, name: kAXFocusedUIElementAttribute as String),
              CFGetTypeID(focused) == AXUIElementGetTypeID(),
              let element = (focused as! AXUIElement?),
              let text = stringValue(of: element),
              let selected = attribute(of: element, name: kAXSelectedTextRangeAttribute as String).flatMap(range(from:)),
              selected.location >= 0, selected.length >= 0,
              selected.location <= (text as NSString).length - selected.length else { return false }

        let right = key == 124
        let shift = flags.contains(.maskShift)
        let sameSelection = lastElement.map { CFEqual($0, element) } == true &&
            caret.map { selected == NSRange(location: min(anchor ?? $0, $0), length: abs((anchor ?? $0) - $0)) } == true
        let fixed = shift ? (sameSelection ? anchor! : (right ? selected.location : NSMaxRange(selected))) : nil
        let moving = shift && sameSelection ? caret! : (right ? NSMaxRange(selected) : selected.location)
        let next = right ? WordBoundaries.next(from: moving, in: text) : WordBoundaries.previous(from: moving, in: text)
        let selection = fixed.map { NSRange(location: min($0, next), length: abs($0 - next)) }
            ?? NSRange(location: next, length: 0)
        guard setRange(selection, on: element) else { return false }
        anchor = fixed
        caret = shift ? next : nil
        lastElement = element
        return true
    }

    private func attribute(of element: AXUIElement, name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
    }

    private func parameterValue(of element: AXUIElement, name: String, parameter: CFTypeRef) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &result) == .success ? result : nil
    }

    private func stringValue(of element: AXUIElement) -> String? {
        attribute(of: element, name: kAXValueAttribute as String) as? String
    }

    private func range(from value: CFTypeRef) -> NSRange? {
        guard CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetType(value as! AXValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func setRange(_ range: NSRange, on element: AXUIElement) -> Bool {
        var value = CFRange(location: range.location, length: range.length)
        guard let axValue = AXValueCreate(.cfRange, &value) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axValue) == .success
    }

    private func showAlert(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.icon = NSApplication.shared.applicationIconImage
        alert.runModal()
    }

    @objc private func quit() {
        disable(persist: false)
        NSApplication.shared.terminate(nil)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = SelectionApp()
application.delegate = delegate
application.run()
