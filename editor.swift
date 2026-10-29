import AppKit
import UniformTypeIdentifiers

enum Mark {
    case rect(CGRect, NSColor, CGFloat)
    case oval(CGRect, NSColor, CGFloat)
    case arrow(CGPoint, CGPoint, NSColor, CGFloat)
    case pen([CGPoint], NSColor, CGFloat)
    case text(CGPoint, String, NSColor, CGFloat)
}

enum DrawTool {
    case rect, oval, arrow, pen, text
}

func imagePoint(view: CGPoint, imageRect: CGRect, imageSize: CGSize) -> CGPoint {
    guard imageRect.width > 0, imageRect.height > 0 else { return view }
    return CGPoint(
        x: (view.x - imageRect.minX) * imageSize.width / imageRect.width,
        y: (view.y - imageRect.minY) * imageSize.height / imageRect.height
    )
}

func pixelSize(of image: NSImage) -> CGSize {
    for rep in image.representations where rep.pixelsWide > 0 && rep.pixelsHigh > 0 {
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
    return image.size
}

var openEditors: [ShotEditor] = []
var editorOwnsRunLoop = false

func showEditors(_ shots: [(NSImage, URL)]) {
    for (image, url) in shots {
        let editor = ShotEditor(image: image, suggestedURL: url)
        openEditors.append(editor)
        editor.onClose = { [weak editor] in
            guard let editor else { return }
            openEditors.removeAll { $0 === editor }
            if editorOwnsRunLoop, openEditors.isEmpty {
                NSApp.stop(nil)
            }
        }
        editor.show()
    }
    NSApp.setActivationPolicy(.accessory)
    NSApp.activate(ignoringOtherApps: true)
    if !NSApp.isRunning {
        editorOwnsRunLoop = true
        NSApp.run()
    }
}

final class ShotEditor: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    let image: NSImage
    let pixels: CGSize
    let suggestedURL: URL
    var onClose: (() -> Void)?

    private let window: NSWindow
    private let canvas: ShotCanvas
    private var toolButtons: [(DrawTool, NSButton)] = []
    private var colorButtons: [(NSColor, NSButton)] = []
    private let statusLabel = NSTextField(labelWithString: "")
    private var closed = false

    init(image: NSImage, suggestedURL: URL) {
        self.image = image
        self.pixels = pixelSize(of: image)
        self.suggestedURL = suggestedURL
        canvas = ShotCanvas(image: image, pixels: pixelSize(of: image))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        canvas.editor = self
        buildWindow()
    }

    func show() {
        fitWindow()
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeFirstResponder(canvas)
    }

    private func buildWindow() {
        window.title = "编辑截图"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 760, height: 420)
        window.appearance = NSAppearance(named: .darkAqua)

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 6
        toolbar.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)

        func tool(_ title: String, _ tool: DrawTool) -> NSButton {
            let button = NSButton(title: title, target: self, action: #selector(pickTool(_:)))
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .rounded
            button.tag = toolButtons.count
            toolButtons.append((tool, button))
            return button
        }
        toolbar.addArrangedSubview(tool("矩形", .rect))
        toolbar.addArrangedSubview(tool("椭圆", .oval))
        toolbar.addArrangedSubview(tool("箭头", .arrow))
        toolbar.addArrangedSubview(tool("画笔", .pen))
        toolbar.addArrangedSubview(tool("文字", .text))

        let colors: [NSColor] = [.systemRed, .systemOrange, .systemGreen, .systemBlue, .white, .black]
        for color in colors {
            let swatch = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
                color.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                return true
            }
            let button = NSButton(image: swatch, target: self, action: #selector(pickColor(_:)))
            button.bezelStyle = .circular
            button.setButtonType(.pushOnPushOff)
            button.imagePosition = .imageOnly
            button.tag = colorButtons.count
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
            colorButtons.append((color, button))
            toolbar.addArrangedSubview(button)
        }

        let undo = NSButton(title: "撤销", target: self, action: #selector(undoMark(_:)))
        let copy = NSButton(title: "复制", target: self, action: #selector(copyShot(_:)))
        let save = NSButton(title: "保存", target: self, action: #selector(saveShot(_:)))
        let close = NSButton(title: "关闭", target: self, action: #selector(closeShot(_:)))
        toolbar.addArrangedSubview(undo)
        toolbar.addArrangedSubview(copy)
        toolbar.addArrangedSubview(save)
        toolbar.addArrangedSubview(close)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        toolbar.addArrangedSubview(statusLabel)

        let content = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(toolbar)
        content.addSubview(canvas)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 46),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        canvas.tool = .rect
        canvas.color = .systemRed
        refreshChrome()
    }

    private func fitWindow() {
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let maxW = visible.width * 0.86
        let maxH = visible.height * 0.86 - 46
        var width = pixels.width
        var height = pixels.height
        let fit = min(1, min(maxW / max(width, 1), maxH / max(height, 1)))
        width *= fit
        height *= fit
        window.setContentSize(NSSize(width: max(width, 760), height: max(height, 320) + 46))
    }

    func fittedRect(in bounds: NSRect) -> NSRect {
        guard pixels.width > 0, pixels.height > 0 else { return bounds }
        let scale = min(bounds.width / pixels.width, bounds.height / pixels.height)
        let size = CGSize(width: pixels.width * scale, height: pixels.height * scale)
        return NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    func refreshChrome() {
        for (tool, button) in toolButtons {
            let on = tool == canvas.tool
            button.state = on ? .on : .off
            button.font = .systemFont(ofSize: 13, weight: on ? .bold : .regular)
        }
        for (color, button) in colorButtons {
            button.state = color === canvas.color ? .on : .off
        }
        window.invalidateCursorRects(for: canvas)
    }

    func note(_ text: String) {
        statusLabel.stringValue = text
    }

    @objc func pickTool(_ sender: NSButton) {
        canvas.commitText()
        canvas.tool = toolButtons[sender.tag].0
        refreshChrome()
    }

    @objc func pickColor(_ sender: NSButton) {
        canvas.color = colorButtons[sender.tag].0
        refreshChrome()
    }

    @objc func undoMark(_ sender: Any?) {
        canvas.commitText()
        guard !canvas.marks.isEmpty else { return }
        canvas.marks.removeLast()
        canvas.needsDisplay = true
        note("")
    }

    @objc func copyShot(_ sender: Any?) {
        canvas.commitText()
        guard let rep = canvas.renderedRep() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let tiff = rep.representation(using: .tiff, properties: [:]), let image = NSImage(data: tiff) {
            pasteboard.writeObjects([image])
        }
        if let png = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        note("已复制")
    }

    @objc func saveShot(_ sender: Any?) {
        canvas.commitText()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.directoryURL = suggestedURL.deletingLastPathComponent()
        panel.nameFieldStringValue = suggestedURL.lastPathComponent
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url, let rep = self.canvas.renderedRep(),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            do {
                try png.write(to: url)
                self.note("已保存")
                print(url.path)
            } catch {
                self.note("保存失败")
            }
        }
    }

    @objc func closeShot(_ sender: Any?) {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard !closed else { return }
        closed = true
        canvas.commitText()
        onClose?()
    }
}

final class ShotCanvas: NSView, NSTextFieldDelegate {
    let image: NSImage
    let pixels: CGSize
    weak var editor: ShotEditor?
    var marks: [Mark] = []
    var draft: Mark?
    var tool: DrawTool = .rect
    var color: NSColor = .systemRed
    private var textField: NSTextField?
    private var anchor: CGPoint?

    init(image: NSImage, pixels: CGSize) {
        self.image = image
        self.pixels = pixels
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .text ? .iBeam : .crosshair)
    }

    func fitted() -> NSRect {
        editor?.fittedRect(in: bounds) ?? bounds
    }

    func toImage(_ point: NSPoint) -> CGPoint {
        imagePoint(view: point, imageRect: fitted(), imageSize: pixels)
    }

    func strokeWidth() -> CGFloat {
        let fitted = fitted()
        guard fitted.width > 1 else { return 4 }
        return 3 * pixels.width / fitted.width
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        bounds.fill()
        let rect = fitted()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        let scale = rect.width / max(pixels.width, 1)
        for mark in marks + (draft.map { [$0] } ?? []) {
            draw(mark, scale: scale, origin: CGPoint(x: rect.minX, y: rect.minY))
        }
    }

    func renderedRep() -> NSBitmapImageRep? {
        let width = max(Int(pixels.width.rounded()), 1)
        let height = max(Int(pixels.height.rounded()), 1)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
        for mark in marks {
            draw(mark, scale: 1, origin: .zero)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func draw(_ mark: Mark, scale: CGFloat, origin: CGPoint) {
        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale)
        }
        switch mark {
        case .rect(let rect, let color, let width), .oval(let rect, let color, let width):
            let path = NSBezierPath(rect: NSRect(
                x: origin.x + rect.minX * scale,
                y: origin.y + rect.minY * scale,
                width: rect.width * scale,
                height: rect.height * scale
            ))
            if case .oval = mark {
                path.removeAllPoints()
                path.appendOval(in: NSRect(
                    x: origin.x + rect.minX * scale,
                    y: origin.y + rect.minY * scale,
                    width: rect.width * scale,
                    height: rect.height * scale
                ))
            }
            path.lineWidth = max(width * scale, 1)
            color.setStroke()
            path.stroke()
        case .arrow(let from, let to, let color, let width):
            let start = map(from)
            let end = map(to)
            let line = NSBezierPath()
            line.move(to: start)
            line.line(to: end)
            line.lineWidth = max(width * scale, 1)
            line.lineCapStyle = .round
            color.setStroke()
            line.stroke()
            let angle = atan2(end.y - start.y, end.x - start.x)
            let head = max(width * scale * 4, 8)
            let left = CGPoint(x: end.x - head * cos(angle - 0.4), y: end.y - head * sin(angle - 0.4))
            let right = CGPoint(x: end.x - head * cos(angle + 0.4), y: end.y - head * sin(angle + 0.4))
            let triangle = NSBezierPath()
            triangle.move(to: end)
            triangle.line(to: left)
            triangle.line(to: right)
            triangle.close()
            color.setFill()
            triangle.fill()
        case .pen(let points, let color, let width):
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.move(to: map(first))
            for point in points.dropFirst() { path.line(to: map(point)) }
            path.lineWidth = max(width * scale, 1)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            color.setStroke()
            path.stroke()
        case .text(let point, let string, let color, let size):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(size * scale, 1), weight: .semibold),
                .foregroundColor: color,
            ]
            (string as NSString).draw(at: map(point), withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitText()
        let point = toImage(convert(event.locationInWindow, from: nil))
        anchor = point
        let width = strokeWidth()
        switch tool {
        case .pen:
            draft = .pen([point], color, width)
        case .text:
            beginText(at: convert(event.locationInWindow, from: nil))
            anchor = nil
        default:
            draft = nil
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor, tool != .text else { return }
        let point = toImage(convert(event.locationInWindow, from: nil))
        let width = strokeWidth()
        switch tool {
        case .rect:
            draft = .rect(box(anchor, point), color, width)
        case .oval:
            draft = .oval(box(anchor, point), color, width)
        case .arrow:
            draft = .arrow(anchor, point, color, width)
        case .pen:
            if case .pen(var points, let color, let width) = draft {
                points.append(point)
                draft = .pen(points, color, width)
            }
        case .text:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            anchor = nil
            draft = nil
            needsDisplay = true
        }
        guard let draft else { return }
        switch draft {
        case .rect(let rect, _, _), .oval(let rect, _, _):
            guard rect.width > 2, rect.height > 2 else { return }
        case .arrow(let from, let to, _, _):
            guard hypot(to.x - from.x, to.y - from.y) > 2 else { return }
        case .pen(let points, _, _):
            guard points.count > 1 else { return }
        case .text:
            return
        }
        marks.append(draft)
        editor?.note("")
    }

    func beginText(at viewPoint: NSPoint) {
        let field = NSTextField(frame: NSRect(x: viewPoint.x, y: viewPoint.y - 14, width: 280, height: 28))
        field.font = .systemFont(ofSize: 20, weight: .semibold)
        field.textColor = color
        field.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        field.isBezeled = false
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    func commitText() {
        guard let field = textField else { return }
        let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !string.isEmpty {
            let origin = toImage(NSPoint(x: field.frame.minX, y: field.frame.minY))
            let scale = fitted().width / max(pixels.width, 1)
            marks.append(.text(origin, string, field.textColor ?? color, 20 / max(scale, 0.01)))
        }
        field.removeFromSuperview()
        textField = nil
        needsDisplay = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitText()
            window?.makeFirstResponder(self)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            textField?.removeFromSuperview()
            textField = nil
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    override func cancelOperation(_ sender: Any?) {
        editor?.closeShot(sender)
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.keyDown(with: event)
            return
        }
        switch event.charactersIgnoringModifiers {
        case "c": editor?.copyShot(nil)
        case "s": editor?.saveShot(nil)
        case "z": editor?.undoMark(nil)
        default: super.keyDown(with: event)
        }
    }
}

private func box(_ a: CGPoint, _ b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
}
