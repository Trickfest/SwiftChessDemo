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
import ChessCore
import ChessUCI

/// Distinguishes engine searches that should apply a move from analysis
/// searches that only produce board arrows.
enum StockfishSearchPurpose: Equatable, Sendable {
    case opponentMove
    case suggestions
}

/// One Stockfish request against one board position.
struct StockfishSearchRequest: Equatable, Sendable {
    let purpose: StockfishSearchPurpose
    let fen: String
    let sideToMove: PieceColor
    let depth: Int
    let multiPVCount: Int
}

/// Typed output from the Stockfish provider.
enum StockfishMoveProviderEvent: Equatable, Sendable {
    case output(UCIParsedLine, request: StockfishSearchRequest)
    case timeout(StockfishSearchRequest)
    case timeoutWithoutBestMove(StockfishSearchRequest)
}

/// Owns the embedded Stockfish process and UCI search lifecycle.
///
/// The game view model decides what engine output means for the app. This
/// provider only serializes searches, sends UCI commands, parses engine lines,
/// suppresses cancelled suggestion output, and reports typed events.
@MainActor
final class StockfishMoveProvider {
    typealias EventHandler = @MainActor (StockfishMoveProviderEvent) -> Void

    private let eventHandler: EventHandler
    private var engine: SFEngine?
    private var activeRequest: StockfishSearchRequest?
    private var queuedSearchRequest: StockfishSearchRequest?
    private var isIgnoringActiveSuggestionOutput = false
    private var isWaitingForBestMoveAfterTimeout = false
    private var engineInstanceID = UUID()
    private var searchToken = UUID()
    private var timeoutTask: Task<Void, Never>?
    private var timeoutStopTask: Task<Void, Never>?

    init(eventHandler: @escaping EventHandler) {
        self.eventHandler = eventHandler
    }

    var activePurpose: StockfishSearchPurpose? {
        activeRequest?.purpose
    }

    var activeFEN: String? {
        activeRequest?.fen
    }

    func startOrQueueSearch(_ request: StockfishSearchRequest) {
        guard let activeRequest else {
            startSearch(request)
            return
        }

        if activeRequest.purpose == .suggestions {
            cancelSuggestionSearch(queueReplacement: request)
        }
    }

    func cancelSuggestionSearch(queueReplacement: StockfishSearchRequest?) {
        if activeRequest?.purpose == .suggestions {
            queuedSearchRequest = queueReplacement
            isIgnoringActiveSuggestionOutput = true
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
        isIgnoringActiveSuggestionOutput = false
        isWaitingForBestMoveAfterTimeout = false
        engineInstanceID = UUID()
        timeoutTask?.cancel()
        timeoutTask = nil
        timeoutStopTask?.cancel()
        timeoutStopTask = nil

        if let engine {
            DispatchQueue.global(qos: .userInitiated).async {
                engine.stop()
            }
        }
        engine = nil
    }

    private func startSearch(_ request: StockfishSearchRequest) {
        guard let engine = ensureEngineStarted() else { return }

        activeRequest = request
        queuedSearchRequest = nil
        isIgnoringActiveSuggestionOutput = false
        isWaitingForBestMoveAfterTimeout = false
        searchToken = UUID()
        timeoutTask?.cancel()
        timeoutStopTask?.cancel()

        engine.sendCommand(UCICommand.setOption(name: "MultiPV", value: request.multiPVCount).string)
        engine.sendCommand(UCICommand.isReady.string)
        engine.sendCommand(UCICommand.newGame.string)
        engine.sendCommand(UCICommand.position(.fen(request.fen)).string)
        engine.sendCommand(UCICommand.go(.depth(request.depth)).string)

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
            Task { @MainActor in
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

        if isIgnoringActiveSuggestionOutput, request.purpose == .suggestions {
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
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                return
            }

            self?.handleTimeout(token: token)
        }
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

    private func finishCurrentSearch() -> StockfishSearchRequest? {
        activeRequest = nil
        isIgnoringActiveSuggestionOutput = false
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

        if let engine {
            DispatchQueue.global(qos: .userInitiated).async {
                engine.stop()
            }
        }
    }

    private func startQueuedSearchIfStillIdle(_ request: StockfishSearchRequest?) {
        guard let request, activeRequest == nil else { return }
        startSearch(request)
    }
}
