import Foundation

struct TodoBubbleGeometry {
    static func frame(size: CGSize, pet: CGRect, visible: CGRect, gap: CGFloat = 10) -> CGRect {
        let size = CGSize(width: min(size.width, visible.width), height: min(size.height, visible.height))
        let above = CGPoint(x: pet.midX - size.width / 2, y: pet.maxY + gap)
        let right = CGPoint(x: pet.maxX + gap, y: pet.midY - size.height / 2)
        let left = CGPoint(x: pet.minX - size.width - gap, y: pet.midY - size.height / 2)
        let below = CGPoint(x: pet.midX - size.width / 2, y: pet.minY - size.height - gap)
        let candidates = [above, right, left, below]
        let origin = candidates.first { visible.contains(CGRect(origin: $0, size: size)) } ?? above
        return CGRect(origin: PetPointerAvoidance.clampedOrigin(origin, size: size, bounds: visible), size: size)
    }

    static func entryFrame(pet: CGRect, visible: CGRect) -> CGRect {
        let size = CGSize(width: 64, height: 30)
        let right = CGPoint(x: pet.maxX + 6, y: pet.minY + 12)
        let left = CGPoint(x: pet.minX - size.width - 6, y: pet.minY + 12)
        let origin = visible.contains(CGRect(origin: right, size: size)) ? right : left
        return CGRect(origin: PetPointerAvoidance.clampedOrigin(origin, size: size, bounds: visible), size: size)
    }
}
