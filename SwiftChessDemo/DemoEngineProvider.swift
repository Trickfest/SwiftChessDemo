//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and embedded engines.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the MIT License.
// You may obtain a copy of the License in the LICENSE file
// See the LICENSE file for more information.
//

import ChessCore
import ChessUCI

/// Shared event callback signature used by embedded engine providers.
typealias DemoEngineEventHandler = @MainActor (EngineProviderEvent) -> Void

/// Embedded engines exposed by the demo game screen.
enum DemoEngineKind: String, CaseIterable, Hashable, Identifiable, Sendable {
    case stockfish
    case arasan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stockfish:
            return "Stockfish"
        case .arasan:
            return "Arasan"
        }
    }
}

/// Move-time values exposed by the demo for live engine searches.
enum EngineMoveTime: Int, CaseIterable, Identifiable, Sendable {
    case quarterSecond = 250
    case halfSecond = 500
    case oneSecond = 1_000
    case twoSeconds = 2_000
    case fiveSeconds = 5_000
    case tenSeconds = 10_000

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .quarterSecond:
            return "250ms"
        case .halfSecond:
            return "500ms"
        case .oneSecond:
            return "1s"
        case .twoSeconds:
            return "2s"
        case .fiveSeconds:
            return "5s"
        case .tenSeconds:
            return "10s"
        }
    }

    static let defaultValue: EngineMoveTime = .oneSecond

    static func closest(milliseconds: Int) -> EngineMoveTime {
        let clampedMilliseconds = max(1, milliseconds)
        return allCases.min { lhs, rhs in
            abs(lhs.rawValue - clampedMilliseconds) < abs(rhs.rawValue - clampedMilliseconds)
        } ?? defaultValue
    }
}

/// Distinguishes searches that apply a move from analysis searches that update
/// display-only UI such as evaluation and suggestion arrows.
enum EngineSearchPurpose: Equatable, Sendable {
    case opponentMove
    case suggestions
    case evaluation

    var isAnalysis: Bool {
        switch self {
        case .suggestions, .evaluation:
            return true
        case .opponentMove:
            return false
        }
    }
}

/// One engine request against one board position.
struct EngineSearchRequest: Equatable, Sendable {
    static let safetyTimeoutGraceSeconds = 3

    let engineKind: DemoEngineKind
    let purpose: EngineSearchPurpose
    let fen: String
    let sideToMove: PieceColor
    let moveTimeMilliseconds: Int
    let multiPVCount: Int
    let safetyTimeoutSeconds: Int

    init(
        engineKind: DemoEngineKind,
        purpose: EngineSearchPurpose,
        fen: String,
        sideToMove: PieceColor,
        moveTimeMilliseconds: Int,
        multiPVCount: Int,
        safetyTimeoutSeconds: Int? = nil
    ) {
        self.engineKind = engineKind
        self.purpose = purpose
        self.fen = fen
        self.sideToMove = sideToMove
        self.moveTimeMilliseconds = max(1, moveTimeMilliseconds)
        self.multiPVCount = multiPVCount
        self.safetyTimeoutSeconds = max(
            1,
            safetyTimeoutSeconds ?? Self.defaultSafetyTimeoutSeconds(for: self.moveTimeMilliseconds)
        )
    }

    static func defaultSafetyTimeoutSeconds(for moveTimeMilliseconds: Int) -> Int {
        ((max(1, moveTimeMilliseconds) + 999) / 1_000) + safetyTimeoutGraceSeconds
    }
}

/// Typed output from a live engine provider.
enum EngineProviderEvent: Equatable, Sendable {
    case output(UCIParsedLine, request: EngineSearchRequest)
    case timeout(EngineSearchRequest)
    case timeoutWithoutBestMove(EngineSearchRequest)
    case failure(message: String, request: EngineSearchRequest)
}

/// App-local abstraction for an embedded UCI engine used by the demo.
@MainActor
protocol DemoEngineProvider: AnyObject {
    var engineKind: DemoEngineKind { get }
    var activePurpose: EngineSearchPurpose? { get }
    var activeFEN: String? { get }
    var isBusy: Bool { get }

    func startOrQueueSearch(_ request: EngineSearchRequest)
    func cancelAnalysisSearch(queueReplacement: EngineSearchRequest?)
    func stop()
}
