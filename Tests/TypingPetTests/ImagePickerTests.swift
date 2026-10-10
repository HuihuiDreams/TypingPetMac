import Testing
@testable import TypingPet

@Suite struct ImagePickerTests {
    @Test func pickerExcludesCurrentImage() {
        let picker = ImagePicker(names: ["left", "right", "question"])
        let result = picker.next(excluding: "left") { _ in 0 }
        #expect(result == "right")
    }

    @Test func pickerReturnsOnlyImageWhenNoAlternativeExists() {
        let picker = ImagePicker(names: ["left"])
        let result = picker.next(excluding: "left") { _ in 0 }
        #expect(result == "left")
    }

    @Test func emptyPickerReturnsNil() {
        let picker = ImagePicker(names: [])
        #expect(picker.next(excluding: nil) { _ in 0 } == nil)
    }
}
