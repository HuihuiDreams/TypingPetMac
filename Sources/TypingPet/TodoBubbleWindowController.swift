import AppKit
import SwiftUI
import Combine

final class TodoPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class TodoBubbleWindowController {
    let store: TodoStore
    let panel: TodoPanel
    private let entry: TodoPanel
    private weak var pet: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    private var timer: Timer?
    private var lastTick: TimeInterval = 0
    private var notificationTokens: [NSObjectProtocol] = []

    init(store: TodoStore, pet: NSWindow) {
        self.store = store
        self.pet = pet
        panel = Self.makePanel(size: NSSize(width: 340, height: 410))
        entry = Self.makePanel(size: NSSize(width: 64, height: 30))
        panel.contentView = NSHostingView(rootView: TodoBubbleView(store: store))
        entry.contentView = NSHostingView(rootView: Button("할 일") { [weak self] in self?.show() }
            .buttonStyle(.borderedProminent).help("할 일").accessibilityLabel("할 일")
            .frame(maxWidth: .infinity, maxHeight: .infinity))
        store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.synchronize() }
        }.store(in: &subscriptions)
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
            notificationTokens.append(NotificationCenter.default.addObserver(forName: name, object: pet, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.synchronize() }
            })
        }
        notificationTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.synchronize() }
        })
        notificationTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.pauseForSleepOrTermination() }
        })
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if now - self.lastTick >= 1 {
                    self.lastTick = now
                    self.store.tick()
                }
                self.synchronize()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        synchronize()
    }

    private static func makePanel(size: NSSize) -> TodoPanel {
        let panel = TodoPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = AppEnvironment.displayName + " · 할 일"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    var isInteracting: Bool {
        let mouse = NSEvent.mouseLocation
        return (panel.isVisible && (panel.frame.insetBy(dx: -14, dy: -14).contains(mouse) || panel.isKeyWindow))
            || (entry.isVisible && entry.frame.insetBy(dx: -40, dy: -40).contains(mouse))
    }

    func show() {
        store.show()
        synchronize()
        panel.makeKeyAndOrderFront(nil)
    }

    func synchronize() {
        guard let pet, pet.isVisible else {
            panel.orderOut(nil); entry.orderOut(nil); return
        }
        let visible = (pet.screen ?? NSScreen.main)?.visibleFrame ?? pet.frame
        panel.level = pet.level
        entry.level = pet.level
        let preferences = store.engine.state.featurePreferences
        if (preferences.enabled && !preferences.bubbleHidden) || store.errorMessage != nil {
            let session = store.engine.activeSession
            let expanded = store.expanded || session == nil
            let expired = session?.status == .expired
            let size = CGSize(width: expanded ? 340 : 280, height: expanded ? 430 : (expired ? 192 : 156))
            let frame = TodoBubbleGeometry.frame(size: size, pet: pet.frame, visible: visible)
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else { panel.orderOut(nil) }
        let mouse = NSEvent.mouseLocation
        let entryFrame = TodoBubbleGeometry.entryFrame(pet: pet.frame, visible: visible)
        // Show the entry before pointer avoidance moves the pet away.
        let nearPet = PetPointerAvoidance.distance(from: mouse, to: pet.frame) <= 108
        let overEntry = entryFrame.insetBy(dx: -18, dy: -18).contains(mouse)
        if nearPet || overEntry {
            if entry.frame != entryFrame { entry.setFrame(entryFrame, display: true) }
            if !entry.isVisible { entry.orderFrontRegardless() }
        } else { entry.orderOut(nil) }
    }
}
