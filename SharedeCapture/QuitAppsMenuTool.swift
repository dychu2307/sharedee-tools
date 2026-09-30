import AppKit

@MainActor
final class QuitAppsMenuTool: MenuBarTool {
    private let quitter: AppQuitter
    private weak var quitSelectedItem: NSMenuItem?

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
        menu.addItem(ActionMenuItem(L10n.format("Thoát tất cả (%ld)", apps.count),
                                    symbol: "xmark.circle") { [quitter] in
            quitter.quitAll()
        })
        let quitSelected = ActionMenuItem("", symbol: "checkmark.circle") { [quitter] in
            quitter.quitSelected()
        }
        menu.addItem(quitSelected)
        quitSelectedItem = quitSelected
        updateQuitSelectedItem()

        menu.addItem(.separator())
        for app in apps {
            let item = NSMenuItem(title: app.localizedName ?? "", action: nil, keyEquivalent: "")
            item.view = AppRowView(app: app, selected: quitter.isSelected(app),
                                   onToggle: { [weak self] selected in
                                       self?.quitter.setSelected(selected, for: app)
                                       self?.updateQuitSelectedItem()
                                   },
                                   onQuit: { [weak menu, quitter] in
                                       menu?.cancelTracking()
                                       quitter.quit([app])
                                   })
            menu.addItem(item)
        }
    }

    private func updateQuitSelectedItem() {
        let count = quitter.selection.count
        quitSelectedItem?.title = L10n.format("Thoát %ld ứng dụng đã chọn", count)
        quitSelectedItem?.isEnabled = count > 0
    }
}

/// A running-app row. Clicking the row ticks the app for "quit selected" and keeps the menu
/// open; only the explicit Quit button closes that app.
private final class AppRowView: NSView {
    private let checkbox: NSButton
    private let label: NSTextField
    private let quitButton: NSButton
    private let onToggle: (Bool) -> Void
    private let onQuit: () -> Void
    private var highlighted = false {
        didSet { needsDisplay = true }
    }

    init(app: NSRunningApplication, selected: Bool,
         onToggle: @escaping (Bool) -> Void, onQuit: @escaping () -> Void) {
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

        let iconView = NSImageView(image: app.icon ?? NSImage())
        iconView.imageScaling = .scaleProportionallyUpOrDown
        label.font = .menuFont(ofSize: 0)
        label.lineBreakMode = .byTruncatingTail
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        highlighted = false
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
        onQuit()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard highlighted else { return }
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 4, yRadius: 4).fill()
    }
}
