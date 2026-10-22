import Foundation
import WedgeCore

/// What the user picked in the shelf for the current batch. Nil means "follow the saved settings".
struct ShelfChoices: Equatable {
    enum Output: Equatable {
        case nextToOriginals
        case folder(URL)
    }

    var target: FileFormat?
    var output: Output?

    /// A new batch starts from the saved defaults.
    mutating func itemsChanged(isEmpty: Bool) {
        if isEmpty { self = ShelfChoices() }
    }

    /// Changing the saved folder supersedes an earlier one-off choice.
    mutating func savedFolderChanged() {
        output = nil
    }
}
