// SPDX-License-Identifier: GPL-3.0-only
// The Journey on iPhone (ios/prd.json IOS-017), in plain native views until
// IOS-018 paints it: the belt with its stripes, the words and days toward
// the next one, and the dated promotions.
import MurmurCore
import SwiftUI

struct JourneyScreen: View {
    let history: History
    let rules: JourneyRules

    var body: some View {
        let report = Journey.report(history.entries, rules: rules)
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    BeltSwatch(rank: report.rank, rules: rules)
                        .frame(width: 168, height: 18)
                    Text(report.rank.label)
                        .font(.title3.weight(.semibold))
                    Text(report.rank.title)
                        .foregroundStyle(Tokens.textDim)
                    Text(JourneyCopy.level(report.level))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Tokens.brand)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Tokens.panel)

            Section {
                if let words = report.words, let days = report.activeDays {
                    Gate(text: JourneyCopy.words(words), pct: words.pct)
                    Gate(text: JourneyCopy.days(days), pct: days.pct)
                } else {
                    Text(JourneyCopy.top)
                }
            } header: {
                SectionTitle(report.next.map { "\(JourneyCopy.toward) \($0.label)" } ?? JourneyCopy.title)
            }
            .listRowBackground(Tokens.panel)

            Section {
                if report.promotions.isEmpty {
                    Text(JourneyCopy.firstBelt(report.next))
                        .foregroundStyle(Tokens.textDim)
                } else {
                    ForEach(report.promotions.reversed(), id: \.id) { promotion in
                        let rank = rules.ranks.ranks.first { $0.id == promotion.id }
                        LabeledContent(rank?.label ?? promotion.id, value: JourneyCopy.promoted(Date(timeIntervalSince1970: TimeInterval(promotion.at) / 1000)))
                    }
                }
            } header: {
                SectionTitle(JourneyCopy.promotions)
            } footer: {
                Text(JourneyCopy.devices).foregroundStyle(Tokens.textDim)
            }
            .listRowBackground(Tokens.panel)
        }
        .scrollContentBackground(.hidden)
        .background(Tokens.ink)
        .foregroundStyle(Tokens.text)
        .navigationTitle(JourneyCopy.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One gate: a line of numbers over a quiet bar, gold once it holds.
private struct Gate: View {
    let text: String
    let pct: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
            ProgressView(value: pct)
                .tint(pct >= 1 ? Tokens.brand : Tokens.textDim)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Where a belt's rank bar and tape go, as desktop's painter lays them out
/// (journeyPaint.ts): the bar from 70 to 86 percent of the belt's length,
/// none on coral or red belts (or no belt), and up to four tapes, six
/// degrees on a black belt, spaced to fit inside the bar. All in fractions
/// of the length.
struct BeltLayout: Equatable {
    static let barStart = 0.7
    static let barEnd = 0.86

    let bar: ClosedRange<Double>?
    let tapes: [Double]
    let tapeWidth: Double

    static func of(belt: String, stripes: Int) -> BeltLayout {
        guard belt != "none", belt != "red", !belt.hasPrefix("coral") else { return BeltLayout(bar: nil, tapes: [], tapeWidth: 0) }
        let cap = belt == "black" ? 6 : 4
        let space = (barEnd - barStart) / Double(cap + 1)
        let tapes = (0..<min(max(stripes, 0), cap)).map { barStart + space * Double($0 + 1) }
        return BeltLayout(bar: barStart...barEnd, tapes: tapes, tapeWidth: space * 0.5)
    }
}

/// A belt drawn plainly, as desktop lays it out: the fabric, the rank bar
/// (red on a black belt, none on coral or red belts), and a strip of cream
/// tape per stripe.
struct BeltSwatch: View {
    let rank: RankSpec
    let rules: JourneyRules

    var body: some View {
        let layout = BeltLayout.of(belt: rank.belt, stripes: rank.stripes)
        Canvas { context, size in
            let w = size.width
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(rules.fabric(rank.belt)))
            if let bar = layout.bar {
                let rect = CGRect(x: w * bar.lowerBound, y: 0, width: w * (bar.upperBound - bar.lowerBound), height: size.height)
                context.fill(Path(rect), with: .color(rank.belt == "black" ? rules.color("red") : Tokens.ink))
                for tape in layout.tapes {
                    let width = max(1, w * layout.tapeWidth)
                    context.fill(Path(CGRect(x: w * tape - width / 2, y: size.height * 0.15, width: width, height: size.height * 0.7)), with: .color(Tokens.text))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Tokens.panelEdge))
        .accessibilityHidden(true)
    }
}

/// Home's row into the Journey: the belt and where it stands.
struct JourneyRow: View {
    let history: History
    let rules: JourneyRules

    var body: some View {
        let report = Journey.report(history.entries, rules: rules)
        NavigationLink {
            JourneyScreen(history: history, rules: rules)
        } label: {
            HStack(spacing: 12) {
                BeltSwatch(rank: report.rank, rules: rules)
                    .frame(width: 72, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(JourneyCopy.title)
                    Text(report.rank.label)
                        .font(.footnote)
                        .foregroundStyle(Tokens.textDim)
                }
            }
            .frame(minHeight: 44)
        }
    }
}

#if DEBUG
/// A history in a scratch file with this many words a day, one take a day.
@MainActor private func previewHistory(_ name: String, words: [Int]) -> History {
    let store = HistoryStore(file: FileManager.default.temporaryDirectory.appending(path: "journey-preview-\(name).jsonl"))
    try? store.clear()
    let start = Date.now.addingTimeInterval(-Double(words.count) * 86_400)
    for (day, count) in words.enumerated() {
        try? store.append(HistoryEntry(at: start.addingTimeInterval(Double(day) * 86_400), durationMs: 60_000, words: Array(repeating: "word", count: count).joined(separator: " ")))
    }
    return History(store: store)
}

#Preview("No belt") {
    NavigationStack {
        if let rules = JourneyRules.live { JourneyScreen(history: previewHistory("none", words: []), rules: rules) }
    }
    .preferredColorScheme(.dark)
}

#Preview("White, two stripes") {
    NavigationStack {
        if let rules = JourneyRules.live { JourneyScreen(history: previewHistory("white2", words: [180, 900, 1500, 600, 2100, 1300, 800]), rules: rules) }
    }
    .preferredColorScheme(.dark)
}

#Preview("Belts on the Home row") {
    if let rules = JourneyRules.live {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(["white-4", "blue-2", "brown-4", "black", "black-6", "coral-7", "red-9"], id: \.self) { id in
                if let rank = rules.ranks.ranks.first(where: { $0.id == id }) {
                    HStack {
                        BeltSwatch(rank: rank, rules: rules).frame(width: 72, height: 10)
                        Text(rank.label).font(.footnote)
                    }
                }
            }
        }
        .padding()
        .background(Tokens.panel)
        .foregroundStyle(Tokens.text)
        .preferredColorScheme(.dark)
    }
}
#endif
