import Foundation

/// The build steps tools/builder_cli.py announces, in order, with their share of the work
/// (measured on an M1 Pro; they add up to 100).
public let buildSteps: [(id: String, weight: Double)] = [
    ("prepare", 4), ("lift", 30), ("compile", 44), ("link", 16), ("package", 5), ("sign", 1),
]

/// Fraction (0...1) of total work completed when the given step begins.
public func progressFraction(atStart stepID: String) -> Double {
    var sum = 0.0
    for step in buildSteps {
        if step.id == stepID { break }
        sum += step.weight
    }
    return sum / 100
}

/// Fraction (0...1) of total work completed when `part` (0...1) of the given step is done.
public func progressFraction(in stepID: String, part: Double) -> Double {
    let weight = buildSteps.first { $0.id == stepID }?.weight ?? 0
    return min(1, progressFraction(atStart: stepID) + weight * max(0, min(1, part)) / 100)
}
