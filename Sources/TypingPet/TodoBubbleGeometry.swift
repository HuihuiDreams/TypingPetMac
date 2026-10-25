import Foundation

// The bubble edge that carries the tail. The tail always faces the pet.
enum TodoBubbleEdge: Equatable { case top, bottom, leading, trailing }

struct TodoBubblePlacement: Equatable {
    var frame: CGRect
    var tailEdge: TodoBubbleEdge
    // Distance from the tail edge's center, in top-left view coordinates.
    var tailOffset: CGFloat
}

struct TodoBubbleCanvas: Equatable {
    var frame: CGRect
    // Where the bubble sits inside the canvas. Only this area takes clicks.
    var bubble: CGRect
    var tailEdge: TodoBubbleEdge
    var tailOffset: CGFloat
    var maxContentHeight: CGFloat
}

// Browser-style steps keep text at predictable sizes and make 100% easy to return to.
enum TodoBubbleZoom {
    static let steps: [Double] = [0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2]
    static func normalized(_ value: Double) -> Double {
        steps.min { abs($0 - value) < abs($1 - value) } ?? 1
    }
    static func larger(than value: Double) -> Double { steps.first { $0 > value + 0.001 } ?? steps[steps.count - 1] }
    static func smaller(than value: Double) -> Double { steps.last { $0 < value - 0.001 } ?? steps[0] }
}

struct TodoBubbleGeometry {
    static func frame(size: CGSize, pet: CGRect, visible: CGRect, gap: CGFloat = 10) -> CGRect {
        placement(content: size, tail: 0, pet: pet, visible: visible, gap: gap).frame
    }

    // Try above, right, left, then below. The tail adds depth on the side that faces the pet.
    static func placement(content: CGSize, tail: CGFloat, pet: CGRect, visible: CGRect, gap: CGFloat = 10, tailInset: CGFloat = 28) -> TodoBubblePlacement {
        let vertical = CGSize(width: min(content.width, visible.width), height: min(content.height + tail, visible.height))
        let horizontal = CGSize(width: min(content.width + tail, visible.width), height: min(content.height, visible.height))
        let candidates: [(CGRect, TodoBubbleEdge)] = [
            (CGRect(origin: CGPoint(x: pet.midX - vertical.width / 2, y: pet.maxY + gap), size: vertical), .bottom),
            (CGRect(origin: CGPoint(x: pet.maxX + gap, y: pet.midY - horizontal.height / 2), size: horizontal), .leading),
            (CGRect(origin: CGPoint(x: pet.minX - horizontal.width - gap, y: pet.midY - horizontal.height / 2), size: horizontal), .trailing),
            (CGRect(origin: CGPoint(x: pet.midX - vertical.width / 2, y: pet.minY - vertical.height - gap), size: vertical), .top)
        ]
        // Slide along the facing edge first so a pet in a corner still gets a bubble beside it.
        let slid = candidates.map { rect, edge -> (CGRect, TodoBubbleEdge) in
            var rect = rect
            switch edge {
            case .top, .bottom: rect.origin.x = min(max(rect.minX, visible.minX), visible.maxX - rect.width)
            case .leading, .trailing: rect.origin.y = min(max(rect.minY, visible.minY), visible.maxY - rect.height)
            }
            return (rect, edge)
        }
        let (raw, edge) = slid.first { visible.contains($0.0) } ?? candidates[0]
        let frame = CGRect(origin: PetPointerAvoidance.clampedOrigin(raw.origin, size: raw.size, bounds: visible), size: raw.size)
        let offset: CGFloat
        switch edge {
        case .top, .bottom:
            let limit = max(0, frame.width / 2 - tailInset)
            offset = min(max(pet.midX - frame.midX, -limit), limit)
        case .leading, .trailing:
            let limit = max(0, frame.height / 2 - tailInset)
            offset = min(max(frame.midY - pet.midY, -limit), limit)
        }
        return TodoBubblePlacement(frame: frame, tailEdge: edge, tailOffset: offset)
    }

    // The panel is a fixed canvas with room for the bubble to grow, so SwiftUI animates in stable coordinates.
    // The bubble sits against the canvas edge that faces the pet.
    // `margin` adds transparent room on every side for a shadow drawn by the bubble itself.
    static func canvas(content: CGSize, tail: CGFloat, width: CGFloat, maxHeight: CGFloat, pet: CGRect, visible: CGRect, gap: CGFloat = 2, tailInset: CGFloat = 28, margin: CGFloat = 0) -> TodoBubbleCanvas {
        let edge = placement(content: content, tail: tail, pet: pet, visible: visible, gap: gap).tailEdge
        var frame: CGRect
        switch edge {
        case .top, .bottom:
            let roomWidth = max(content.width, min(width, visible.width))
            let available = edge == .bottom ? visible.maxY - pet.maxY - gap : pet.minY - gap - visible.minY
            let roomHeight = max(content.height + tail, min(maxHeight + tail, available))
            let y = edge == .bottom ? pet.maxY + gap : pet.minY - gap - roomHeight
            frame = CGRect(x: pet.midX - roomWidth / 2, y: y, width: roomWidth, height: roomHeight)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        case .leading, .trailing:
            let available = edge == .leading ? visible.maxX - pet.maxX - gap : pet.minX - gap - visible.minX
            let roomWidth = max(content.width + tail, min(width + tail, available))
            let roomHeight = max(content.height, min(maxHeight, visible.height))
            let x = edge == .leading ? pet.maxX + gap : pet.minX - gap - roomWidth
            frame = CGRect(x: x, y: pet.midY - roomHeight / 2, width: roomWidth, height: roomHeight)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        let bubble: CGRect
        let offset: CGFloat
        switch edge {
        case .bottom, .top:
            let size = CGSize(width: content.width, height: content.height + tail)
            bubble = CGRect(x: frame.midX - size.width / 2, y: edge == .bottom ? frame.minY : frame.maxY - size.height, width: size.width, height: size.height)
            let limit = max(0, content.width / 2 - tailInset)
            offset = min(max(pet.midX - frame.midX, -limit), limit)
        case .leading, .trailing:
            let size = CGSize(width: content.width + tail, height: content.height)
            bubble = CGRect(x: edge == .leading ? frame.minX : frame.maxX - size.width, y: frame.midY - size.height / 2, width: size.width, height: size.height)
            let limit = max(0, content.height / 2 - tailInset)
            offset = min(max(frame.midY - pet.midY, -limit), limit)
        }
        let maxContentHeight = edge == .top || edge == .bottom ? frame.height - tail : frame.height
        return TodoBubbleCanvas(frame: frame.insetBy(dx: -margin, dy: -margin), bubble: bubble, tailEdge: edge, tailOffset: offset, maxContentHeight: maxContentHeight)
    }

    static let entrySize = CGSize(width: 76, height: 30)

    static func entryFrame(pet: CGRect, visible: CGRect) -> CGRect {
        let size = entrySize
        let right = CGPoint(x: pet.maxX + 6, y: pet.minY + 12)
        let left = CGPoint(x: pet.minX - size.width - 6, y: pet.minY + 12)
        let origin = visible.contains(CGRect(origin: right, size: size)) ? right : left
        return CGRect(origin: PetPointerAvoidance.clampedOrigin(origin, size: size, bounds: visible), size: size)
    }
}
