import Testing
@testable import WedgeApp

@Suite struct MaxDimensionInputTests {
    @Test func emptyAndWhitespaceMeanNoLimit() {
        #expect(MaxDimensionInput.parse("") == .empty)
        #expect(MaxDimensionInput.parse("  ") == .empty)
    }

    @Test func positiveIntegersInRangeAreValid() {
        #expect(MaxDimensionInput.parse("800") == .valid(800))
        #expect(MaxDimensionInput.parse("1") == .valid(1))
        #expect(MaxDimensionInput.parse("16384") == .valid(16384))
    }

    @Test func everythingElseIsInvalid() {
        for text in ["abc", "0", "12.5", "-3", "20000", "16385", "1e3", "99999999999999999999"] {
            #expect(MaxDimensionInput.parse(text) == .invalid, "\(text)")
        }
    }
}
