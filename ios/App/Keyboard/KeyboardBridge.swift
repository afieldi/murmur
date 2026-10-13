// SPDX-License-Identifier: GPL-3.0-only
// The app's side of the keyboard (ios/prd.json IOS-008): it hears the
// keyboard's start, stop, and cancel, runs the take on the app's one take
// model under the id the keyboard asked with, and tells the keyboard how
// it goes through the mailbox. Only a take the keyboard started goes to
// the mailbox, so a take made on the Dictate screen never turns up in
// another app.
import Foundation
import Observation

@MainActor final class KeyboardBridge {
    /// How long a keyboard's ask stays good. One that waited longer, sent
    /// while murmur was not running, is dropped.
    static let askLife: TimeInterval = 3

    private let model: TakeModel
    private let mailbox: Mailbox
    private let announce: @MainActor (Signal) -> Void
    private var listener: SignalListener?
    /// The take the keyboard asked for, until it ends.
    private var take: UUID?
    /// A cancel heard while the take was still starting.
    private var cancelled = false
    private var startedAt = Date.distantPast

    init(model: TakeModel, mailbox: Mailbox, announce: @escaping @MainActor (Signal) -> Void = { $0.post() }) {
        self.model = model
        self.mailbox = mailbox
        self.announce = announce
    }

    /// Hears the keyboard from now on and follows the take model.
    func listen() {
        listener = SignalListener([.start, .stop, .cancel]) { [weak self] signal in
            self?.hear(signal)
        }
        follow()
    }

    func hear(_ signal: Signal) {
        switch signal {
        case .start:
            guard let id = mailbox.answer(within: Self.askLife) else { return }
            guard take == nil, !model.isRecording, !model.isBusy else {
                announce(.busy)
                return
            }
            take = id
            startedAt = .now
            cancelled = false
            // Written here, not read from the model, whose state may still
            // be the last take's words.
            write(.listening)
            Task { await settle(id) }
        case .stop:
            guard take != nil, model.isRecording else { return }
            Task { await model.stop() }
        case .cancel:
            guard take != nil else { return }
            if model.isRecording { model.cancel() } else { cancelled = true }
        case .changed, .busy, .end:
            break
        }
    }

    /// Settles how the start went. A start that did not record ends failed
    /// here: the model's state may not change at all (denied twice), and
    /// following it alone would leave the take open forever.
    private func settle(_ id: UUID) async {
        await model.start()
        guard take == id else { return }
        if cancelled {
            model.cancel()
            write(.nothing, ends: true)
        } else if !model.isRecording {
            write(.failed, ends: true)
        }
    }

    /// Publishes each change of the take model's state, for as long as the
    /// bridge lives.
    private func follow() {
        withObservationTracking {
            _ = model.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.publish()
                self?.follow()
            }
        }
    }

    private func publish() {
        guard take != nil else { return }
        switch model.state {
        case .recording: write(.listening)
        case .transcribing: write(.working)
        case .words(let text): write(.ready, words: text, ends: true)
        case .heardNothing: write(.nothing, ends: true)
        case .failed, .micOff, .micFailed: write(.failed, ends: true)
        // Idle again after the take began: it was cancelled.
        case .idle: write(.nothing, ends: true)
        }
    }

    private func write(_ phase: MailboxEntry.Phase, words: String? = nil, ends: Bool = false) {
        guard let take else { return }
        mailbox.write(MailboxEntry(take: take, phase: phase, words: words, at: startedAt))
        announce(.changed)
        if ends { self.take = nil }
    }
}

extension KeyboardBridge {
    private static var shared: KeyboardBridge?

    /// Starts the one bridge for the app's life, on the app's take model.
    static func startOnce() {
        guard shared == nil, let model = TakeModel.live(), let mailbox = Mailbox.shared else { return }
        let bridge = KeyboardBridge(model: model, mailbox: mailbox)
        bridge.listen()
        shared = bridge
    }
}
