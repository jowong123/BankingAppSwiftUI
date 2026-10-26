import Testing

@testable import DesignSystem

@Suite struct PINEntryTests {
    @Test func completesAtLength() {
        var entry = PINEntry(length: 6)
        for digit in [1, 2, 3, 4, 5] {
            entry.append(digit)
            #expect(!entry.isComplete)
        }
        entry.append(6)
        #expect(entry.isComplete)
        #expect(entry.value == "123456")
    }

    @Test func ignoresDigitsOnceComplete() {
        var entry = PINEntry(length: 4)
        for digit in [1, 2, 3, 4, 5, 6] { entry.append(digit) }
        #expect(entry.value == "1234")
    }

    @Test(arguments: [-1, 10, 42])
    func ignoresNonDigits(value: Int) {
        var entry = PINEntry(length: 4)
        entry.append(value)
        #expect(entry.digits.isEmpty)
    }

    @Test func keepsLeadingZeros() {
        var entry = PINEntry(length: 4)
        for digit in [0, 0, 7, 0] { entry.append(digit) }
        #expect(entry.value == "0070")
    }

    @Test func deleteLastRemovesOneDigitAndIsSafeWhenEmpty() {
        var entry = PINEntry(length: 4)
        entry.deleteLast()
        #expect(entry.digits.isEmpty)
        entry.append(1)
        entry.append(2)
        entry.deleteLast()
        #expect(entry.value == "1")
    }

    @Test func resetClearsEverything() {
        var entry = PINEntry(length: 4)
        for digit in [1, 2, 3, 4] { entry.append(digit) }
        entry.reset()
        #expect(entry.digits.isEmpty)
        #expect(!entry.isComplete)
    }

    @Test(arguments: [0, -3])
    func lengthBelowOneClampsToOne(length: Int) {
        let entry = PINEntry(length: length)
        #expect(entry.length == 1)
    }
}
