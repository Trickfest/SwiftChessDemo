import Foundation

/// Marks the Objective-C engine wrapper as Sendable for Swift concurrency.
///
/// The engine is internally synchronized; we avoid copying it across tasks,
/// but this conformance allows safe storage in Swift async contexts.
extension SFEngine: @unchecked Sendable {}
