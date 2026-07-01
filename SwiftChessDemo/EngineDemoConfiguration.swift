//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and embedded engines.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the MIT License.
// You may obtain a copy of the License in the LICENSE file
// See the LICENSE file for more information.
//

import Foundation
import ChessCore

/// Top-level game modes exposed by the setup screen.
enum DemoGameMode: String, CaseIterable, Identifiable, Sendable {
    case humanVsEngine
    case engineVsEngine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .humanVsEngine:
            return "Human vs Engine"
        case .engineVsEngine:
            return "Engine vs Engine"
        }
    }
}

/// Pacing used between automatically generated engine-vs-engine moves.
enum EngineDemoPacing: String, CaseIterable, Identifiable, Sendable {
    case fast
    case oneSecond
    case twoSeconds
    case fiveSeconds

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fast:
            return "Fast"
        case .oneSecond:
            return "1s"
        case .twoSeconds:
            return "2s"
        case .fiveSeconds:
            return "5s"
        }
    }

    var delay: TimeInterval {
        switch self {
        case .fast:
            return 0
        case .oneSecond:
            return 1
        case .twoSeconds:
            return 2
        case .fiveSeconds:
            return 5
        }
    }
}

/// App-side safety cutoff for one engine-vs-engine search.
enum EngineDemoSearchTimeout: Int, CaseIterable, Identifiable, Sendable {
    case fiveSeconds = 5
    case tenSeconds = 10
    case thirtySeconds = 30

    var id: Int { rawValue }

    var displayName: String {
        "\(rawValue)s"
    }
}

/// Engine and depth for one side in engine-vs-engine mode.
struct EngineDemoSideConfiguration: Equatable, Sendable {
    var engineKind: DemoEngineKind
    var depth: Int
}

/// Optional stress settings that randomize the engine and/or depth per move.
struct EngineDemoStressConfiguration: Equatable, Sendable {
    var isEnabled: Bool = false
    var randomizesEngineEachMove: Bool = false
    var randomizesDepthEachMove: Bool = false
    var minimumDepth: Int = 1
    var maximumDepth: Int = 8
    var seed: UInt64 = 20260630

    func normalized() -> EngineDemoStressConfiguration {
        var copy = self
        copy.minimumDepth = EngineDemoConfiguration.clampedDepth(copy.minimumDepth)
        copy.maximumDepth = EngineDemoConfiguration.clampedDepth(copy.maximumDepth)
        if copy.minimumDepth > copy.maximumDepth {
            copy.maximumDepth = copy.minimumDepth
        }
        return copy
    }
}

/// Configuration for engine-vs-engine demo mode.
struct EngineDemoConfiguration: Equatable, Sendable {
    var white: EngineDemoSideConfiguration
    var black: EngineDemoSideConfiguration
    var pacing: EngineDemoPacing = .oneSecond
    var searchTimeout: EngineDemoSearchTimeout = .thirtySeconds
    var stress: EngineDemoStressConfiguration = EngineDemoStressConfiguration()

    static let defaultDepth = 8
    static let minimumDepth = 1
    static let maximumDepth = 30

    static func defaultConfiguration(defaultDepth: Int = defaultDepth) -> EngineDemoConfiguration {
        let clampedDepth = clampedDepth(defaultDepth)
        return EngineDemoConfiguration(
            white: EngineDemoSideConfiguration(engineKind: .stockfish, depth: clampedDepth),
            black: EngineDemoSideConfiguration(engineKind: .arasan, depth: clampedDepth)
        )
    }

    static func clampedDepth(_ depth: Int) -> Int {
        min(maximumDepth, max(minimumDepth, depth))
    }

    func normalized() -> EngineDemoConfiguration {
        var copy = self
        copy.white.depth = Self.clampedDepth(copy.white.depth)
        copy.black.depth = Self.clampedDepth(copy.black.depth)
        copy.stress = copy.stress.normalized()
        return copy
    }

    func sideConfiguration(for color: PieceColor) -> EngineDemoSideConfiguration {
        switch color {
        case .white:
            return white
        case .black:
            return black
        }
    }
}

/// Concrete engine/depth chosen for one engine-vs-engine move.
struct EngineDemoMoveConfiguration: Equatable, Sendable {
    let side: PieceColor
    let engineKind: DemoEngineKind
    let depth: Int
}

/// Playback state for engine-vs-engine demo mode.
enum EngineDemoRunState: Equatable, Sendable {
    case paused
    case playing
    case stepping
    case pausingAfterCurrentMove

    var isRunning: Bool {
        switch self {
        case .playing, .stepping, .pausingAfterCurrentMove:
            return true
        case .paused:
            return false
        }
    }
}

/// Tiny deterministic random generator for seeded stress tests.
struct SeededRandomGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x4d595df4d0f33173 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
