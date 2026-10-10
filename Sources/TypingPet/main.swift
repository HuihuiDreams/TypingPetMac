import AppKit
import CoreGraphics
import QuartzCore
import ServiceManagement
import UniformTypeIdentifiers

private enum PetConstants {
    static let fallbackBaseSize = NSSize(width: 453, height: 354)
    static let idleDelay: TimeInterval = 0.75
}

private final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PetResizeHandleView: NSView {
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

private final class PetContentView: NSView {
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

@MainActor
private final class PetController: NSObject, NSWindowDelegate {
    private let library: PetImageLibrary
    private let keyStore: KeyReactionStore
    private let panel: PetPanel
    private let contentView: PetContentView
    private let imageView: NSImageView
    private let onScaleChanged: (CGFloat) -> Void
    private var baseSize: NSSize
    private var currentImageKey = ""
    private var idleWorkItem: DispatchWorkItem?
    private var resizeInitialMouseLocation: NSPoint?
    private var resizeInitialFrame: NSRect?
    private var resizeInitialScale: CGFloat?
    private var moveInitialMouseLocation: NSPoint?
    private var moveInitialFrame: NSRect?
    private var moveSamples: [PetDragSample] = []
    private var inertiaTimer: Timer?
    private var inertiaVelocity: CGVector = .zero
    private var inertiaLastTimestamp: TimeInterval?
    private var inertiaBounds: NSRect?
    private var avoidanceTimer: Timer?
    private var avoidanceVelocity: CGVector = .zero
    private var avoidanceLastTimestamp: TimeInterval?
    private var avoidanceBounds: NSRect?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    init(
        library: PetImageLibrary,
        keyStore: KeyReactionStore,
        onScaleChanged: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.library = library
        self.keyStore = keyStore
        self.onScaleChanged = onScaleChanged
        let initialImage = library.idleURL.flatMap(NSImage.init(contentsOf:))
        baseSize = Self.normalizedBaseSize(for: initialImage?.size ?? PetConstants.fallbackBaseSize)
        panel = PetPanel(
            contentRect: NSRect(
                origin: .zero,
                size: Self.scaledSize(baseSize: baseSize, scale: Self.savedScale)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        imageView = NSImageView(frame: NSRect(origin: .zero, size: panel.frame.size))
        contentView = PetContentView(frame: NSRect(origin: .zero, size: panel.frame.size))
        super.init()

        imageView.autoresizingMask = []
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.wantsLayer = true
        contentView.petImageView = imageView
        contentView.addSubview(imageView, positioned: .below, relativeTo: nil)
        contentView.onClose = { [weak self] in self?.hidePet() }
        contentView.onResizeBegan = { [weak self] in self?.beginResize(at: $0) }
        contentView.onResizeDragged = { [weak self] in self?.continueResize(at: $0) }
        contentView.onResizeEnded = { [weak self] in self?.endResize() }
        contentView.onMoveBegan = { [weak self] in self?.beginMove(with: $0) }
        contentView.onMoveDragged = { [weak self] in self?.continueMove(with: $0) }
        contentView.onMoveEnded = { [weak self] in self?.endMove(with: $0) }

        panel.contentView = contentView
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = Self.savedAlwaysOnTop ? .floating : .normal
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = Self.savedPositionLocked
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView.controlsEnabled = !Self.savedPositionLocked

        let restoredPosition = panel.setFrameUsingName("TypingPetWindow")
        resizePanelForCurrentCanvas(animate: false)
        if !restoredPosition {
            resetPosition()
        }

        showIdleImage()
        panel.orderFrontRegardless()
        startMouseHoverMonitoring()
        updatePetOpacity()
        updatePointerAvoidance()
    }

    var isAlwaysOnTop: Bool {
        get { panel.level == .floating }
        set {
            panel.level = newValue ? .floating : .normal
            UserDefaults.standard.set(newValue, forKey: "alwaysOnTop")
        }
    }

    var isPositionLocked: Bool {
        get { panel.ignoresMouseEvents }
        set {
            if newValue { stopInertia(savePosition: true) }
            panel.ignoresMouseEvents = newValue
            contentView.controlsEnabled = !newValue
            UserDefaults.standard.set(newValue, forKey: "positionLocked")
            if newValue {
                updatePointerAvoidance()
            } else {
                stopPointerAvoidance(savePosition: true)
            }
        }
    }

    var isPetVisible: Bool { panel.isVisible }

    var scale: CGFloat {
        get { Self.savedScale }
        set { applyScale(newValue, anchorOrigin: nil, animate: true) }
    }

    var restingOpacity: CGFloat {
        get { Self.savedRestingOpacity }
        set {
            UserDefaults.standard.set(Double(min(max(newValue, 0), 1)), forKey: "restingOpacity")
            updatePetOpacity()
        }
    }

    var hoverOpacity: CGFloat {
        get { Self.savedHoverOpacity }
        set {
            UserDefaults.standard.set(Double(min(max(newValue, 0), 1)), forKey: "hoverOpacity")
            updatePetOpacity()
        }
    }

    var avoidsPointerWhenLocked: Bool {
        get { Self.savedAvoidsPointerWhenLocked }
        set {
            UserDefaults.standard.set(newValue, forKey: "avoidsPointerWhenLocked")
            if newValue {
                updatePointerAvoidance()
            } else {
                stopPointerAvoidance(savePosition: true)
            }
        }
    }

    var shakeLevel: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: "shakeLevel") as? Int
            return max(0, min(stored ?? 2, 3))
        }
        set { UserDefaults.standard.set(max(0, min(newValue, 3)), forKey: "shakeLevel") }
    }

    func handleKeystroke(_ stroke: KeyStroke? = nil) {
        let chosenURL: URL?
        if let stroke, let exactMatch = keyStore.imageURL(matching: stroke) {
            chosenURL = exactMatch
        } else {
            let reactions = library.reactionURLs
            let picker = ImagePicker(names: reactions.map(\.path))
            chosenURL = picker.next(excluding: currentImageKey).map(URL.init(fileURLWithPath:))
        }
        guard let chosenURL else { return }

        idleWorkItem?.cancel()
        showImage(at: chosenURL)
        bounce()

        let workItem = DispatchWorkItem { [weak self] in
            self?.showIdleImage()
        }
        idleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + PetConstants.idleDelay, execute: workItem)
    }

    func reloadImages() {
        idleWorkItem?.cancel()
        if let idleImage = library.idleURL.flatMap(NSImage.init(contentsOf:)) {
            baseSize = Self.normalizedBaseSize(for: idleImage.size)
        } else {
            baseSize = PetConstants.fallbackBaseSize
        }
        resizePanelForCurrentCanvas(animate: true)
        showIdleImage()
    }

    func hidePet() {
        stopInertia(savePosition: true)
        stopPointerAvoidance(savePosition: true)
        contentView.hideControls()
        panel.orderOut(nil)
    }

    func showPet() {
        contentView.hideControls()
        panel.orderFrontRegardless()
        updatePetOpacity()
        updatePointerAvoidance()
    }

    func togglePetVisibility() {
        isPetVisible ? hidePet() : showPet()
    }

    func resetPosition() {
        stopInertia(savePosition: false)
        stopPointerAvoidance(savePosition: false)
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - size.width - 24,
            y: visible.minY + 24
        )
        panel.setFrameOrigin(origin)
        panel.saveFrame(usingName: "TypingPetWindow")
    }

    func windowDidMove(_ notification: Notification) {
        panel.saveFrame(usingName: "TypingPetWindow")
    }

    private func showIdleImage() {
        guard let idleURL = library.idleURL else { return }
        showImage(at: idleURL)
    }

    private func showImage(at url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        currentImageKey = url.path
        imageView.image = nil
        imageView.image = image
    }

    private func resizePanelForCurrentCanvas(animate: Bool) {
        let oldFrame = panel.frame
        let newSize = Self.scaledSize(baseSize: baseSize, scale: Self.savedScale)
        let newOrigin = NSPoint(
            x: oldFrame.midX - newSize.width / 2,
            y: oldFrame.minY
        )
        panel.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: animate)
        panel.saveFrame(usingName: "TypingPetWindow")
    }

    private func beginResize(at mouseLocation: NSPoint) {
        stopInertia(savePosition: true)
        resizeInitialMouseLocation = mouseLocation
        resizeInitialFrame = panel.frame
        resizeInitialScale = scale
    }

    private func beginMove(with sample: PetDragSample) {
        stopInertia(savePosition: false)
        moveInitialMouseLocation = sample.point
        moveInitialFrame = panel.frame
        moveSamples = [sample]
    }

    private func continueMove(with sample: PetDragSample) {
        guard let initialMouse = moveInitialMouseLocation,
              let initialFrame = moveInitialFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: initialFrame.origin.x + sample.point.x - initialMouse.x,
            y: initialFrame.origin.y + sample.point.y - initialMouse.y
        ))
        appendMoveSample(sample)
    }

    private func endMove(with sample: PetDragSample) {
        appendMoveSample(sample)
        let velocity = PetMotionPhysics.releaseVelocity(samples: moveSamples)
        moveInitialMouseLocation = nil
        moveInitialFrame = nil
        moveSamples.removeAll()
        startInertia(with: velocity)
    }

    private func appendMoveSample(_ sample: PetDragSample) {
        moveSamples.append(sample)
        let cutoff = sample.timestamp - 0.15
        moveSamples.removeAll { $0.timestamp < cutoff }
    }

    private func startInertia(with velocity: CGVector) {
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed >= 45 else {
            panel.saveFrame(usingName: "TypingPetWindow")
            return
        }
        inertiaVelocity = velocity
        inertiaLastTimestamp = ProcessInfo.processInfo.systemUptime
        inertiaBounds = (panel.screen ?? NSScreen.main)?.visibleFrame
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceInertia() }
        }
        inertiaTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceInertia() {
        guard let lastTimestamp = inertiaLastTimestamp else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(max(now - lastTimestamp, 1.0 / 240.0), 1.0 / 30.0)
        inertiaLastTimestamp = now
        let visibleFrame = inertiaBounds ?? panel.frame
        let step = PetMotionPhysics.advance(
            origin: panel.frame.origin,
            size: panel.frame.size,
            velocity: inertiaVelocity,
            elapsed: elapsed,
            bounds: visibleFrame
        )
        inertiaVelocity = step.velocity
        panel.setFrameOrigin(step.origin)
        updatePetOpacity()
        if hypot(step.velocity.dx, step.velocity.dy) < 18 {
            stopInertia(savePosition: true)
        }
    }

    private func stopInertia(savePosition: Bool) {
        inertiaTimer?.invalidate()
        inertiaTimer = nil
        inertiaVelocity = .zero
        inertiaLastTimestamp = nil
        inertiaBounds = nil
        if savePosition { panel.saveFrame(usingName: "TypingPetWindow") }
    }

    private func startMouseHoverMonitoring() {
        let events: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
        ]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated { self?.handlePointerMotion() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointerMotion() }
            return event
        }
    }

    private func handlePointerMotion() {
        updatePetOpacity()
        updatePointerAvoidance()
    }

    private func updatePetOpacity() {
        guard panel.isVisible, let imageLayer = imageView.layer else { return }
        let targetOpacity = PetOpacityBehavior.opacity(
            isHovering: panel.frame.contains(NSEvent.mouseLocation),
            restingOpacity: restingOpacity,
            hoverOpacity: hoverOpacity
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.opacity = Float(targetOpacity)
        CATransaction.commit()
    }

    private func updatePointerAvoidance() {
        guard panel.isVisible, isPositionLocked, avoidsPointerWhenLocked else { return }
        let bounds = avoidanceBounds ?? (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        guard PetPointerAvoidance.targetOrigin(
            mouseLocation: NSEvent.mouseLocation,
            petFrame: panel.frame,
            bounds: bounds
        ) != nil else { return }
        startPointerAvoidance(in: bounds)
    }

    private func startPointerAvoidance(in bounds: NSRect) {
        guard avoidanceTimer == nil else { return }
        avoidanceBounds = bounds
        avoidanceLastTimestamp = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advancePointerAvoidance() }
        }
        avoidanceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advancePointerAvoidance() {
        guard panel.isVisible, isPositionLocked, avoidsPointerWhenLocked,
              let lastTimestamp = avoidanceLastTimestamp else {
            stopPointerAvoidance(savePosition: true)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = CGFloat(min(max(now - lastTimestamp, 1.0 / 240.0), 1.0 / 30.0))
        avoidanceLastTimestamp = now
        let bounds = avoidanceBounds ?? panel.frame
        let origin = panel.frame.origin
        let target = PetPointerAvoidance.targetOrigin(
            mouseLocation: NSEvent.mouseLocation,
            petFrame: panel.frame,
            bounds: bounds
        )
        let delta = CGVector(
            dx: (target?.x ?? origin.x) - origin.x,
            dy: (target?.y ?? origin.y) - origin.y
        )
        let stiffness: CGFloat = target == nil ? 0 : 58
        let damping: CGFloat = target == nil ? 16 : 13
        avoidanceVelocity.dx += (delta.dx * stiffness - avoidanceVelocity.dx * damping) * elapsed
        avoidanceVelocity.dy += (delta.dy * stiffness - avoidanceVelocity.dy * damping) * elapsed

        let speed = hypot(avoidanceVelocity.dx, avoidanceVelocity.dy)
        if speed > 520 {
            let factor = 520 / speed
            avoidanceVelocity.dx *= factor
            avoidanceVelocity.dy *= factor
        }
        let proposedOrigin = CGPoint(
            x: origin.x + avoidanceVelocity.dx * elapsed,
            y: origin.y + avoidanceVelocity.dy * elapsed
        )
        let nextOrigin = PetPointerAvoidance.clampedOrigin(
            proposedOrigin,
            size: panel.frame.size,
            bounds: bounds
        )
        if nextOrigin.x != proposedOrigin.x { avoidanceVelocity.dx = 0 }
        if nextOrigin.y != proposedOrigin.y { avoidanceVelocity.dy = 0 }
        panel.setFrameOrigin(nextOrigin)
        updatePetOpacity()

        if target == nil, hypot(avoidanceVelocity.dx, avoidanceVelocity.dy) < 5 {
            stopPointerAvoidance(savePosition: true)
        }
    }

    private func stopPointerAvoidance(savePosition: Bool) {
        avoidanceTimer?.invalidate()
        avoidanceTimer = nil
        avoidanceVelocity = .zero
        avoidanceLastTimestamp = nil
        avoidanceBounds = nil
        if savePosition { panel.saveFrame(usingName: "TypingPetWindow") }
    }

    private func continueResize(at mouseLocation: NSPoint) {
        guard let initialMouse = resizeInitialMouseLocation,
              let initialFrame = resizeInitialFrame,
              let initialScale = resizeInitialScale else { return }
        let delta = NSPoint(
            x: mouseLocation.x - initialMouse.x,
            y: mouseLocation.y - initialMouse.y
        )
        let newScale = PetResizeGeometry.scale(
            initialScale: initialScale,
            initialSize: initialFrame.size,
            dragDelta: delta
        )
        applyScale(newScale, anchorOrigin: initialFrame.origin, animate: false)
    }

    private func endResize() {
        resizeInitialMouseLocation = nil
        resizeInitialFrame = nil
        resizeInitialScale = nil
        panel.saveFrame(usingName: "TypingPetWindow")
    }

    private func applyScale(_ value: CGFloat, anchorOrigin: NSPoint?, animate: Bool) {
        let clamped = max(0.35, min(value, 1.25))
        let oldFrame = panel.frame
        let newSize = Self.scaledSize(baseSize: baseSize, scale: clamped)
        let newOrigin = anchorOrigin ?? NSPoint(
            x: oldFrame.midX - newSize.width / 2,
            y: oldFrame.minY
        )
        panel.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: animate)
        UserDefaults.standard.set(Double(clamped), forKey: "petScale")
        onScaleChanged(clamped)
        if animate { panel.saveFrame(usingName: "TypingPetWindow") }
    }

    private func bounce() {
        let amplitudes: [CGFloat] = [0, 4, 9, 15]
        let amplitude = amplitudes[shakeLevel]
        guard amplitude > 0 else { return }
        guard let layer = imageView.layer else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        animation.values = [0, amplitude, 0]
        animation.keyTimes = [0, 0.42, 1]
        animation.duration = 0.16
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "typingBounce")
    }

    private static func scaledSize(baseSize: NSSize, scale: CGFloat) -> NSSize {
        NSSize(
            width: baseSize.width * scale,
            height: baseSize.height * scale
        )
    }

    private static func normalizedBaseSize(for imageSize: NSSize) -> NSSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return PetConstants.fallbackBaseSize
        }

        let longestSide: CGFloat = 453
        if imageSize.width >= imageSize.height {
            return NSSize(
                width: longestSide,
                height: longestSide * imageSize.height / imageSize.width
            )
        }
        return NSSize(
            width: longestSide * imageSize.width / imageSize.height,
            height: longestSide
        )
    }

    private static var savedScale: CGFloat {
        let value = UserDefaults.standard.double(forKey: "petScale")
        return value > 0 ? CGFloat(value) : 0.62
    }

    private static var savedRestingOpacity: CGFloat {
        guard let value = UserDefaults.standard.object(forKey: "restingOpacity") as? Double else {
            return 1
        }
        return min(max(CGFloat(value), 0), 1)
    }

    private static var savedHoverOpacity: CGFloat {
        guard let value = UserDefaults.standard.object(forKey: "hoverOpacity") as? Double else {
            return 0.3
        }
        return min(max(CGFloat(value), 0), 1)
    }

    private static var savedAvoidsPointerWhenLocked: Bool {
        UserDefaults.standard.bool(forKey: "avoidsPointerWhenLocked")
    }

    private static var savedAlwaysOnTop: Bool {
        if UserDefaults.standard.object(forKey: "alwaysOnTop") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "alwaysOnTop")
    }

    private static var savedPositionLocked: Bool {
        UserDefaults.standard.bool(forKey: "positionLocked")
    }
}

private final class GlobalKeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let handler: (KeyStroke) -> Void

    init(handler: @escaping (KeyStroke) -> Void) {
        self.handler = handler
    }

    var isRunning: Bool {
        eventTap != nil
    }

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        stop()

        guard CGPreflightListenEventAccess() else {
            return false
        }

        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let callback: CGEventTapCallBack = { _, eventType, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<GlobalKeyMonitor>
                .fromOpaque(userInfo)
                .takeUnretainedValue()

            if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            } else if eventType == .keyDown {
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                monitor.handler(KeyStroke(keyCode: keyCode, modifiers: KeyModifiers(eventFlags: event.flags)))
            }

            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let imageLibrary = PetImageLibrary()
    private let keyReactionStore = KeyReactionStore()
    private var statusItem: NSStatusItem!
    private var petController: PetController!
    private var keyMonitor: GlobalKeyMonitor!
    private var menu: NSMenu!
    private var petVisibilityItem: NSMenuItem!
    private var positionLockedItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var monitoringStatusItem: NSMenuItem!
    private var permissionRetryTimer: Timer?
    private var didShowPermissionAlert = false
    private var settingsWindowController: SettingsWindowController?
    private var settingsModel: TypingPetSettingsModel?
    private var inputMonitoringGuideController: InputMonitoringGuideController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        petController = PetController(
            library: imageLibrary,
            keyStore: keyReactionStore,
            onScaleChanged: { [weak self] scale in self?.settingsModel?.syncScale(scale) }
        )
        configureStatusItem()

        keyMonitor = GlobalKeyMonitor { [weak self] stroke in
            DispatchQueue.main.async {
                self?.petController.handleKeystroke(stroke)
            }
        }

        startMonitoringOrRequestPermission(shouldShowAlert: true)

        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionRetryTimer?.invalidate()
        keyMonitor.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        retryMonitoringIfAuthorized()
        settingsModel?.refresh()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !petController.isPetVisible {
            petController.showPet()
        }
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        petVisibilityItem.title = petController.isPetVisible ? "隐藏宠物" : "重新显示宠物"
        positionLockedItem.state = petController.isPositionLocked ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        updateMonitoringStatusItem()
    }

    @objc private func toggleAlwaysOnTop() {
        petController.isAlwaysOnTop.toggle()
    }

    @objc private func togglePetVisibility() {
        petController.togglePetVisibility()
    }

    @objc private func togglePositionLock() {
        petController.isPositionLocked.toggle()
    }

    @objc private func resetPosition() {
        petController.resetPosition()
    }

    @objc private func setSmallSize() {
        petController.scale = 0.46
    }

    @objc private func setMediumSize() {
        petController.scale = 0.62
    }

    @objc private func setLargeSize() {
        petController.scale = 0.82
    }

    @objc private func setExtraLargeSize() {
        petController.scale = 1.08
    }

    @objc private func changeIdleImage() {
        guard let url = chooseImageFiles(
            title: "选择待机图像",
            message: "请选择无按键输入时显示的图像。",
            allowsMultipleSelection: false
        )?.first else { return }

        do {
            try imageLibrary.replaceIdle(with: url)
            petController.reloadImages()
        } catch {
            showImageError(error)
        }
    }

    @objc private func replaceReactionImages() {
        guard let urls = chooseImageFiles(
            title: "选择反应图像",
            message: "请选择按下按键时随机显示的一张或多张图像。",
            allowsMultipleSelection: true
        ), !urls.isEmpty else { return }

        do {
            try imageLibrary.replaceReactions(with: urls)
            petController.reloadImages()
        } catch {
            showImageError(error)
        }
    }

    @objc private func importImageFolder() {
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        let panel = NSOpenPanel()
        panel.title = "导入图像文件夹"
        panel.message = "idle.* 或 pet-idle.* 作为待机图像，其余作为按键输入反应图像导入。"
        panel.prompt = "导入"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }

        do {
            let result = try imageLibrary.importFolder(folderURL)
            petController.reloadImages()

            var parts: [String] = []
            if result.changedIdle {
                parts.append("待机图像 1 张")
            }
            if let reactionCount = result.reactionCount {
                parts.append("反应图像 \(reactionCount) 张")
            }
            showAlert(
                title: "图像导入成功",
                message: "已应用 " + parts.joined(separator: ", ") + "。",
                primaryButton: "好"
            )
        } catch {
            showImageError(error)
        }
    }

    @objc private func showImageFolderRules() {
        showAlert(
            title: "图像集文件夹规则",
            message: "文件名无限制。若包含 idle.* 或 pet-idle.* 文件，将作为待机图像，其余作为按键输入反应图像。若无待机图像，则按文件名排序的第一张作为待机图像。若仅有 1 张图像，则同时用于待机和反应。支持 PNG、APNG、JPG、GIF、TIFF、HEIC、WebP 格式。",
            primaryButton: "好"
        )
    }

    @objc private func resetImages() {
        showAlert(
            title: "确定恢复为默认图像吗？",
            message: "将当前选中的待机图像和反应图像设置恢复为默认值。不会修改原始图像文件。",
            primaryButton: "恢复",
            secondaryButton: "取消"
        ) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.imageLibrary.resetToDefaults()
            self?.petController.reloadImages()
        }
    }

    @objc private func restartMonitoring() {
        startMonitoringOrRequestPermission(shouldShowAlert: true)
    }

    @objc private func previewReaction() {
        petController.handleKeystroke(nil)
    }

    @objc private func showSettings() {
        if settingsModel == nil {
            settingsModel = TypingPetSettingsModel(
                library: imageLibrary,
                keyStore: keyReactionStore,
                scale: petController.scale,
                restingOpacity: petController.restingOpacity,
                hoverOpacity: petController.hoverOpacity,
                shakeLevel: petController.shakeLevel,
                alwaysOnTop: petController.isAlwaysOnTop,
                positionLocked: petController.isPositionLocked,
                avoidsPointerWhenLocked: petController.avoidsPointerWhenLocked,
                applyScale: { [weak self] in self?.petController.scale = $0 },
                applyRestingOpacity: { [weak self] in self?.petController.restingOpacity = $0 },
                applyHoverOpacity: { [weak self] in self?.petController.hoverOpacity = $0 },
                applyShake: { [weak self] in self?.petController.shakeLevel = $0 },
                applyAlwaysOnTop: { [weak self] in self?.petController.isAlwaysOnTop = $0 },
                applyPositionLock: { [weak self] in self?.petController.isPositionLocked = $0 },
                applyPointerAvoidance: { [weak self] in self?.petController.avoidsPointerWhenLocked = $0 },
                reloadPet: { [weak self] in self?.petController.reloadImages() },
                openInputMonitoringSettings: { [weak self] in self?.openInputMonitoringSettings() }
            )
        }
        settingsModel?.refresh()
        if settingsWindowController == nil, let settingsModel {
            settingsWindowController = SettingsWindowController(model: settingsModel)
        }
        settingsWindowController?.show()
    }

    @objc private func openInputMonitoringSettings() {
        InputMonitoringSettings.open()
        guard !CGPreflightListenEventAccess() else { return }

        if inputMonitoringGuideController == nil {
            inputMonitoringGuideController = InputMonitoringGuideController { [weak self] in
                self?.retryMonitoringIfAuthorized()
                self?.settingsModel?.refresh()
            }
        }
        inputMonitoringGuideController?.show()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(
                title: "设置自动启动失败",
                message: error.localizedDescription,
                primaryButton: "好"
            )
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Typing Pet")
            image?.isTemplate = true
            button.image = image
        }

        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        menu.addItem(makeMenuItem("设置", action: #selector(showSettings), keyEquivalent: ","))
        petVisibilityItem = makeMenuItem("隐藏宠物", action: #selector(togglePetVisibility))
        menu.addItem(petVisibilityItem)
        menu.addItem(.separator())

        positionLockedItem = makeMenuItem("锁定位置 (点击穿透)", action: #selector(togglePositionLock))
        menu.addItem(positionLockedItem)
        menu.addItem(makeMenuItem("重置位置", action: #selector(resetPosition)))
        menu.addItem(.separator())
        monitoringStatusItem = NSMenuItem(title: "按键监听 (检测中)", action: nil, keyEquivalent: "")
        monitoringStatusItem.isEnabled = true
        menu.addItem(monitoringStatusItem)
        updateMonitoringStatusItem()
        menu.addItem(makeMenuItem("输入监控设置", action: #selector(openInputMonitoringSettings)))
        menu.addItem(.separator())

        loginItem = makeMenuItem("登录时自动启动", action: #selector(toggleLaunchAtLogin))
        menu.addItem(loginItem)
        menu.addItem(makeMenuItem("退出 Typing Pet", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func updateMonitoringStatusItem() {
        let isAvailable = keyMonitor?.isRunning == true
        let title = isAvailable ? "按键监听 (正常)" : "按键监听 (未授权/异常)"
        monitoringStatusItem.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: isAvailable ? NSColor.systemGreen : NSColor.systemRed
            ]
        )
    }

    private func makeMenuItem(
        _ title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func chooseImageFiles(
        title: String,
        message: String,
        allowsMultipleSelection: Bool
    ) -> [URL]? {
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = "选择"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.allowedContentTypes = [.image]
        return panel.runModal() == .OK ? panel.urls : nil
    }

    private func showImageError(_ error: Error) {
        showAlert(
            title: "无法应用图像",
            message: error.localizedDescription,
            primaryButton: "好"
        )
    }

    private func startMonitoringOrRequestPermission(shouldShowAlert: Bool) {
        if CGPreflightListenEventAccess(), keyMonitor.start() {
            permissionRetryTimer?.invalidate()
            permissionRetryTimer = nil
            return
        }

        schedulePermissionRetry()
        guard shouldShowAlert, !didShowPermissionAlert else { return }
        didShowPermissionAlert = true
        _ = CGRequestListenEventAccess()
        showAlert(
            title: "需要输入监控权限",
            message: "Typing Pet 不会读取或保存您的输入内容，仅检测是否有按键按下。在系统设置中允许 Typing Pet 的输入监控权限后，应用将自动恢复连接。",
            primaryButton: "打开系统设置",
            secondaryButton: "稍后"
        ) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.openInputMonitoringSettings()
            }
        }
    }

    private func schedulePermissionRetry() {
        guard permissionRetryTimer == nil else { return }
        permissionRetryTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(retryMonitoringIfAuthorized),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func retryMonitoringIfAuthorized() {
        guard !keyMonitor.isRunning, CGPreflightListenEventAccess() else { return }
        if keyMonitor.start() {
            permissionRetryTimer?.invalidate()
            permissionRetryTimer = nil
        }
    }

    private func showAlert(
        title: String,
        message: String,
        primaryButton: String,
        secondaryButton: String? = nil,
        completion: ((NSApplication.ModalResponse) -> Void)? = nil
    ) {
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: primaryButton)
        if let secondaryButton {
            alert.addButton(withTitle: secondaryButton)
        }
        let response = alert.runModal()
        completion?(response)
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
