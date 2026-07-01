//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and StockfishEmbedded.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the MIT License.
// You may obtain a copy of the License in the LICENSE file
// See the LICENSE file for more information.
//

import Foundation
import ChessUCI

/// Owns the embedded Stockfish process and UCI search lifecycle.
///
/// The game view model decides what engine output means for the app. This
/// provider only serializes searches, sends UCI commands, parses engine lines,
/// suppresses cancelled analysis output, and reports typed events.
@MainActor
final class StockfishMoveProvider: DemoEngineProvider {
    private let eventHandler: DemoEngineEventHandler
    private var engine: SFEngine?
    private var activeRequest: EngineSearchRequest?
    private var queuedSearchRequest: EngineSearchRequest?
    private var isIgnoringActiveAnalysisOutput = false
    private var isWaitingForBestMoveAfterTimeout = false
    private var engineInstanceID = UUID()
    private var searchToken = UUID()
    private var timeoutTask: Task<Void, Never>?
    private var timeoutStopTask: Task<Void, Never>?

    init(eventHandler: @escaping DemoEngineEventHandler) {
        self.eventHandler = eventHandler
    }

    let engineKind: DemoEngineKind = .stockfish

    var activePurpose: EngineSearchPurpose? {
        activeRequest?.purpose
    }

    var activeFEN: String? {
        activeRequest?.fen
    }

    var isBusy: Bool {
        activeRequest != nil
    }

    func startOrQueueSearch(_ request: EngineSearchRequest) {
        guard request.engineKind == engineKind else { return }

        guard let activeRequest else {
            startSearch(request)
            return
        }

        if activeRequest.purpose.isAnalysis {
            cancelAnalysisSearch(queueReplacement: request)
        }
    }

    func cancelAnalysisSearch(queueReplacement: EngineSearchRequest?) {
        if activeRequest?.purpose.isAnalysis == true {
            queuedSearchRequest = queueReplacement
            isIgnoringActiveAnalysisOutput = true
            engine?.sendCommand(UCICommand.stop.string)
        } else if let queueReplacement {
            if activeRequest == nil {
                startSearch(queueReplacement)
            } else {
                queuedSearchRequest = queueReplacement
            }
        }
    }

    func stop() {
        searchToken = UUID()
        activeRequest = nil
        queuedSearchRequest = nil
        isIgnoringActiveAnalysisOutput = false
        isWaitingForBestMoveAfterTimeout = false
        engineInstanceID = UUID()
        timeoutTask?.cancel()
        timeoutTask = nil
        timeoutStopTask?.cancel()
        timeoutStopTask = nil

        let engine = engine
        self.engine = nil
        engine?.stop()
    }

    private func startSearch(_ request: EngineSearchRequest) {
        guard request.engineKind == engineKind else { return }
        guard let engine = ensureEngineStarted() else { return }

        activeRequest = request
        queuedSearchRequest = nil
        isIgnoringActiveAnalysisOutput = false
        isWaitingForBestMoveAfterTimeout = false
        searchToken = UUID()
        timeoutTask?.cancel()
        timeoutStopTask?.cancel()

        engine.sendCommand(UCICommand.setOption(name: "MultiPV", value: request.multiPVCount).string)
        engine.sendCommand(UCICommand.isReady.string)
        engine.sendCommand(UCICommand.newGame.string)
        engine.sendCommand(UCICommand.position(.fen(request.fen)).string)
        engine.sendCommand(UCICommand.go(.moveTime(milliseconds: request.moveTimeMilliseconds)).string)

        startTimeout(token: searchToken)
    }

    private func ensureEngineStarted() -> SFEngine? {
        if let engine {
            return engine
        }

        let parser = UCIParser()
        let engineInstanceID = UUID()
        self.engineInstanceID = engineInstanceID
        let engine = SFEngine(lineHandler: { [weak self] line in
            let parsedLine = parser.parse(line)
            Task { @MainActor [weak self] in
                self?.receiveParsedLine(parsedLine, engineInstanceID: engineInstanceID)
            }
        })

        self.engine = engine
        engine.start()
        engine.sendCommand(UCICommand.uci.string)
        return engine
    }

    private func receiveParsedLine(_ output: UCIParsedLine, engineInstanceID: UUID) {
        guard engineInstanceID == self.engineInstanceID else { return }
        guard let request = activeRequest else { return }

        if isIgnoringActiveAnalysisOutput, request.purpose.isAnalysis {
            if case .bestMove = output {
                startQueuedSearchIfStillIdle(finishCurrentSearch())
            }
            return
        }

        if case .bestMove = output {
            let queuedRequest = finishCurrentSearch()
            eventHandler(.output(output, request: request))
            startQueuedSearchIfStillIdle(queuedRequest)
            return
        }

        eventHandler(.output(output, request: request))
    }

    private func startTimeout(token: UUID) {
        let timeoutSeconds = Self.safetyTimeoutSeconds(for: activeRequest)
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(timeoutSeconds))
            } catch {
                return
            }

            self?.handleTimeout(token: token)
        }
    }

    /// Returns the app-side safety timeout for a search request.
    static func safetyTimeoutSeconds(for request: EngineSearchRequest?) -> Int {
        request?.safetyTimeoutSeconds
            ?? EngineSearchRequest.defaultSafetyTimeoutSeconds(
                for: EngineMoveTime.defaultValue.rawValue
            )
    }

    private func handleTimeout(token: UUID) {
        guard token == searchToken, let request = activeRequest else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        isWaitingForBestMoveAfterTimeout = true
        eventHandler(.timeout(request))
        engine?.sendCommand(UCICommand.stop.string)
        startBestMoveAfterStopTimeout(token: token)
    }

    private func startBestMoveAfterStopTimeout(token: UUID) {
        timeoutStopTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }

            self?.handleBestMoveAfterStopTimeout(token: token)
        }
    }

    private func handleBestMoveAfterStopTimeout(token: UUID) {
        guard token == searchToken,
              let request = activeRequest,
              isWaitingForBestMoveAfterTimeout
        else {
            return
        }

        let queuedRequest = finishCurrentSearch()
        discardEngineAfterUnresponsiveSearch()
        eventHandler(.timeoutWithoutBestMove(request))
        startQueuedSearchIfStillIdle(queuedRequest)
    }

    private func finishCurrentSearch() -> EngineSearchRequest? {
        activeRequest = nil
        isIgnoringActiveAnalysisOutput = false
        isWaitingForBestMoveAfterTimeout = false
        searchToken = UUID()
        timeoutTask?.cancel()
        timeoutTask = nil
        timeoutStopTask?.cancel()
        timeoutStopTask = nil

        let request = queuedSearchRequest
        queuedSearchRequest = nil
        return request
    }

    private func discardEngineAfterUnresponsiveSearch() {
        let engine = engine
        self.engine = nil
        engineInstanceID = UUID()

        engine?.stop()
    }

    private func startQueuedSearchIfStillIdle(_ request: EngineSearchRequest?) {
        guard let request, activeRequest == nil else { return }
        startSearch(request)
    }
}
