import AppKit
import XCTest
@testable import TypingPet

final class TodoBubbleTests: XCTestCase {
    func testScreenEdgesAndSmallScreenContainAllControls() {
        for screen in [CGRect(x: 0, y: 24, width: 1440, height: 876), CGRect(x: -1920, y: -200, width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 300, height: 250)] {
            for x in [screen.minX, screen.midX, screen.maxX - 180] {
                for y in [screen.minY, screen.midY, screen.maxY - 140] {
                    let pet = CGRect(x: x, y: y, width: 180, height: 140)
                    let frame = TodoBubbleGeometry.frame(size: CGSize(width: 340, height: 430), pet: pet, visible: screen)
                    XCTAssertTrue(screen.contains(frame))
                    XCTAssertTrue(screen.contains(TodoBubbleGeometry.entryFrame(pet: pet, visible: screen)))
                }
            }
        }
    }
    func testBottomLeftPetUsesSpaceAbove() {
        let pet = CGRect(x: 12, y: 40, width: 180, height: 140)
        let frame = TodoBubbleGeometry.frame(size: CGSize(width: 340, height: 430), pet: pet, visible: CGRect(x: 0, y: 24, width: 1440, height: 876))
        XCTAssertEqual(frame.minY, pet.maxY + 10)
    }
    @MainActor func testTodoPanelAcceptsFocusAndDoesNotPassClicks() {
        let panel = TodoPanel(contentRect: CGRect(x: 0, y: 0, width: 340, height: 430), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.ignoresMouseEvents)
    }
}
