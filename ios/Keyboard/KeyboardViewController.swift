// SPDX-License-Identifier: GPL-3.0-only
// The murmur keyboard, a dictation pad (ios/prd.json IOS-008): tap the
// pill to start a take and again to stop it. The keyboard only signals the
// app (start, stop, cancel) and reads the mailbox; it never touches the
// microphone or the network. Words land at the cursor once, or wait as
// Insert last when you left the field before they arrived.
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let pad = PadView()
    private var listener: SignalListener?
    /// When this keyboard asked for a take, until it ends.
    private var startedAt: Date?
    /// The field the take began in.
    private var field: UUID?
    private var listening = false
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
        listener = SignalListener([.changed]) { [weak self] _ in self?.refresh() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pad.setFullAccess(hasFullAccess)
        refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // A take still listening when the keyboard goes away is dropped.
        if listening { Signal.cancel.post() }
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
        if listening {
            Signal.stop.post()
            return
        }
        startedAt = .now
        field = textDocumentProxy.documentIdentifier
        pad.insertLast.isHidden = true
        pad.status.text = "Starting"
        Signal.start.post()
        // The app answers within a moment when it is open; when it is not,
        // say how to start.
        noAnswer?.invalidate()
        noAnswer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.answerMissing() }
        }
    }

    private func answerMissing() {
        guard startedAt != nil, !listening else { return }
        startedAt = nil
        pad.status.text = "Open murmur, then tap the pill again."
    }

    @objc private func tapInsertLast() {
        guard let words = Mailbox.shared?.claim() else { return }
        insert(words)
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
        var look = pad.returnKey.configuration
        look?.title = title
        pad.returnKey.configuration = look
        pad.returnKey.accessibilityLabel = title
    }

    /// Reads the mailbox and does what the newest entry asks.
    private func refresh() {
        guard hasFullAccess, let mailbox = Mailbox.shared else { return }
        let entry = mailbox.read()
        let ours = startedAt.map { start in entry.map { $0.at >= start.addingTimeInterval(-1) } ?? false } ?? false
        listening = ours && entry?.phase == .listening
        pad.setListening(listening)
        if ours { noAnswer?.invalidate() }
        switch Pad.react(to: entry, startedAt: startedAt, sameField: textDocumentProxy.documentIdentifier == field) {
        case .insert(let take):
            if let words = mailbox.claim(take) { insert(words) }
            finish(nil)
        case .offerInsertLast:
            pad.insertLast.isHidden = false
            finish(nil)
        case .status(let line):
            pad.status.text = line
            if entry?.phase == .nothing || entry?.phase == .failed { finish(line) }
        case .none:
            break
        }
    }

    private func insert(_ words: String) {
        textDocumentProxy.insertText(Pad.spaced(words, after: textDocumentProxy.documentContextBeforeInput))
    }

    private func finish(_ line: String?) {
        startedAt = nil
        listening = false
        pad.setListening(false)
        pad.status.text = line
    }
}
