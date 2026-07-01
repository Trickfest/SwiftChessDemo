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
    static let defaultTimeoutSeconds = 30

    let engineKind: DemoEngineKind
    let purpose: EngineSearchPurpose
    let fen: String
    let sideToMove: PieceColor
    let depth: Int
    let multiPVCount: Int
    let timeoutSeconds: Int

    init(
        engineKind: DemoEngineKind,
        purpose: EngineSearchPurpose,
        fen: String,
        sideToMove: PieceColor,
        depth: Int,
        multiPVCount: Int,
        timeoutSeconds: Int = defaultTimeoutSeconds
    ) {
        self.engineKind = engineKind
        self.purpose = purpose
        self.fen = fen
        self.sideToMove = sideToMove
        self.depth = depth
        self.multiPVCount = multiPVCount
        self.timeoutSeconds = max(1, timeoutSeconds)
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
