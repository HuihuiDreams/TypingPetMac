import AppKit
import CoreGraphics
import QuartzCore

// MARK: - Pet Constants

enum PetConstants {
    static let fallbackBaseSize = AppPreferencesDefault.fallbackBaseSize
    static let idleDelay: TimeInterval = AppPreferencesDefault.idleDelay
    /// 图像归一化后的最长边（pt），与默认图集的回退尺寸一致。
    static let normalizedLongestSide: CGFloat = 453
    /// 计算松手速度时保留的拖拽采样时长（秒）。
    static let dragSampleWindow: TimeInterval = 0.15
    /// 惯性滑行的启动与停止速度阈值（pt/s）。
    static let inertiaStartSpeed: CGFloat = 45
    static let inertiaStopSpeed: CGFloat = 18
    /// 指针躲避弹簧参数：追踪目标时的刚度/阻尼、无目标时的阻尼、速度上限与停止阈值。
    static let avoidanceStiffness: CGFloat = 58
    static let avoidanceDamping: CGFloat = 13
    static let avoidanceSettleDamping: CGFloat = 16
    static let avoidanceMaxSpeed: CGFloat = 520
    static let avoidanceStopSpeed: CGFloat = 5
    /// 按抖动等级索引的击键弹跳幅度（pt）。
    static let bounceAmplitudes: [CGFloat] = [0, 4, 9, 15]
}

// MARK: - PetController

@MainActor
internal final class PetController: NSObject {
    private let library: PetImageLibrary
    private let keyStore: KeyReactionStore
    private let panel: PetPanel
    private let contentView: PetContentView
    private let imageView: NSImageView
    private let onScaleChanged: (CGFloat) -> Void
    private var baseSize: NSSize
    private var currentImageKey = ""
    private var reactionPicker = ImagePicker(names: [])
    private var reactionURLsByPath: [String: URL] = [:]
    private var cachedScale: CGFloat = PetController.savedScale
    private var cachedRestingOpacity: CGFloat = PetController.savedRestingOpacity
    private var cachedHoverOpacity: CGFloat = PetController.savedHoverOpacity
    private var cachedAvoidsPointerWhenLocked: Bool = PetController.savedAvoidsPointerWhenLocked
    private var cachedShakeLevel: Int = PetController.savedShakeLevel
    private var idleWorkItem: DispatchWorkItem?
    private var resizeInitialMouseLocation: NSPoint?
    private var resizeInitialFrame: NSRect?
    private var resizeInitialScale: CGFloat?
    private var resizeLatestScale: CGFloat?
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
        let initialImage = library.idleURL.flatMap { library.image(for: $0) }
        baseSize = Self.normalizedBaseSize(for: initialImage?.size ?? PetConstants.fallbackBaseSize)
        panel = PetPanel(
            contentRect: NSRect(
                origin: .zero,
                size: Self.scaledSize(baseSize: baseSize, scale: cachedScale)
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

        let restoredPosition = panel.setFrameUsingName(AppPreferencesKey.windowFrame)
        resizePanelForCurrentCanvas(animate: false)
        if !restoredPosition {
            resetPosition()
        }

        updateReactionImages()
        showIdleImage()
        panel.orderFrontRegardless()
        updateMouseMonitoringState()
        updatePetOpacity()
        updatePointerAvoidance()
    }

    deinit {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        inertiaTimer?.invalidate()
        avoidanceTimer?.invalidate()
        idleWorkItem?.cancel()
    }

    var isAlwaysOnTop: Bool {
        get { panel.level == .floating }
        set {
            panel.level = newValue ? .floating : .normal
            UserDefaults.standard.set(newValue, forKey: AppPreferencesKey.alwaysOnTop)
        }
    }

    var isPositionLocked: Bool {
        get { panel.ignoresMouseEvents }
        set {
            if newValue { stopInertia(savePosition: true) }
            panel.ignoresMouseEvents = newValue
            contentView.controlsEnabled = !newValue
            UserDefaults.standard.set(newValue, forKey: AppPreferencesKey.positionLocked)
            updateMouseMonitoringState()
            if newValue {
                updatePointerAvoidance()
            } else {
                stopPointerAvoidance(savePosition: true)
            }
        }
    }

    var isPetVisible: Bool { panel.isVisible }

    var scale: CGFloat {
        get { cachedScale }
        set {
            cachedScale = applyScale(newValue, anchorOrigin: nil, animate: false)
            UserDefaults.standard.set(Double(cachedScale), forKey: AppPreferencesKey.petScale)
            panel.saveFrame(usingName: AppPreferencesKey.windowFrame)
        }
    }

    var restingOpacity: CGFloat {
        get { cachedRestingOpacity }
        set {
            let clamped = min(max(newValue, 0), 1)
            guard clamped != cachedRestingOpacity else { return }
            cachedRestingOpacity = clamped
            UserDefaults.standard.set(Double(clamped), forKey: AppPreferencesKey.restingOpacity)
            updateMouseMonitoringState()
            updatePetOpacity()
        }
    }

    var hoverOpacity: CGFloat {
        get { cachedHoverOpacity }
        set {
            let clamped = min(max(newValue, 0), 1)
            guard clamped != cachedHoverOpacity else { return }
            cachedHoverOpacity = clamped
            UserDefaults.standard.set(Double(clamped), forKey: AppPreferencesKey.hoverOpacity)
            updateMouseMonitoringState()
            updatePetOpacity()
        }
    }

    var avoidsPointerWhenLocked: Bool {
        get { cachedAvoidsPointerWhenLocked }
        set {
            guard newValue != cachedAvoidsPointerWhenLocked else { return }
            cachedAvoidsPointerWhenLocked = newValue
            UserDefaults.standard.set(newValue, forKey: AppPreferencesKey.avoidsPointerWhenLocked)
            updateMouseMonitoringState()
            if newValue {
                updatePointerAvoidance()
            } else {
                stopPointerAvoidance(savePosition: true)
            }
        }
    }

    var shakeLevel: Int {
        get { cachedShakeLevel }
        set {
            let clamped = max(AppPreferencesDefault.minShakeLevel, min(newValue, AppPreferencesDefault.maxShakeLevel))
            guard clamped != cachedShakeLevel else { return }
            cachedShakeLevel = clamped
            UserDefaults.standard.set(clamped, forKey: AppPreferencesKey.shakeLevel)
        }
    }

    func handleKeystroke(_ stroke: KeyStroke? = nil) {
        let chosenURL: URL?
        if let stroke, let exactMatch = keyStore.imageURL(matching: stroke) {
            chosenURL = exactMatch
        } else {
            chosenURL = reactionPicker.next(excluding: currentImageKey).flatMap { reactionURLsByPath[$0] }
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
        updateReactionImages()
        if let idleImage = library.idleURL.flatMap({ library.image(for: $0) }) {
            baseSize = Self.normalizedBaseSize(for: idleImage.size)
        } else {
            baseSize = PetConstants.fallbackBaseSize
        }
        resizePanelForCurrentCanvas(animate: true)
        showIdleImage()
    }

    private func updateReactionImages() {
        let urls = library.reactionURLs
        reactionURLsByPath = urls.reduce(into: [:]) { $0[$1.path] = $1 }
        reactionPicker = ImagePicker(names: urls.map(\.path))
    }

    func hidePet() {
        stopInertia(savePosition: true)
        stopPointerAvoidance(savePosition: true)
        contentView.hideControls()
        panel.orderOut(nil)
        updateMouseMonitoringState()
    }

    func showPet() {
        contentView.hideControls()
        panel.orderFrontRegardless()
        updateMouseMonitoringState()
        updatePetOpacity()
        updatePointerAvoidance()
    }

    func togglePetVisibility() {
        isPetVisible ? hidePet() : showPet()
    }

    func resetPosition() {
        stopInertia(savePosition: false)
        stopPointerAvoidance(savePosition: false)
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 24, y: visible.minY + 24))
        panel.saveFrame(usingName: AppPreferencesKey.windowFrame)
    }

    func clampToVisibleScreen() {
        // Motion bounds belong to the previous screen configuration.
        stopInertia(savePosition: false)
        stopPointerAvoidance(savePosition: false)
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let bounds = screen.visibleFrame
        let origin = PetPointerAvoidance.clampedOrigin(panel.frame.origin, size: panel.frame.size, bounds: bounds)
        guard origin != panel.frame.origin else { return }
        panel.setFrameOrigin(origin)
        panel.saveFrame(usingName: AppPreferencesKey.windowFrame)
    }

    private func showIdleImage() {
        guard let idleURL = library.idleURL else { return }
        showImage(at: idleURL)
    }

    private func showImage(at url: URL) {
        if currentImageKey == url.path, imageView.image != nil { return }
        guard let image = library.image(for: url) else { return }
        currentImageKey = url.path
        imageView.image = image
    }

    private func resizePanelForCurrentCanvas(animate: Bool) {
        let oldFrame = panel.frame
        let newSize = Self.scaledSize(baseSize: baseSize, scale: cachedScale)
        let newOrigin = NSPoint(x: oldFrame.midX - newSize.width / 2, y: oldFrame.minY)
        panel.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: animate)
        panel.saveFrame(usingName: AppPreferencesKey.windowFrame)
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
        let cutoff = sample.timestamp - PetConstants.dragSampleWindow
        moveSamples.removeAll { $0.timestamp < cutoff }
    }

    private func startInertia(with velocity: CGVector) {
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed >= PetConstants.inertiaStartSpeed else {
            panel.saveFrame(usingName: AppPreferencesKey.windowFrame)
            return
        }
        inertiaVelocity = velocity
        inertiaLastTimestamp = ProcessInfo.processInfo.systemUptime
        inertiaBounds = (panel.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
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
        if hypot(step.velocity.dx, step.velocity.dy) < PetConstants.inertiaStopSpeed {
            stopInertia(savePosition: true)
        }
    }

    private func stopInertia(savePosition: Bool) {
        inertiaTimer?.invalidate()
        inertiaTimer = nil
        inertiaVelocity = .zero
        inertiaLastTimestamp = nil
        inertiaBounds = nil
        if savePosition { panel.saveFrame(usingName: AppPreferencesKey.windowFrame) }
    }

    private func updateMouseMonitoringState() {
        let needsMonitoring = panel.isVisible && (
            abs(cachedRestingOpacity - cachedHoverOpacity) > 0.001 ||
            (isPositionLocked && cachedAvoidsPointerWhenLocked)
        )
        needsMonitoring ? startMouseHoverMonitoring() : stopMouseHoverMonitoring()
    }

    private func startMouseHoverMonitoring() {
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated { self?.handlePointerMotion() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointerMotion() }
            return event
        }
    }

    private func stopMouseHoverMonitoring() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
    }

    private func handlePointerMotion() {
        updatePetOpacity()
        updatePointerAvoidance()
    }

    private func updatePetOpacity() {
        guard panel.isVisible, let imageLayer = imageView.layer else { return }
        let targetOpacity = PetOpacityBehavior.opacity(
            isHovering: panel.frame.contains(NSEvent.mouseLocation),
            restingOpacity: cachedRestingOpacity,
            hoverOpacity: cachedHoverOpacity
        )
        guard abs(CGFloat(imageLayer.opacity) - targetOpacity) > 0.001 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.opacity = Float(targetOpacity)
        CATransaction.commit()
    }

    private func updatePointerAvoidance() {
        guard avoidanceTimer == nil, panel.isVisible, isPositionLocked, avoidsPointerWhenLocked else { return }
        let bounds = avoidanceBounds ?? (panel.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? panel.frame
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
        let stiffness: CGFloat = target == nil ? 0 : PetConstants.avoidanceStiffness
        let damping: CGFloat = target == nil ? PetConstants.avoidanceSettleDamping : PetConstants.avoidanceDamping
        avoidanceVelocity.dx += (delta.dx * stiffness - avoidanceVelocity.dx * damping) * elapsed
        avoidanceVelocity.dy += (delta.dy * stiffness - avoidanceVelocity.dy * damping) * elapsed

        let speed = hypot(avoidanceVelocity.dx, avoidanceVelocity.dy)
        if speed > PetConstants.avoidanceMaxSpeed {
            let factor = PetConstants.avoidanceMaxSpeed / speed
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

        if (target == nil || hypot(delta.dx, delta.dy) < 0.5), hypot(avoidanceVelocity.dx, avoidanceVelocity.dy) < PetConstants.avoidanceStopSpeed {
            stopPointerAvoidance(savePosition: true)
        }
    }

    private func stopPointerAvoidance(savePosition: Bool) {
        avoidanceTimer?.invalidate()
        avoidanceTimer = nil
        avoidanceVelocity = .zero
        avoidanceLastTimestamp = nil
        avoidanceBounds = nil
        if savePosition { panel.saveFrame(usingName: AppPreferencesKey.windowFrame) }
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
        resizeLatestScale = applyScale(newScale, anchorOrigin: initialFrame.origin, animate: false)
    }

    private func endResize() {
        if let resizeLatestScale {
            cachedScale = resizeLatestScale
            UserDefaults.standard.set(Double(resizeLatestScale), forKey: AppPreferencesKey.petScale)
        }
        resizeInitialMouseLocation = nil
        resizeInitialFrame = nil
        resizeInitialScale = nil
        resizeLatestScale = nil
        panel.saveFrame(usingName: AppPreferencesKey.windowFrame)
    }

    /// 拖拽缩放（`animate == false`）时只更新窗口，由 `endResize()` 统一持久化，避免每个鼠标事件都写 UserDefaults。
    @discardableResult
    private func applyScale(_ value: CGFloat, anchorOrigin: NSPoint?, animate: Bool) -> CGFloat {
        let clamped = max(AppPreferencesDefault.minScale, min(value, AppPreferencesDefault.maxScale))
        let oldFrame = panel.frame
        let newSize = Self.scaledSize(baseSize: baseSize, scale: clamped)
        let newOrigin = anchorOrigin ?? NSPoint(
            x: oldFrame.midX - newSize.width / 2,
            y: oldFrame.minY
        )
        panel.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: animate)
        onScaleChanged(clamped)
        if animate {
            UserDefaults.standard.set(Double(clamped), forKey: AppPreferencesKey.petScale)
            panel.saveFrame(usingName: AppPreferencesKey.windowFrame)
        }
        return clamped
    }

    private func bounce() {
        let level = shakeLevel
        guard PetConstants.bounceAmplitudes.indices.contains(level) else { return }
        let amplitude = PetConstants.bounceAmplitudes[level]
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
        NSSize(width: baseSize.width * scale, height: baseSize.height * scale)
    }

    private static func normalizedBaseSize(for imageSize: NSSize) -> NSSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return PetConstants.fallbackBaseSize }
        let longest = PetConstants.normalizedLongestSide
        return imageSize.width >= imageSize.height
            ? NSSize(width: longest, height: longest * imageSize.height / imageSize.width)
            : NSSize(width: longest * imageSize.width / imageSize.height, height: longest)
    }

    private static var savedScale: CGFloat {
        let value = UserDefaults.standard.double(forKey: AppPreferencesKey.petScale)
        return value > 0 ? CGFloat(value) : AppPreferencesDefault.petScale
    }

    private static var savedRestingOpacity: CGFloat {
        let value = UserDefaults.standard.object(forKey: AppPreferencesKey.restingOpacity) as? Double
        return min(max(CGFloat(value ?? AppPreferencesDefault.restingOpacity), 0), 1)
    }

    private static var savedHoverOpacity: CGFloat {
        let value = UserDefaults.standard.object(forKey: AppPreferencesKey.hoverOpacity) as? Double
        return min(max(CGFloat(value ?? AppPreferencesDefault.hoverOpacity), 0), 1)
    }

    private static var savedAvoidsPointerWhenLocked: Bool {
        UserDefaults.standard.bool(forKey: AppPreferencesKey.avoidsPointerWhenLocked)
    }

    private static var savedAlwaysOnTop: Bool {
        UserDefaults.standard.object(forKey: AppPreferencesKey.alwaysOnTop) == nil
            ? AppPreferencesDefault.alwaysOnTop
            : UserDefaults.standard.bool(forKey: AppPreferencesKey.alwaysOnTop)
    }

    private static var savedPositionLocked: Bool {
        UserDefaults.standard.bool(forKey: AppPreferencesKey.positionLocked)
    }

    private static var savedShakeLevel: Int {
        let stored = UserDefaults.standard.object(forKey: AppPreferencesKey.shakeLevel) as? Int
        return max(AppPreferencesDefault.minShakeLevel, min(stored ?? AppPreferencesDefault.shakeLevel, AppPreferencesDefault.maxShakeLevel))
    }
}
