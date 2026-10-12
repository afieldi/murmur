// SPDX-License-Identifier: GPL-3.0-only
// The dictation pad's keys (ios/prd.json IOS-008): the pill in the middle,
// with globe, space, delete, and return around it, and Insert last when a
// take landed after you left its field. Kept in Shared so the app can
// preview it; only the keyboard wires it to a text field.
import UIKit

final class PadView: UIView {
    let pill = UIButton(type: .system)
    let status = UILabel()
    let insertLast = UIButton(type: .system)
    let globe = UIButton(type: .system)
    let space = UIButton(type: .system)
    let delete = UIButton(type: .system)
    let returnKey = UIButton(type: .system)
    let fullAccess = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(Tokens.ink)
        // The keyboard's height is fixed, so text grows only as far as it fits.
        maximumContentSizeCategory = .accessibilityMedium

        var pillLook = UIButton.Configuration.filled()
        pillLook.cornerStyle = .capsule
        pillLook.imagePadding = 8
        pillLook.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28)
        pill.configuration = pillLook
        setListening(false)

        for label in [status, fullAccess] {
            label.font = .preferredFont(forTextStyle: .footnote)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = UIColor(Tokens.textDim)
            label.textAlignment = .center
            label.numberOfLines = 2
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
        }
        fullAccess.numberOfLines = 4
        fullAccess.text = "murmur needs Full Access to hear you. Open Settings, then General, Keyboard, Keyboards, murmur, and turn on Allow Full Access."
        fullAccess.isHidden = true

        var insertLook = UIButton.Configuration.plain()
        insertLook.title = "Insert last"
        insertLook.baseForegroundColor = UIColor(Tokens.brand)
        insertLast.configuration = insertLook
        insertLast.isHidden = true

        key(globe, image: "globe", label: "Next keyboard")
        key(space, title: "space", label: "Space")
        key(delete, image: "delete.left", label: "Delete")
        key(returnKey, title: "Return", label: "Return")

        let top = UIStackView(arrangedSubviews: [insertLast, pill, status, fullAccess])
        top.axis = .vertical
        top.alignment = .center
        top.spacing = 6
        top.translatesAutoresizingMaskIntoConstraints = false
        // The pill keeps its size and sits in the middle of the space
        // above the keys, however tall that space is.
        let middle = UIView()
        middle.addSubview(top)
        let bottom = UIStackView(arrangedSubviews: [globe, space, delete, returnKey])
        bottom.spacing = 6
        let column = UIStackView(arrangedSubviews: [middle, bottom])
        column.axis = .vertical
        column.spacing = 8
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            top.centerXAnchor.constraint(equalTo: middle.centerXAnchor),
            top.centerYAnchor.constraint(equalTo: middle.centerYAnchor),
            top.topAnchor.constraint(greaterThanOrEqualTo: middle.topAnchor),
            top.bottomAnchor.constraint(lessThanOrEqualTo: middle.bottomAnchor),
            top.leadingAnchor.constraint(greaterThanOrEqualTo: middle.leadingAnchor),
            top.trailingAnchor.constraint(lessThanOrEqualTo: middle.trailingAnchor),
            pill.heightAnchor.constraint(equalToConstant: 56),
            insertLast.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 176),
            globe.widthAnchor.constraint(equalToConstant: 48),
            delete.widthAnchor.constraint(equalToConstant: 56),
            returnKey.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),
            bottom.heightAnchor.constraint(equalToConstant: 48)
        ])
        // The return key grows to fit its name (Emergency call is long) and
        // the space bar gives way; key labels stop growing where the row
        // still holds them, as the system keyboard's do.
        returnKey.setContentCompressionResistancePriority(.required, for: .horizontal)
        returnKey.setContentHuggingPriority(.required, for: .horizontal)
        space.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        space.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bottom.maximumContentSizeCategory = .extraExtraLarge
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PadView is built in code") }

    /// The pill: gold to start, live amber while listening.
    func setListening(_ listening: Bool) {
        var look = pill.configuration ?? .filled()
        look.title = listening ? "Stop" : "Tap to talk"
        look.image = UIImage(systemName: listening ? "stop.fill" : "mic.fill")
        look.baseBackgroundColor = UIColor(listening ? Tokens.amber : Tokens.panelLift)
        look.baseForegroundColor = UIColor(listening ? Tokens.ink : Tokens.brand)
        pill.configuration = look
        pill.accessibilityLabel = listening ? "Stop dictation" : "Start dictation"
    }

    /// Without Full Access the pill cannot work, so it gives way to the
    /// one line that says how to turn it on.
    func setFullAccess(_ granted: Bool) {
        pill.isHidden = !granted
        status.isHidden = !granted
        fullAccess.isHidden = granted
    }

    private func key(_ button: UIButton, image: String? = nil, title: String? = nil, label: String) {
        var look = UIButton.Configuration.filled()
        look.baseBackgroundColor = UIColor(Tokens.panelLift)
        look.baseForegroundColor = UIColor(Tokens.text)
        look.cornerStyle = .medium
        look.image = image.map { UIImage(systemName: $0) } ?? nil
        look.title = title
        look.titleLineBreakMode = .byTruncatingTail
        button.configuration = look
        button.accessibilityLabel = label
        button.titleLabel?.adjustsFontForContentSizeCategory = true
    }
}
