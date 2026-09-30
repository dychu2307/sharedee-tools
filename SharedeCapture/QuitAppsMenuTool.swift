import AppKit

@MainActor
final class QuitAppsMenuTool: MenuBarTool {
    private let quitter: AppQuitter
    private var quitSelectedItems: [(item: NSMenuItem, force: Bool)] = []

    init(quitter: AppQuitter) {
        self.quitter = quitter
    }

    var title: String { L10n.tr("Thoát ứng dụng") }
    var symbol: String { "power" }

    func populate(_ menu: NSMenu) {
        quitter.refresh()
        let apps = quitter.apps
        guard !apps.isEmpty else {
            menu.addDisabledItem(L10n.tr("Không có ứng dụng nào đang mở"))
            return
        }
        // Each action has a ⌥ alternate that force quits; macOS swaps them while ⌥ is held.
        let all = quitter.quitAllTargets()
        addPair(to: menu, symbol: "xmark.circle", enabled: !all.isEmpty,
                title: { L10n.format($0 ? "Buộc thoát tất cả (%ld)" : "Thoát tất cả (%ld)", all.count) },
                action: { [quitter] force in quitter.quitAll(force: force) })
        if let current = quitter.lastActiveApp, all.contains(current) {
            let others = quitter.quitAllTargets(keeping: current)
            let name = current.localizedName ?? ""
            addPair(to: menu, symbol: "xmark.circle", enabled: !others.isEmpty,
                    title: { L10n.format($0 ? "Buộc thoát tất cả trừ %@ (%ld)" : "Thoát tất cả trừ %@ (%ld)",
                                         name, others.count) },
                    action: { [quitter] force in quitter.quitAll(keeping: current, force: force) })
        }
        quitSelectedItems = addPair(to: menu, symbol: "checkmark.circle", enabled: true,
                                    title: { _ in "" },
                                    action: { [quitter] force in quitter.quitSelected(force: force) })
        updateQuitSelectedItems()

        menu.addItem(.separator())
        for app in apps {
            let item = NSMenuItem(title: app.localizedName ?? "", action: nil, keyEquivalent: "")
            item.view = AppRowView(app: app, selected: quitter.isSelected(app), excluded: quitter.isExcluded(app),
                                   onToggle: { [weak self] selected in
                                       self?.quitter.setSelected(selected, for: app)
                                       self?.updateQuitSelectedItems()
                                   },
                                   onQuit: { [weak menu, quitter] force in
                                       menu?.cancelTracking()
                                       quitter.quit([app], force: force)
                                   })
            menu.addItem(item)
        }
    }

    @discardableResult
    private func addPair(to menu: NSMenu, symbol: String, enabled: Bool, title: (Bool) -> String,
                         action: @escaping (Bool) -> Void) -> [(item: NSMenuItem, force: Bool)] {
        [false, true].map { force in
            let item = ActionMenuItem(title(force), symbol: force ? "bolt.circle" : symbol, enabled: enabled) {
                action(force)
            }
            if force {
                item.keyEquivalentModifierMask = [.option]
                item.isAlternate = true
            }
            menu.addItem(item)
            return (item, force)
        }
    }

    private func updateQuitSelectedItems() {
        let count = quitter.selection.count
        for (item, force) in quitSelectedItems {
            item.title = L10n.format(force ? "Buộc thoát %ld ứng dụng đã chọn" : "Thoát %ld ứng dụng đã chọn", count)
            item.isEnabled = count > 0
        }
    }
}

/// A running-app row. Clicking the row ticks the app for "quit selected" and keeps the menu
/// open; only the explicit Quit button closes that app (or force quits it while ⌥ is held).
private final class AppRowView: NSView {
    private let checkbox: NSButton
    private let label: NSTextField
    private let quitButton: NSButton
    private let onToggle: (Bool) -> Void
    private let onQuit: (Bool) -> Void
    private var flagsMonitor: Any?
    private var highlighted = false {
        didSet { needsDisplay = true }
    }

    init(app: NSRunningApplication, selected: Bool, excluded: Bool,
         onToggle: @escaping (Bool) -> Void, onQuit: @escaping (Bool) -> Void) {
        self.onToggle = onToggle
        self.onQuit = onQuit
        let name = app.localizedName ?? app.bundleIdentifier ?? "?"
        checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        label = NSTextField(labelWithString: name)
        quitButton = NSButton(title: L10n.tr("Thoát"), target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 28))

        checkbox.state = selected ? .on : .off
        checkbox.target = self
        checkbox.action = #selector(checkboxChanged)
        checkbox.setAccessibilityLabel(L10n.format("Chọn %@", name))

        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small
        quitButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        quitButton.target = self
        quitButton.action = #selector(quitClicked)
        quitButton.setAccessibilityLabel(L10n.format("Thoát %@", name))
        if excluded { label.toolTip = L10n.tr("Thoát tất cả luôn bỏ qua ứng dụng này") }

        let iconView = NSImageView(image: app.icon ?? NSImage())
        iconView.imageScaling = .scaleProportionallyUpOrDown
        label.font = .menuFont(ofSize: 0)
        label.lineBreakMode = .byTruncatingTail
        if excluded, let pin = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil) {
            let attachment = NSTextAttachment()
            attachment.image = pin
            let text = NSMutableAttributedString(string: name + "  ", attributes: [.font: label.font as Any])
            text.append(NSAttributedString(attachment: attachment))
            label.attributedStringValue = text
        }
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for view in [checkbox, iconView, label, quitButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            quitButton.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            quitButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            quitButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        highlighted = false
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
        if window != nil {
            updateQuitTitle(force: NSEvent.modifierFlags.contains(.option))
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.updateQuitTitle(force: event.modifierFlags.contains(.option))
                return event
            }
        }
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { highlighted = true }
    override func mouseExited(with event: NSEvent) { highlighted = false }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        if quitButton.frame.contains(point) {
            quitClicked()
        } else {
            checkbox.state = checkbox.state == .on ? .off : .on
            checkboxChanged()
        }
    }

    @objc private func checkboxChanged() {
        onToggle(checkbox.state == .on)
    }

    @objc private func quitClicked() {
        onQuit(NSEvent.modifierFlags.contains(.option))
    }

    private func updateQuitTitle(force: Bool) {
        quitButton.title = force ? L10n.tr("Buộc thoát") : L10n.tr("Thoát")
        quitButton.contentTintColor = force ? .systemRed : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard highlighted else { return }
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 4, yRadius: 4).fill()
    }
}
