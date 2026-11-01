import Foundation

/// The build steps tools/builder_cli.py announces, in order, with their share of the work
/// (they add up to 100). Measured on an M1 Pro, European build: lift 52 s, compile 57 s,
/// link 10 s, the launcher (swiftc, only the first time in a workspace) 60 s; unpacking two
/// discs about 5 s.
public let buildSteps: [(id: String, weight: Double)] = [
    ("prepare", 3), ("lift", 29), ("compile", 32), ("link", 6), ("package", 29), ("sign", 1),
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
