import AppKit
import Carbon
import SwiftUI

enum PostCaptureAction: String, CaseIterable, Identifiable {
    case copy, saveToFolder, uploadToDrive, thumbnailOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy: L10n.tr("Sao chép vào clipboard")
        case .saveToFolder: L10n.tr("Lưu vào thư mục trên Mac")
        case .uploadToDrive: L10n.tr("Tải lên Google Drive")
        case .thumbnailOnly: L10n.tr("Chỉ hiện thumbnail")
        }
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case area, window, fullScreen, scrolling, captureText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: L10n.tr("Chụp vùng chọn")
        case .window: L10n.tr("Chụp cửa sổ")
        case .fullScreen: L10n.tr("Chụp toàn màn hình")
        case .scrolling: L10n.tr("Chụp cuộn")
        case .captureText: L10n.tr("Chụp và sao chép chữ")
        }
    }

    var symbol: String {
        switch self {
        case .area: "selection.pin.in.out"
        case .window: "macwindow"
        case .fullScreen: "display"
        case .scrolling: "scroll"
        case .captureText: "text.viewfinder"
        }
    }
}

struct KeyShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyLabel: String

    var display: String {
        var parts = ""
        if modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if modifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        if modifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        return parts + keyLabel
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        guard carbonModifiers & (UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)) != 0,
              let label = Self.keyLabel(for: event.keyCode)
                ?? event.charactersIgnoringModifiers?.uppercased(),
              !label.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers, keyLabel: label)
    }

    private static func keyLabel(for code: UInt16) -> String? {
        let keys: [UInt16: String] = [
            UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
            UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
            UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
            UInt16(kVK_ANSI_9): "9", UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B",
            UInt16(kVK_ANSI_C): "C", UInt16(kVK_ANSI_D): "D", UInt16(kVK_ANSI_E): "E",
            UInt16(kVK_ANSI_F): "F", UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H",
            UInt16(kVK_ANSI_I): "I", UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K",
            UInt16(kVK_ANSI_L): "L", UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N",
            UInt16(kVK_ANSI_O): "O", UInt16(kVK_ANSI_P): "P", UInt16(kVK_ANSI_Q): "Q",
            UInt16(kVK_ANSI_R): "R", UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T",
            UInt16(kVK_ANSI_U): "U", UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W",
            UInt16(kVK_ANSI_X): "X", UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z"
        ]
        return keys[code]
    }
}

@MainActor
final class ShortcutSettings: ObservableObject {
    static let defaultMaxScrollHeight = 30_000
    static let maxScrollHeightOptions = [10_000, 20_000, 30_000, 50_000]
    @Published private(set) var shortcuts: [ShortcutAction: KeyShortcut]
    @Published private(set) var errors: [ShortcutAction: String] = [:]
    @Published var postCaptureAction: PostCaptureAction {
        didSet { UserDefaults.standard.set(postCaptureAction.rawValue, forKey: "postCaptureAction") }
    }
    @Published private(set) var saveFolderURL: URL?
    @Published var captureDelay: Int {
        didSet { UserDefaults.standard.set(captureDelay, forKey: "captureDelay") }
    }
    @Published var includeCursor: Bool {
        didSet { UserDefaults.standard.set(includeCursor, forKey: "includeCursor") }
    }
    /// Longest scrolling capture, in output pixels.
    @Published var maxScrollHeight: Int {
        didSet { UserDefaults.standard.set(maxScrollHeight, forKey: "maxScrollHeight") }
    }

    private var manager: GlobalHotKeyManager?
    private var onAction: ((ShortcutAction) -> Void)?
    private static let storageKey = "customShortcutsV1"

    init() {
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: KeyShortcut].self, from: $0) } ?? [:]
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map {
            ($0, saved[$0.rawValue] ?? Self.defaultShortcut(for: $0))
        })
        postCaptureAction = PostCaptureAction(rawValue: defaults.string(forKey: "postCaptureAction") ?? "") ?? .copy
        saveFolderURL = defaults.string(forKey: "saveFolderPath").map { URL(fileURLWithPath: $0, isDirectory: true) }
        captureDelay = defaults.object(forKey: "captureDelay") as? Int ?? 0
        includeCursor = defaults.object(forKey: "includeCursor") as? Bool ?? false
        maxScrollHeight = defaults.object(forKey: "maxScrollHeight") as? Int ?? Self.defaultMaxScrollHeight
    }

    func activate(onAction: @escaping (ShortcutAction) -> Void) {
        self.onAction = onAction
        if manager == nil {
            manager = GlobalHotKeyManager { [weak self] action in
                self?.onAction?(action)
            }
        }
        registerAll()
    }

    func shortcut(for action: ShortcutAction) -> KeyShortcut {
        shortcuts[action] ?? Self.defaultShortcut(for: action)
    }

    func setSaveFolder(_ url: URL) {
        saveFolderURL = url
        UserDefaults.standard.set(url.path, forKey: "saveFolderPath")
    }

    func set(_ shortcut: KeyShortcut, for action: ShortcutAction) {
        guard !shortcuts.contains(where: { $0.key != action && $0.value == shortcut }) else {
            errors[action] = L10n.tr("Tổ hợp này đã dùng cho một tác vụ khác.")
            return
        }
        shortcuts[action] = shortcut
        persist()
        registerAll()
    }

    func resetToDefaults() {
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map {
            ($0, Self.defaultShortcut(for: $0))
        })
        persist()
        registerAll()
    }

    func useConflictFreePreset() {
        let prefix = UInt32(controlKey | optionKey | cmdKey)
        shortcuts = [
            .area: KeyShortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: prefix, keyLabel: "4"),
            .window: KeyShortcut(keyCode: UInt32(kVK_ANSI_5), modifiers: prefix, keyLabel: "5"),
            .fullScreen: KeyShortcut(keyCode: UInt32(kVK_ANSI_3), modifiers: prefix, keyLabel: "3"),
            .scrolling: KeyShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: prefix, keyLabel: "S"),
            .captureText: KeyShortcut(keyCode: UInt32(kVK_ANSI_O), modifiers: prefix, keyLabel: "O")
        ]
        persist()
        registerAll()
    }

    private static func defaultShortcut(for action: ShortcutAction) -> KeyShortcut {
        let captureModifiers = UInt32(cmdKey | shiftKey)
        switch action {
        case .area:
            return KeyShortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: captureModifiers, keyLabel: "4")
        case .window:
            return KeyShortcut(keyCode: UInt32(kVK_ANSI_5), modifiers: captureModifiers, keyLabel: "5")
        case .fullScreen:
            return KeyShortcut(keyCode: UInt32(kVK_ANSI_3), modifiers: captureModifiers, keyLabel: "3")
        case .scrolling:
            return KeyShortcut(keyCode: UInt32(kVK_ANSI_S),
                        modifiers: UInt32(controlKey | optionKey | cmdKey), keyLabel: "S")
        case .captureText:
            return KeyShortcut(keyCode: UInt32(kVK_ANSI_O),
                        modifiers: UInt32(controlKey | optionKey | cmdKey), keyLabel: "O")
        }
    }

    private func persist() {
        let raw = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func registerAll() {
        guard let manager else { return }
        manager.unregisterAll()
        errors = [:]
        for action in ShortcutAction.allCases {
            let result = manager.register(shortcut(for: action), action: action)
            if result != noErr {
                errors[action] = L10n.tr("Phím tắt đang được macOS hoặc app khác sử dụng.")
            }
        }
    }
}

private final class GlobalHotKeyManager {
    private var hotkeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let onAction: (ShortcutAction) -> Void

    init(onAction: @escaping (ShortcutAction) -> Void) {
        self.onAction = onAction
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard result == noErr else { return result }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            let index = Int(hotKeyID.id) - 1
            guard ShortcutAction.allCases.indices.contains(index) else { return noErr }
            let action = ShortcutAction.allCases[index]
            DispatchQueue.main.async { manager.onAction(action) }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ shortcut: KeyShortcut, action: ShortcutAction) -> OSStatus {
        let index = ShortcutAction.allCases.firstIndex(of: action) ?? 0
        let identifier = EventHotKeyID(signature: 0x53484350, id: UInt32(index + 1))
        var hotkey: EventHotKeyRef?
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier,
                                         GetApplicationEventTarget(), 0, &hotkey)
        if let hotkey { hotkeys.append(hotkey) }
        return result
    }

    func unregisterAll() {
        hotkeys.forEach { UnregisterEventHotKey($0) }
        hotkeys.removeAll()
    }

    deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: KeyShortcut
    let onChange: (KeyShortcut) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.shortcut = shortcut
        view.onChange = onChange
        view.needsDisplay = true
    }
}

final class RecorderView: NSView {
    var shortcut = KeyShortcut(keyCode: 0, modifiers: 0, keyLabel: "")
    var onChange: ((KeyShortcut) -> Void)?
    private var recording = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        recording = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return }
        if event.keyCode == 53 {
            recording = false
        } else if let newShortcut = KeyShortcut(event: event) {
            onChange?(newShortcut)
            recording = false
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        (recording ? NSColor.systemTeal.withAlphaComponent(0.18)
                   : NSColor(calibratedWhite: 0.22, alpha: 1)).setFill()
        path.fill()
        (recording ? NSColor.systemTeal : NSColor(calibratedWhite: 0.36, alpha: 1)).setStroke()
        path.lineWidth = 1
        path.stroke()
        let title = recording ? L10n.tr("Nhấn tổ hợp…") : shortcut.display
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: CGPoint(x: (bounds.width - size.width) / 2,
                                             y: (bounds.height - size.height) / 2),
                                 withAttributes: attributes)
    }
}
