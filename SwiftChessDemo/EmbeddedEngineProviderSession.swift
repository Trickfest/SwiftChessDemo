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

/// Narrow transport surface shared by the two embedded engine wrappers.
protocol EmbeddedEngineTransport: AnyObject, Sendable {
    nonisolated func sendCommand(_ command: String)
    nonisolated func stop()
}

/// Describes which startup handshake commands a concrete wrapper sends itself.
enum EmbeddedEngineStartupSequence: Equatable {
    /// The provider must send `uci`; the wrapper sends no readiness probe.
    case providerSendsUCI
    /// The wrapper sends `uci`, its startup options, and `isready` in order.
    case transportSendsUCIAndReady
}

typealias EmbeddedEngineTransportFactory = @MainActor (
    @escaping @Sendable (String) -> Void
) throws -> any EmbeddedEngineTransport

/// Serializes blocking teardown with a later engine start without blocking the main actor.
///
/// Both native wrappers join their worker thread from `stop()`. Registering the
/// teardown synchronously closes the race with a later provider while the work
/// itself runs away from the UI. A later start waits for the registered tail.
final class EmbeddedEngineLifecycleCoordinator: @unchecked Sendable {
    /// Both native wrappers temporarily own process-wide C++ standard streams.
    /// Their teardown/start boundary therefore has to be serialized across
    /// engine types, not merely across instances of one wrapper.
    static let shared = EmbeddedEngineLifecycleCoordinator()

    private let lock = NSLock()
    private var teardownTail: Task<Void, Never>?

    func enqueueTeardown(of transport: any EmbeddedEngineTransport) {
        lock.lock()
        let previousTeardown = teardownTail
        let teardown = Task.detached(priority: .utility) {
            await previousTeardown?.value
            transport.stop()
        }
        teardownTail = teardown
        lock.unlock()
    }

    func waitForPendingTeardown() async {
        await currentTeardown()?.value
    }

    private func currentTeardown() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return teardownTail
    }
}

/// Shared UCI lifecycle used by the Stockfish and Arasan provider facades.
///
/// The concrete wrappers only differ in construction and which startup commands
/// they send. Search serialization, handshake ordering, cancellation, timeouts,
/// stale-output rejection, and teardown coordination stay identical here.
@MainActor
final class EmbeddedEngineProviderSession: DemoEngineProvider {
    private enum State: Equatable {
        case idle
        case starting
        case waitingForUCI
        case waitingForStartupReady
        case waitingForSearchReady
        case ready
        case searching
    }

    let engineKind: DemoEngineKind

    private let startupSequence: EmbeddedEngineStartupSequence
    private let lifecycleCoordinator: EmbeddedEngineLifecycleCoordinator
    private let transportFactory: EmbeddedEngineTransportFactory
    private let eventHandler: DemoEngineEventHandler
    private let handshakeTimeout: Duration
    private let bestMoveAfterStopTimeout: Duration
    private let searchTimeoutOverride: Duration?

    private var state: State = .idle
    private var transport: (any EmbeddedEngineTransport)?
    private var activeRequest: EngineSearchRequest?
    private var queuedSearchRequest: EngineSearchRequest?
    private var isIgnoringActiveAnalysisOutput = false
    private var isWaitingForBestMoveAfterTimeout = false
    private var preparationNeedsRestart = false
    private var engineInstanceID = UUID()
    private var searchToken = UUID()
    private var startupTask: Task<Void, Never>?
    private var handshakeTimeoutTask: Task<Void, Never>?
    private var searchTimeoutTask: Task<Void, Never>?
    private var timeoutStopTask: Task<Void, Never>?

    init(
        engineKind: DemoEngineKind,
        startupSequence: EmbeddedEngineStartupSequence,
        lifecycleCoordinator: EmbeddedEngineLifecycleCoordinator,
        transportFactory: @escaping EmbeddedEngineTransportFactory,
        eventHandler: @escaping DemoEngineEventHandler,
        handshakeTimeout: Duration = .seconds(10),
        bestMoveAfterStopTimeout: Duration = .seconds(3),
        searchTimeoutOverride: Duration? = nil
    ) {
        self.engineKind = engineKind
        self.startupSequence = startupSequence
        self.lifecycleCoordinator = lifecycleCoordinator
        self.transportFactory = transportFactory
        self.eventHandler = eventHandler
        self.handshakeTimeout = handshakeTimeout
        self.bestMoveAfterStopTimeout = bestMoveAfterStopTimeout
        self.searchTimeoutOverride = searchTimeoutOverride
    }

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

        guard let currentRequest = activeRequest else {
            startSearch(request)
            return
        }

        if currentRequest.purpose.isAnalysis {
            cancelAnalysisSearch(queueReplacement: request)
        }
    }

    func cancelAnalysisSearch(queueReplacement: EngineSearchRequest?) {
        guard activeRequest?.purpose.isAnalysis == true else {
            if let queueReplacement {
                if activeRequest == nil {
                    startSearch(queueReplacement)
                } else {
                    queuedSearchRequest = queueReplacement
                }
            }
            return
        }

        switch state {
        case .searching:
            queuedSearchRequest = queueReplacement
            isIgnoringActiveAnalysisOutput = true
            transport?.sendCommand(UCICommand.stop.string)

        case .waitingForSearchReady:
            activeRequest = queueReplacement
            queuedSearchRequest = nil
            preparationNeedsRestart = queueReplacement != nil

        case .starting, .waitingForUCI, .waitingForStartupReady:
            activeRequest = queueReplacement
            queuedSearchRequest = nil

        case .idle, .ready:
            activeRequest = nil
            queuedSearchRequest = nil
            if let queueReplacement {
                startSearch(queueReplacement)
            }
        }
    }

    func stop() {
        searchToken = UUID()
        engineInstanceID = UUID()
        activeRequest = nil
        queuedSearchRequest = nil
        isIgnoringActiveAnalysisOutput = false
        isWaitingForBestMoveAfterTimeout = false
        preparationNeedsRestart = false
        state = .idle

        startupTask?.cancel()
        startupTask = nil
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        searchTimeoutTask?.cancel()
        searchTimeoutTask = nil
        timeoutStopTask?.cancel()
        timeoutStopTask = nil

        discardTransport()
    }

    private func startSearch(_ request: EngineSearchRequest) {
        guard request.engineKind == engineKind else { return }

        activeRequest = request
        queuedSearchRequest = nil
        isIgnoringActiveAnalysisOutput = false
        isWaitingForBestMoveAfterTimeout = false
        preparationNeedsRestart = false
        searchToken = UUID()
        searchTimeoutTask?.cancel()
        timeoutStopTask?.cancel()

        switch state {
        case .idle:
            startTransport()
        case .ready:
            beginSearchPreparation()
        case .waitingForSearchReady:
            preparationNeedsRestart = true
        case .starting, .waitingForUCI, .waitingForStartupReady, .searching:
            break
        }
    }

    private func startTransport() {
        guard transport == nil, startupTask == nil, activeRequest != nil else { return }

        let engineInstanceID = UUID()
        self.engineInstanceID = engineInstanceID
        state = .starting

        startupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await lifecycleCoordinator.waitForPendingTeardown()

            guard !Task.isCancelled,
                  self.engineInstanceID == engineInstanceID,
                  self.activeRequest != nil
            else {
                if self.engineInstanceID == engineInstanceID {
                    self.startupTask = nil
                    self.state = .idle
                }
                return
            }

            let parser = UCIParser()
            do {
                let transport = try transportFactory { [weak self] line in
                    let parsedLine = parser.parse(line)

                    // Both wrappers deliver lines on one serial queue. Submitting
                    // every parsed line to the main queue preserves that FIFO
                    // order while keeping UI state main-actor isolated.
                    DispatchQueue.main.async { [weak self] in
                        self?.receiveParsedLine(parsedLine, engineInstanceID: engineInstanceID)
                    }
                }

                guard !Task.isCancelled,
                      self.engineInstanceID == engineInstanceID,
                      self.activeRequest != nil
                else {
                    lifecycleCoordinator.enqueueTeardown(of: transport)
                    if self.engineInstanceID == engineInstanceID {
                        self.startupTask = nil
                        self.state = .idle
                    }
                    return
                }

                self.transport = transport
                self.startupTask = nil
                self.state = .waitingForUCI
                self.startHandshakeTimeout(engineInstanceID: engineInstanceID)

                if startupSequence == .providerSendsUCI {
                    transport.sendCommand(UCICommand.uci.string)
                }
            } catch {
                self.startupTask = nil
                self.state = .idle
                self.reportStartupFailure(error.localizedDescription)
            }
        }
    }

    private func receiveParsedLine(_ output: UCIParsedLine, engineInstanceID: UUID) {
        guard engineInstanceID == self.engineInstanceID else { return }

        switch state {
        case .waitingForUCI:
            guard case .uciOK = output else {
                reportOutputIfActive(output)
                return
            }

            reportOutputIfActive(output)
            if startupSequence == .transportSendsUCIAndReady {
                state = .waitingForStartupReady
            } else {
                beginSearchPreparationOrBecomeReady()
            }

        case .waitingForStartupReady:
            guard case .readyOK = output else {
                reportOutputIfActive(output)
                return
            }

            reportOutputIfActive(output)
            beginSearchPreparationOrBecomeReady()

        case .waitingForSearchReady:
            guard case .readyOK = output else {
                reportOutputIfActive(output)
                return
            }

            reportOutputIfActive(output)
            if preparationNeedsRestart {
                preparationNeedsRestart = false
                beginSearchPreparationOrBecomeReady()
            } else if activeRequest != nil {
                beginSearchCommands()
            } else {
                becomeReady()
            }

        case .searching:
            receiveSearchOutput(output)

        case .idle, .starting, .ready:
            break
        }
    }

    private func reportOutputIfActive(_ output: UCIParsedLine) {
        guard let request = activeRequest else { return }
        eventHandler(.output(output, request: request))
    }

    private func beginSearchPreparationOrBecomeReady() {
        if activeRequest == nil {
            becomeReady()
        } else {
            beginSearchPreparation()
        }
    }

    private func beginSearchPreparation() {
        guard let request = activeRequest, let transport else {
            becomeReady()
            return
        }

        state = .waitingForSearchReady
        preparationNeedsRestart = false
        startHandshakeTimeout(engineInstanceID: engineInstanceID)
        transport.sendCommand(UCICommand.setOption(name: "MultiPV", value: request.multiPVCount).string)
        transport.sendCommand(UCICommand.newGame.string)
        transport.sendCommand(UCICommand.isReady.string)
    }

    private func beginSearchCommands() {
        guard let request = activeRequest, let transport else {
            becomeReady()
            return
        }

        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        state = .searching
        transport.sendCommand(UCICommand.position(.fen(request.fen)).string)
        transport.sendCommand(UCICommand.go(.moveTime(milliseconds: request.moveTimeMilliseconds)).string)
        startSearchTimeout(token: searchToken)
    }

    private func becomeReady() {
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        state = transport == nil ? .idle : .ready
    }

    private func receiveSearchOutput(_ output: UCIParsedLine) {
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

    private func startHandshakeTimeout(engineInstanceID: UUID) {
        handshakeTimeoutTask?.cancel()
        let timeout = handshakeTimeout
        handshakeTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }

            self?.handleHandshakeTimeout(engineInstanceID: engineInstanceID)
        }
    }

    private func handleHandshakeTimeout(engineInstanceID: UUID) {
        guard engineInstanceID == self.engineInstanceID,
              state == .waitingForUCI
                || state == .waitingForStartupReady
                || state == .waitingForSearchReady
        else {
            return
        }

        let request = activeRequest
        let queuedRequest = finishCurrentSearch()
        discardTransport()

        if let request {
            eventHandler(.failure(message: "Timed out waiting for engine readiness.", request: request))
        }
        startQueuedSearchIfStillIdle(queuedRequest)
    }

    private func startSearchTimeout(token: UUID) {
        let timeoutSeconds = activeRequest?.safetyTimeoutSeconds
            ?? EngineSearchRequest.defaultSafetyTimeoutSeconds(
                for: EngineMoveTime.defaultValue.rawValue
            )
        let timeout = searchTimeoutOverride ?? .seconds(timeoutSeconds)

        searchTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }

            self?.handleSearchTimeout(token: token)
        }
    }

    private func handleSearchTimeout(token: UUID) {
        guard token == searchToken, let request = activeRequest, state == .searching else { return }
        searchTimeoutTask?.cancel()
        searchTimeoutTask = nil
        isWaitingForBestMoveAfterTimeout = true
        eventHandler(.timeout(request))
        transport?.sendCommand(UCICommand.stop.string)
        startBestMoveAfterStopTimeout(token: token)
    }

    private func startBestMoveAfterStopTimeout(token: UUID) {
        let timeout = bestMoveAfterStopTimeout
        timeoutStopTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: timeout)
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
        discardTransport()
        eventHandler(.timeoutWithoutBestMove(request))
        startQueuedSearchIfStillIdle(queuedRequest)
    }

    private func reportStartupFailure(_ message: String) {
        guard let request = activeRequest else { return }
        let queuedRequest = finishCurrentSearch()
        eventHandler(.failure(message: message, request: request))
        startQueuedSearchIfStillIdle(queuedRequest)
    }

    private func finishCurrentSearch() -> EngineSearchRequest? {
        activeRequest = nil
        isIgnoringActiveAnalysisOutput = false
        isWaitingForBestMoveAfterTimeout = false
        preparationNeedsRestart = false
        searchToken = UUID()
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        searchTimeoutTask?.cancel()
        searchTimeoutTask = nil
        timeoutStopTask?.cancel()
        timeoutStopTask = nil
        state = transport == nil ? .idle : .ready

        let request = queuedSearchRequest
        queuedSearchRequest = nil
        return request
    }

    private func discardTransport() {
        guard let transport else { return }
        self.transport = nil
        state = .idle
        engineInstanceID = UUID()
        lifecycleCoordinator.enqueueTeardown(of: transport)
    }

    private func startQueuedSearchIfStillIdle(_ request: EngineSearchRequest?) {
        guard let request, activeRequest == nil else { return }
        startSearch(request)
    }
}
