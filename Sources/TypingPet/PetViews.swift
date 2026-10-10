import AppKit
import QuartzCore

internal final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

internal final class PetResizeHandleView: NSView {
    var onResizeBegan: ((NSPoint) -> Void)?
    var onResizeDragged: ((NSPoint) -> Void)?
    var onResizeEnded: (() -> Void)?

    private let imageView: NSImageView
    private(set) var isDragging = false
    private var cursorTrackingArea: NSTrackingArea?

    private static var resizeCursor: NSCursor {
        if #available(macOS 15.0, *) {
            return .frameResize(position: .topRight, directions: .all)
        }
        return .resizeLeftRight
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        imageView = NSImageView(frame: .zero)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        layer?.cornerRadius = frameRect.width / 2

        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        imageView.image = NSImage(
            systemSymbolName: "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: "调整尺寸"
        )?.withSymbolConfiguration(configuration)
        imageView.contentTintColor = .white
        imageView.imageScaling = .scaleProportionallyDown
        addSubview(imageView)
        toolTip = "拖拽调整尺寸"
        setAccessibilityLabel("调整宠物尺寸")
        setAccessibilityHelp("拖拽调整宠物尺寸。")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
        imageView.frame = bounds.insetBy(dx: 9, dy: 9)
        window?.invalidateCursorRects(for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTrackingArea { removeTrackingArea(cursorTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        cursorTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        Self.resizeCursor.set()
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging { NSCursor.arrow.set() }
    }

    override func cursorUpdate(with event: NSEvent) {
        Self.resizeCursor.set()
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        Self.resizeCursor.set()
        onResizeBegan?(screenLocation(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        Self.resizeCursor.set()
        onResizeDragged?(screenLocation(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        let localPoint = convert(event.locationInWindow, from: nil)
        (bounds.contains(localPoint) ? Self.resizeCursor : NSCursor.arrow).set()
        onResizeEnded?()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: Self.resizeCursor)
    }

    private func screenLocation(for event: NSEvent) -> NSPoint {
        guard let window else { return NSEvent.mouseLocation }
        return window.convertPoint(toScreen: event.locationInWindow)
    }
}

internal final class PetContentView: NSView {
    var onClose: (() -> Void)?
    var onResizeBegan: ((NSPoint) -> Void)?
    var onResizeDragged: ((NSPoint) -> Void)?
    var onResizeEnded: (() -> Void)?
    var onMoveBegan: ((PetDragSample) -> Void)?
    var onMoveDragged: ((PetDragSample) -> Void)?
    var onMoveEnded: ((PetDragSample) -> Void)?
    weak var petImageView: NSView?

    private let closeButton: NSButton
    private let resizeHandle: PetResizeHandleView
    private var hoverTrackingArea: NSTrackingArea?
    private var controlsVisible = false
    private var isPointerInside = false
    private var isBodyPressed = false

    var controlsEnabled = true {
        didSet {
            if !controlsEnabled { hideControls() }
        }
    }

    override init(frame frameRect: NSRect) {
        closeButton = NSButton(frame: .zero)
        resizeHandle = PetResizeHandleView(frame: .zero)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        closeButton.isBordered = false
        closeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "隐藏宠物"
        )?.withSymbolConfiguration(.init(pointSize: 18, weight: .semibold))
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .white
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        closeButton.target = self
        closeButton.action = #selector(closePet)
        closeButton.setAccessibilityLabel("隐藏宠物")

        resizeHandle.onResizeBegan = { [weak self] in self?.onResizeBegan?($0) }
        resizeHandle.onResizeDragged = { [weak self] in self?.onResizeDragged?($0) }
        resizeHandle.onResizeEnded = { [weak self] in self?.onResizeEnded?() }

        addSubview(closeButton)
        addSubview(resizeHandle)
        setControlsVisible(false, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func layout() {
        super.layout()
        let imageFrame = bounds.insetBy(
            dx: bounds.width * 0.015,
            dy: bounds.height * 0.015
        )
        petImageView?.frame = imageFrame
        if let imageLayer = petImageView?.layer {
            imageLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            imageLayer.position = CGPoint(x: imageFrame.midX, y: imageFrame.midY)
        }
        let controlSize: CGFloat = 38
        let margin: CGFloat = 10
        closeButton.frame = NSRect(
            x: margin,
            y: bounds.maxY - controlSize - margin,
            width: controlSize,
            height: controlSize
        )
        closeButton.layer?.cornerRadius = controlSize / 2
        resizeHandle.frame = NSRect(
            x: bounds.maxX - controlSize - margin,
            y: bounds.maxY - controlSize - margin,
            width: controlSize,
            height: controlSize
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard controlsEnabled else { return }
        isPointerInside = true
        setControlsVisible(true)
        updateInteractionScale()
    }

    override func mouseDown(with event: NSEvent) {
        if controlsEnabled { setControlsVisible(true) }
        isBodyPressed = true
        updateInteractionScale(pressed: true)
        onMoveBegan?(dragSample(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        onMoveDragged?(dragSample(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        isBodyPressed = false
        isPointerInside = bounds.contains(convert(event.locationInWindow, from: nil))
        updateInteractionScale()
        onMoveEnded?(dragSample(for: event))
    }

    override func mouseMoved(with event: NSEvent) {
        guard controlsEnabled else { return }
        setControlsVisible(true)
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        guard !resizeHandle.isDragging else { return }
        setControlsVisible(false)
        if !isBodyPressed { updateInteractionScale() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if controlsVisible, closeButton.frame.contains(point) { return closeButton }
        if controlsVisible, resizeHandle.frame.contains(point) { return resizeHandle }
        return self
    }

    func hideControls() {
        setControlsVisible(false, animated: false)
        isPointerInside = false
        isBodyPressed = false
        updateInteractionScale(animated: false)
    }

    @objc private func closePet() {
        setControlsVisible(false, animated: false)
        onClose?()
    }

    private func setControlsVisible(_ visible: Bool, animated: Bool = true) {
        guard controlsVisible != visible || !animated else { return }
        controlsVisible = visible

        if visible {
            closeButton.isHidden = false
            resizeHandle.isHidden = false
            window?.invalidateCursorRects(for: resizeHandle)
        }

        let changes = { [weak self] in
            self?.closeButton.alphaValue = visible ? 1 : 0
            self?.resizeHandle.alphaValue = visible ? 1 : 0
        }
        let completion = { [weak self] in
            guard let self, !self.controlsVisible else { return }
            self.closeButton.isHidden = true
            self.resizeHandle.isHidden = true
        }

        guard animated else {
            changes()
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            closeButton.animator().alphaValue = visible ? 1 : 0
            resizeHandle.animator().alphaValue = visible ? 1 : 0
        } completionHandler: {
            completion()
        }
    }

    private func updateInteractionScale(pressed: Bool? = nil, animated: Bool = true) {
        let targetScale: CGFloat
        if pressed ?? isBodyPressed {
            targetScale = 0.94
        } else if isPointerInside, controlsEnabled {
            targetScale = 1.025
        } else {
            targetScale = 1
        }
        animateImageScale(to: targetScale, animated: animated)
    }

    private func animateImageScale(to targetScale: CGFloat, animated: Bool) {
        guard let imageLayer = petImageView?.layer else { return }
        imageLayer.removeAnimation(forKey: "interactionScale")
        let currentScale = (imageLayer.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat)
            ?? (imageLayer.value(forKeyPath: "transform.scale") as? CGFloat)
            ?? 1
        imageLayer.setValue(targetScale, forKeyPath: "transform.scale")
        guard animated else { return }

        let animation = CASpringAnimation(keyPath: "transform.scale")
        animation.fromValue = currentScale
        animation.toValue = targetScale
        animation.mass = 0.75
        animation.stiffness = targetScale < currentScale ? 360 : 220
        animation.damping = targetScale < currentScale ? 22 : 15
        animation.initialVelocity = 0
        animation.duration = animation.settlingDuration
        imageLayer.add(animation, forKey: "interactionScale")
    }

    private func screenLocation(for event: NSEvent) -> NSPoint {
        guard let window else { return NSEvent.mouseLocation }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func dragSample(for event: NSEvent) -> PetDragSample {
        PetDragSample(point: screenLocation(for: event), timestamp: event.timestamp)
    }
}
