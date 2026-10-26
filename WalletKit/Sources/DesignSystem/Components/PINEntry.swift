/// The digits typed into a `PINPad` so far, kept out of the view so it can be tested.
///
/// Holds the PIN only until it is complete; `PINPad` hands it over and resets.
/// Never log or persist this value.
struct PINEntry: Equatable, Sendable {
    let length: Int
    private(set) var digits: [Int] = []

    init(length: Int) {
        self.length = max(1, length)
    }

    var isComplete: Bool { digits.count == length }
    var value: String { digits.map(String.init).joined() }

    /// Ignores input once complete or if `digit` isn't 0...9.
    mutating func append(_ digit: Int) {
        guard !isComplete, (0...9).contains(digit) else { return }
        digits.append(digit)
    }

    mutating func deleteLast() {
        _ = digits.popLast()
    }

    mutating func reset() {
        digits.removeAll()
    }
}
