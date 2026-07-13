//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and embedded engines.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the MIT License.
// You may obtain a copy of the License in the LICENSE file
// See the LICENSE file for more information.
//

import ChessUCI

/// Stockfish transport adapter used by the shared provider session.
private final class StockfishEngineTransport: EmbeddedEngineTransport, @unchecked Sendable {
    private let engine: SFEngine

    init(lineHandler: @escaping @Sendable (String) -> Void) {
        engine = SFEngine(lineHandler: lineHandler)
        engine.start()
    }

    nonisolated func sendCommand(_ command: String) {
        engine.sendCommand(command)
    }

    nonisolated func stop() {
        engine.stop()
    }
}

/// Owns Stockfish through the app's shared embedded-engine UCI lifecycle.
@MainActor
final class StockfishMoveProvider: DemoEngineProvider {
    private let session: EmbeddedEngineProviderSession

    init(eventHandler: @escaping DemoEngineEventHandler) {
        session = EmbeddedEngineProviderSession(
            engineKind: .stockfish,
            startupSequence: .providerSendsUCI,
            lifecycleCoordinator: .shared,
            transportFactory: { StockfishEngineTransport(lineHandler: $0) },
            eventHandler: eventHandler
        )
    }

    let engineKind: DemoEngineKind = .stockfish
    var activePurpose: EngineSearchPurpose? { session.activePurpose }
    var activeFEN: String? { session.activeFEN }
    var isBusy: Bool { session.isBusy }

    func startOrQueueSearch(_ request: EngineSearchRequest) {
        session.startOrQueueSearch(request)
    }

    func cancelAnalysisSearch(queueReplacement: EngineSearchRequest?) {
        session.cancelAnalysisSearch(queueReplacement: queueReplacement)
    }

    func stop() {
        session.stop()
    }

    /// Returns the app-side safety timeout for a search request.
    static func safetyTimeoutSeconds(for request: EngineSearchRequest?) -> Int {
        request?.safetyTimeoutSeconds
            ?? EngineSearchRequest.defaultSafetyTimeoutSeconds(
                for: EngineMoveTime.defaultValue.rawValue
            )
    }
}
