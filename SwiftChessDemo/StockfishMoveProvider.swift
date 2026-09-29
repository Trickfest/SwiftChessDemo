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
import Foundation
import SFEngine

/// Resolves the NNUE network that the app copies from its sibling
/// StockfishEmbedded checkout into the built app bundle.
enum StockfishNetworkResource {
    static var fileName: String { SFEngine.defaultNetworkFileName }

    static func bundledFileURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: fileName, withExtension: nil)
    }

    /// Returns the expected bundle path even when the resource is missing so
    /// SFEngine can report its normal nonfatal startup error through UCI.
    static func requiredFileURL(in bundle: Bundle = .main) -> URL {
        bundledFileURL(in: bundle)
            ?? bundle.bundleURL.appendingPathComponent(fileName)
    }
}

/// Stockfish transport adapter used by the shared provider session.
private final class StockfishEngineTransport: EmbeddedEngineSuspendableTransport, @unchecked Sendable {
    private let engine: SFEngine

    init(lineHandler: @escaping @Sendable (String) -> Void) {
        engine = SFEngine(
            networkFileURL: StockfishNetworkResource.requiredFileURL(),
            lineHandler: lineHandler
        )
        engine.start()
    }

    nonisolated func sendCommand(_ command: String) {
        engine.sendCommand(command)
    }

    nonisolated func stop() {
        engine.stop()
    }

    nonisolated func suspend() {
        engine.suspend()
    }

    nonisolated func resume() {
        engine.resume()
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

    func suspend() {
        session.suspend()
    }

    /// Returns the app-side safety timeout for a search request.
    static func safetyTimeoutSeconds(for request: EngineSearchRequest?) -> Int {
        request?.safetyTimeoutSeconds
            ?? EngineSearchRequest.defaultSafetyTimeoutSeconds(
                for: EngineMoveTime.defaultValue.rawValue
            )
    }
}
