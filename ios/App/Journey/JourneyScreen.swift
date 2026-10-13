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

/// A belt drawn plainly: its color, and at the tip a dark bar (red on a
/// black belt) with one white mark per stripe.
struct BeltSwatch: View {
    let rank: RankSpec
    let rules: JourneyRules

    var body: some View {
        GeometryReader { box in
            let tip = box.size.width * 0.3
            HStack(spacing: 0) {
                Rectangle().fill(rules.color(rank.belt))
                ZStack {
                    Rectangle().fill(rank.belt == "black" ? rules.color("red") : Color.black)
                    HStack(spacing: 3) {
                        ForEach(0..<rank.stripes, id: \.self) { _ in
                            Rectangle().fill(Color.white).frame(width: 3)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(width: rank.belt == "none" ? 0 : tip)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Tokens.panelEdge))
        }
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
                    .frame(width: 56, height: 10)
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
