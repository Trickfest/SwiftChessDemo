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
import MaiaUCI
import MaiaEmbedded

/// Maia owns its state and never redirects the process's C++ streams.
private final class MaiaEngineTransport: EmbeddedEngineTransport, @unchecked Sendable {
    private let engine: MaiaEngine
    init(lineHandler: @escaping @Sendable (String) -> Void) throws {
        guard let url = Bundle.main.url(forResource: "maia3-79m", withExtension: "onnx") else {
            throw CocoaError(.fileNoSuchFile)
        }
        engine = MaiaEngine(configuration: .init(model: .init(modelURL: url)), lineHandler: lineHandler)
        try engine.start()
    }
    nonisolated func sendCommand(_ command: String) { engine.sendCommand(command) }
    nonisolated func stop() { engine.stop() }
    nonisolated func shutdown() async { await engine.shutdown() }
}

/// Uses the same request, timeout and stale-event policy as the other engines.
@MainActor
final class MaiaMoveProvider: DemoEngineProvider {
    private let session: EmbeddedEngineProviderSession
    init(eventHandler: @escaping DemoEngineEventHandler) {
        session = EmbeddedEngineProviderSession(
            engineKind: .maia, startupSequence: .providerSendsUCI,
            lifecycleCoordinator: .shared,
            transportFactory: { try MaiaEngineTransport(lineHandler: $0) },
            eventHandler: eventHandler)
    }
    let engineKind: DemoEngineKind = .maia
    var activePurpose: EngineSearchPurpose? { session.activePurpose }
    var activeFEN: String? { session.activeFEN }
    var isBusy: Bool { session.isBusy }
    func startOrQueueSearch(_ request: EngineSearchRequest) { session.startOrQueueSearch(request) }
    func cancelAnalysisSearch(queueReplacement: EngineSearchRequest?) {
        session.cancelAnalysisSearch(queueReplacement: queueReplacement)
    }
    func stop() { session.stop() }
}
