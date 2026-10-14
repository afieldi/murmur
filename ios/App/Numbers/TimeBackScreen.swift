// SPDX-License-Identifier: GPL-3.0-only
// Time back and recap (ios/prd.json IOS-022): your thumb typing speed, which
// time back is counted against, and the daily recap, off until you turn it
// on. Turning it on is the only moment murmur asks to send notifications.
import MurmurCore
import SwiftUI
import UIKit
import UserNotifications

struct TimeBackScreen: View {
    let history: History
    @State private var settings = NumbersSettings.load()
    @State private var time = Date.now
    @State private var denied = false
    @State private var asking = false
    /// Set while a refusal turns the switch back off, so that change is
    /// not taken as you turning it off.
    @State private var reverting = false

    var body: some View {
        Form {
            Section {
                Stepper(value: $settings.typingWpm, in: TimeBack.minWpm...TimeBack.maxWpm, step: 1) {
                    Text(NumbersCopy.wpm(settings.typingWpm))
                }
            } header: {
                SectionTitle(NumbersCopy.typing)
            } footer: {
                Text(NumbersCopy.typingFooter).foregroundStyle(Tokens.textDim)
            }
            .listRowBackground(Tokens.panel)

            Section {
                Toggle(NumbersCopy.recap, isOn: $settings.recapOn)
                    .tint(Tokens.brand)
                    .disabled(asking)
                if settings.recapOn {
                    DatePicker(NumbersCopy.recapTime, selection: $time, displayedComponents: .hourAndMinute)
                    Button(NumbersCopy.sendNow) {
                        Task { await RecapNotifications.sendNow(history.entries) }
                    }
                    .buttonStyle(RowAction())
                    .frame(minHeight: 44)
                }
                if denied {
                    Text(NumbersCopy.denied)
                        .foregroundStyle(Tokens.textDim)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link(NumbersCopy.openSettings, destination: url)
                            .buttonStyle(RowAction())
                            .frame(minHeight: 44)
                    }
                }
            } header: {
                SectionTitle(NumbersCopy.recap)
            } footer: {
                Text(NumbersCopy.recapFooter).foregroundStyle(Tokens.textDim)
            }
            .listRowBackground(Tokens.panel)
        }
        .scrollContentBackground(.hidden)
        .background(Tokens.ink)
        .foregroundStyle(Tokens.text)
        .navigationTitle(NumbersCopy.screen)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            settings = NumbersSettings.load()
            time = Self.date(hour: settings.recapHour, minute: settings.recapMinute)
        }
        .task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            denied = settings.recapOn && status == .denied
        }
        .onChange(of: settings.typingWpm) {
            settings.save()
            replan()
        }
        .onChange(of: time) {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            settings.recapHour = parts.hour ?? 17
            settings.recapMinute = parts.minute ?? 30
            settings.save()
            replan()
        }
        .onChange(of: settings.recapOn) { _, on in
            guard !reverting else {
                reverting = false
                return
            }
            Task { await turned(on) }
        }
    }

    /// Turning the recap on asks once; refused, it stays off and says where
    /// to turn notifications on.
    private func turned(_ on: Bool) async {
        if on {
            asking = true
            let allowed = await RecapNotifications.ask()
            asking = false
            denied = !allowed
            if !allowed {
                reverting = true
                settings.recapOn = false
            }
        } else {
            denied = false
        }
        settings.save()
        replan()
    }

    private func replan() {
        let entries = history.entries
        Task { await RecapNotifications.refresh(entries) }
    }

    static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }
}
