// SPDX-License-Identifier: GPL-3.0-only
// The belt share card (ios/prd.json IOS-021): desktop's card, painted from
// your last thirty days by desktop's own code in the painter page (a stroke
// for each day you dictated, longer for more words, heavier for more takes,
// ember on your three biggest), with your rank set in the display face. The
// screen shows it and saves it through the share sheet; nothing is sent
// anywhere.
import MurmurCore
import SwiftUI

/// What the card paints: the last thirty days and where practice stands.
struct ShareCard: Hashable, Sendable {
    let days: [DayTotal]
    let rank: String
    let label: String
    let level: Int

    /// The card for these takes, with `today` the last of its days.
    static func from(_ entries: [HistoryEntry], rules: JourneyRules, today: String = HistoryEntry.dayKey(.now)) -> ShareCard {
        let report = Journey.report(entries, rules: rules)
        let days = Analytics.dailyTotals(entries.map(\.rankEvent), count: Analytics.cardDays, today: today)
        return ShareCard(days: days, rank: report.rank.id, label: report.rank.label, level: report.level)
    }

    var artwork: JourneyArtwork { .share(days: days, rank: rank, level: level) }

    /// The month's words, as the card adds them.
    var words: Int { days.reduce(0) { $0 + $1.words } }

    /// Days with words, the card's days on the mat.
    var activeDays: Int { days.filter { $0.words > 0 }.count }
}

/// The share card's words.
enum ShareCardCopy {
    static let row = "Share card"
    static let title = "Your share card"
    static let about = "Painted from your last 30 days: a stroke for each day you dictated, ember on your three biggest."
    static let save = "Save card"
    static let painting = "Painting your card"
    static let failed = "The card did not paint."
    static let tryAgain = "Try again"
    /// Desktop's file name for the belt card.
    static let fileName = "murmur-belt.png"

    /// What VoiceOver reads for the card: its words, which are part of the
    /// picture.
    static func spoken(_ card: ShareCard) -> String {
        let words = card.words.formatted(.number)
        let days = card.activeDays == 1 ? "1 day" : "\(card.activeDays) days"
        return "Share card: \(card.label), \(words) words in the last 30 days, \(days) on the mat, level \(card.level)."
    }
}

/// The card, shown large, with Save card.
struct ShareCardScreen: View {
    let history: History
    let rules: JourneyRules
    @Environment(\.displayScale) private var scale
    @State private var shown: Shown = .painting
    @State private var attempt = 0

    enum Shown: Equatable {
        case painting
        case painted(UIImage)
        case failed
    }

    /// The card's size in points, desktop's.
    static let size = CGSize(width: 840, height: 440)

    var body: some View {
        // Made here, so the card is read only while the screen is open.
        let card = ShareCard.from(history.entries, rules: rules)
        List {
            Section {
                preview(card)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                Text(ShareCardCopy.about)
                    .foregroundStyle(Tokens.textDim)
                switch shown {
                case let .painted(image):
                    ShareLink(item: PaintingShare(name: ShareCardCopy.fileName, artwork: card.artwork), preview: SharePreview(ShareCardCopy.title, image: Image(uiImage: image))) {
                        Text(ShareCardCopy.save)
                            .foregroundStyle(Tokens.brand)
                            .frame(minHeight: 44)
                    }
                case .failed:
                    Button(ShareCardCopy.tryAgain) { attempt += 1 }
                        .buttonStyle(RowAction())
                        .frame(minHeight: 44)
                case .painting:
                    EmptyView()
                }
            }
            .listRowBackground(Tokens.panel)
        }
        .scrollContentBackground(.hidden)
        .background(Tokens.ink)
        .foregroundStyle(Tokens.text)
        .navigationTitle(ShareCardCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: Paint(card: card, scale: scale, attempt: attempt)) {
            shown = .painting
            do {
                shown = .painted(try await JourneyPainter.shared.picture(card.artwork, scale: scale).image)
            } catch {
                shown = .failed
            }
        }
    }

    private struct Paint: Hashable {
        let card: ShareCard
        let scale: CGFloat
        let attempt: Int
    }

    @ViewBuilder private func preview(_ card: ShareCard) -> some View {
        let ratio = Self.size.width / Self.size.height
        switch shown {
        case let .painted(image):
            Image(uiImage: image)
                .resizable()
                .aspectRatio(ratio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(ShareCardCopy.spoken(card))
                .accessibilityAddTraits(.isImage)
        case .painting, .failed:
            RoundedRectangle(cornerRadius: 10)
                .fill(Tokens.panelLift)
                .aspectRatio(ratio, contentMode: .fit)
                .overlay {
                    Text(shown == .failed ? ShareCardCopy.failed : ShareCardCopy.painting)
                        .font(.footnote)
                        .foregroundStyle(Tokens.textDim)
                        .padding()
                }
                .accessibilityElement(children: .combine)
        }
    }
}
