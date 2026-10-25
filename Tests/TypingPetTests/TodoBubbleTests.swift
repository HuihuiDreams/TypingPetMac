import AppKit
import Testing
@testable import TypingPet

@Suite struct TodoBubbleTests {
    @Test func screenEdgesAndSmallScreenContainAllControls() {
        for screen in [CGRect(x: 0, y: 24, width: 1440, height: 876), CGRect(x: -1920, y: -200, width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 300, height: 250)] {
            for x in [screen.minX, screen.midX, screen.maxX - 180] {
                for y in [screen.minY, screen.midY, screen.maxY - 140] {
                    let pet = CGRect(x: x, y: y, width: 180, height: 140)
                    let frame = TodoBubbleGeometry.frame(size: CGSize(width: 340, height: 430), pet: pet, visible: screen)
                    #expect(screen.contains(frame))
                    #expect(screen.contains(TodoBubbleGeometry.entryFrame(pet: pet, visible: screen)))
                }
            }
        }
    }

    @Test func bottomLeftPetUsesSpaceAbove() {
        let pet = CGRect(x: 12, y: 40, width: 180, height: 140)
        let frame = TodoBubbleGeometry.frame(size: CGSize(width: 340, height: 430), pet: pet, visible: CGRect(x: 0, y: 24, width: 1440, height: 876))
        #expect(frame.minY == pet.maxY + 10)
    }

    @Test func tailFacesThePetOnEverySide() {
        let screen = CGRect(x: 0, y: 24, width: 1440, height: 876)
        let content = CGSize(width: 320, height: 300)
        let bottomLeft = TodoBubbleGeometry.placement(content: content, tail: 10, pet: CGRect(x: 12, y: 40, width: 180, height: 140), visible: screen, gap: 2)
        #expect(bottomLeft.tailEdge == .bottom)
        #expect(bottomLeft.frame.height == 310)
        #expect(bottomLeft.tailOffset < 0)
        let left = TodoBubbleGeometry.placement(content: content, tail: 10, pet: CGRect(x: 12, y: 500, width: 180, height: 140), visible: screen, gap: 2)
        #expect(left.tailEdge == .leading)
        #expect(left.frame.width == 330)
        let right = TodoBubbleGeometry.placement(content: content, tail: 10, pet: CGRect(x: 1250, y: 500, width: 180, height: 140), visible: screen, gap: 2)
        #expect(right.tailEdge == .trailing)
        let topCorner = TodoBubbleGeometry.placement(content: content, tail: 10, pet: CGRect(x: 12, y: 750, width: 180, height: 140), visible: screen, gap: 2)
        #expect(topCorner.tailEdge == .leading)
        let narrow = CGRect(x: 0, y: 24, width: 400, height: 876)
        let below = TodoBubbleGeometry.placement(content: content, tail: 10, pet: CGRect(x: 110, y: 750, width: 180, height: 140), visible: narrow, gap: 2)
        #expect(below.tailEdge == .top)
        #expect(narrow.contains(below.frame))
        for placement in [bottomLeft, left, right, topCorner] {
            #expect(screen.contains(placement.frame))
            let limit = (placement.tailEdge == .bottom || placement.tailEdge == .top ? placement.frame.width : placement.frame.height) / 2 - 28
            #expect(abs(placement.tailOffset) <= limit)
        }
    }

    @Test func zoomStepsSnapLikeABrowser() {
        #expect(TodoBubbleZoom.larger(than: 1) == 1.1)
        #expect(TodoBubbleZoom.smaller(than: 1) == 0.9)
        #expect(TodoBubbleZoom.larger(than: 2) == 2)
        #expect(TodoBubbleZoom.smaller(than: 0.8) == 0.8)
        #expect(TodoBubbleZoom.normalized(1.3) == 1.25)
    }

    @Test func canvasKeepsBubbleBesidePetAndOnScreen() {
        let screen = CGRect(x: 0, y: 24, width: 1440, height: 876)
        for pet in [CGRect(x: 12, y: 40, width: 220, height: 220), CGRect(x: 1200, y: 640, width: 220, height: 220), CGRect(x: 12, y: 680, width: 220, height: 220)] {
            for content in [CGSize(width: 320, height: 330), CGSize(width: 226, height: 77)] {
                let canvas = TodoBubbleGeometry.canvas(content: content, tail: 10, width: 320, maxHeight: 560, pet: pet, visible: screen)
                #expect(screen.contains(canvas.frame))
                #expect(canvas.frame.insetBy(dx: -0.5, dy: -0.5).contains(canvas.bubble))
                #expect(!canvas.bubble.intersects(pet.insetBy(dx: 1, dy: 1)))
                #expect(canvas.maxContentHeight + 0.5 >= content.height)
            }
        }
    }

    @Test @MainActor func displayPreferencesPersistOutsideTheRecord() throws {
        let suite = "TypingPetTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("display-\(UUID()).json")
        var store = TodoStore(url: url, defaults: defaults)
        #expect(store.listStyle == .full)
        store.zoomIn(); store.setBubbleVisibility(.hover); store.setBubbleRestingOpacity(0.4); store.setBubbleHoverOpacity(0.7)
        store.setListStyle(.compact)
        store = TodoStore(url: url, defaults: defaults)
        #expect(store.listStyle == .compact)
        #expect(store.zoom == 1.1)
        #expect(store.bubbleVisibility == .hover)
        #expect(abs(store.bubbleRestingOpacity - 0.4) <= 0.0001)
        #expect(abs(store.bubbleHoverOpacity - 0.7) <= 0.0001)
    }

    @Test @MainActor func todoPanelAcceptsFocusAndDoesNotPassClicks() {
        let panel = TodoPanel(contentRect: CGRect(x: 0, y: 0, width: 340, height: 430), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.ignoresMouseEvents)
    }
}
