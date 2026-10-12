// SPDX-License-Identifier: GPL-3.0-only
// The murmur keyboard, a dictation pad (ios/prd.json IOS-008): tap the
// pill to start a take and again to stop it. The keyboard only asks the
// app for a take under its own id, signals it (start, stop, cancel), and
// reads the mailbox; it never touches the microphone or the network.
// Words land at the cursor once, or wait as Insert last when you left the
// field before they arrived.
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let pad = PadView()
    private var listener: SignalListener?
    /// The take this keyboard asked for, until it ends.
    private var mine: UUID?
    /// The phase of that take, as the mailbox last said.
    private var phase: MailboxEntry.Phase?
    /// The field the take began in.
    private var field: UUID?
    private var visible = false
    private var deleteRepeat: Timer?
    private var noAnswer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        pad.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pad)
        let height = view.heightAnchor.constraint(equalToConstant: 236)
        height.priority = .defaultHigh
        NSLayoutConstraint.activate([
            height,
            pad.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pad.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pad.topAnchor.constraint(equalTo: view.topAnchor),
            pad.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        pad.globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        pad.pill.addTarget(self, action: #selector(tapPill), for: .touchUpInside)
        pad.space.addTarget(self, action: #selector(tapSpace), for: .touchUpInside)
        pad.returnKey.addTarget(self, action: #selector(tapReturn), for: .touchUpInside)
        pad.insertLast.addTarget(self, action: #selector(tapInsertLast), for: .touchUpInside)
        pad.delete.addTarget(self, action: #selector(deleteDown), for: .touchDown)
        pad.delete.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        listener = SignalListener([.changed, .busy]) { [weak self] signal in
            signal == .busy ? self?.heardBusy() : self?.refresh()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        visible = true
        pad.setFullAccess(hasFullAccess)
        refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        visible = false
        // A take still starting or listening when the keyboard goes away is
        // dropped; one already being transcribed comes back as Insert last.
        if mine != nil, phase == nil || phase == .listening {
            Signal.cancel.post()
            end(nil)
        }
        deleteUp()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        pad.globe.isHidden = !needsInputModeSwitchKey
        setReturnTitle()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        setReturnTitle()
    }

    @objc private func tapPill() {
        switch (mine, phase) {
        case (.some, .listening?):
            Signal.stop.post()
            // The app moves on to working within a moment; when it does not,
            // it is no longer there.
            expectAnswer(within: 4, else: Pad.stoppedAnswering)
        case (.some, _):
            // This keyboard's take is still starting or being transcribed.
            break
        case (nil, _):
            let take = UUID()
            guard let mailbox = Mailbox.shared else { return }
            mailbox.ask(take)
            mine = take
            phase = nil
            field = textDocumentProxy.documentIdentifier
            pad.insertLast.isHidden = true
            pad.status.text = "Starting"
            Signal.start.post()
            // The app answers within a moment when it is open.
            expectAnswer(within: 2, else: Pad.noAnswer)
        }
    }

    /// Ends the take with a line when the mailbox has not moved on in time.
    private func expectAnswer(within seconds: TimeInterval, else line: String) {
        let waitingOn = phase
        noAnswer?.invalidate()
        noAnswer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.mine != nil, self.phase == waitingOn else { return }
                Signal.cancel.post()
                self.end(line)
            }
        }
    }

    private func heardBusy() {
        guard mine != nil, phase == nil else { return }
        noAnswer?.invalidate()
        end(Pad.busy)
    }

    @objc private func tapInsertLast() {
        if let words = Mailbox.shared?.claim() { insert(words) }
        pad.insertLast.isHidden = true
    }

    @objc private func tapSpace() { textDocumentProxy.insertText(" ") }
    @objc private func tapReturn() { textDocumentProxy.insertText("\n") }

    /// Delete repeats while held, after a short pause.
    @objc private func deleteDown() {
        textDocumentProxy.deleteBackward()
        deleteRepeat?.invalidate()
        deleteRepeat = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.deleteRepeat = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.textDocumentProxy.deleteBackward() }
                }
            }
        }
    }

    @objc private func deleteUp() {
        deleteRepeat?.invalidate()
        deleteRepeat = nil
    }

    private func setReturnTitle() {
        let title = Pad.returnTitle(textDocumentProxy.returnKeyType ?? .default)
        guard pad.returnKey.configuration?.title != title else { return }
        var look = pad.returnKey.configuration
        look?.title = title
        pad.returnKey.configuration = look
        pad.returnKey.accessibilityLabel = title
    }

    /// Reads the mailbox and does what the newest entry asks, only while
    /// this keyboard is on screen.
    private func refresh() {
        guard visible, hasFullAccess, let mailbox = Mailbox.shared else { return }
        let entry = mailbox.read()
        if let entry, entry.take == mine, entry.phase != phase {
            phase = entry.phase
            noAnswer?.invalidate()
            // Transcribing and polish can take a while, but not forever.
            if phase == .working { expectAnswer(within: 90, else: Pad.stoppedAnswering) }
        }
        pad.setListening(mine != nil && phase == .listening)
        switch Pad.react(to: entry, mine: mine, sameField: textDocumentProxy.documentIdentifier == field, visible: visible) {
        case .insert(let take):
            if let words = mailbox.claim(take) { insert(words) }
            end(nil)
        case .offerInsertLast:
            pad.insertLast.isHidden = false
            if entry?.take == mine { end(nil) }
        case .status(let line):
            pad.status.text = line
            if phase == .nothing || phase == .failed { end(line) }
        case .none:
            break
        }
    }

    private func insert(_ words: String) {
        textDocumentProxy.insertText(Pad.spaced(words, after: textDocumentProxy.documentContextBeforeInput))
    }

    private func end(_ line: String?) {
        mine = nil
        phase = nil
        pad.setListening(false)
        pad.status.text = line
    }
}
