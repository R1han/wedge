import Foundation
import Testing
import WedgeCore
@testable import WedgeApp

@Suite struct ShelfChoicesTests {
    private let png = FileFormat.format(forExtension: "png")!
    private let folder = URL(fileURLWithPath: "/tmp/wedge-out", isDirectory: true)

    private func chosen() -> ShelfChoices {
        var choices = ShelfChoices()
        choices.target = png
        choices.output = .folder(folder)
        return choices
    }

    @Test func startsFollowingTheSavedSettings() {
        let choices = ShelfChoices()
        #expect(choices.target == nil)
        #expect(choices.output == nil)
    }

    @Test func emptyingTheShelfClearsBothChoices() {
        var choices = chosen()
        choices.itemsChanged(isEmpty: true)
        #expect(choices.target == nil)
        #expect(choices.output == nil)
    }

    @Test func aNonEmptyShelfKeepsTheChoices() {
        var choices = chosen()
        choices.itemsChanged(isEmpty: false)
        #expect(choices.target == png)
        #expect(choices.output == .folder(folder))
    }

    @Test func changingTheSavedFolderClearsOnlyTheOutputChoice() {
        var choices = chosen()
        choices.savedFolderChanged()
        #expect(choices.output == nil)
        #expect(choices.target == png)
    }
}
