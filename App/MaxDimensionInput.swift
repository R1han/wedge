import Foundation

enum MaxDimensionInput: Equatable {
    case empty
    case valid(Int)
    case invalid

    static let range = 1...16384

    static func parse(_ text: String) -> MaxDimensionInput {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .empty }
        guard trimmed.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(trimmed), range.contains(value) else { return .invalid }
        return .valid(value)
    }
}
