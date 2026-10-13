// SPDX-License-Identifier: GPL-3.0-only
// murmur's widget extension (ios/prd.json IOS-016): the Start murmur
// control for Control Center, the Lock Screen, and the Action Button, and
// the session's Live Activity on the Lock Screen and in the Dynamic Island.
// The Live Activity shows still states, Ready or Recording, the time left,
// and End; iOS redraws it only now and then, so it never follows the voice.
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct MurmurWidgets: WidgetBundle {
    var body: some Widget {
        SessionControlWidget()
        SessionLiveActivity()
    }
}

/// One tap starts a session without opening murmur.
struct SessionControlWidget: ControlWidget {
    static let kind = "session"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartSessionIntent()) {
                Label(SessionWidgetCopy.control, systemImage: "waveform")
            }
        }
        .displayName(LocalizedStringResource(stringLiteral: SessionWidgetCopy.control))
        .description(LocalizedStringResource(stringLiteral: SessionWidgetCopy.controlDescription))
    }
}

struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivity.self) { context in
            LockScreenSession(state: context.state)
                .activityBackgroundTint(Tokens.ink)
                .activitySystemActionForegroundColor(Tokens.text)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PillMark(recording: context.state.recording)
                        .frame(width: 72, height: 28)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimeLeft(until: context.state.until)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(SessionActivityCopy.state(context.state.recording))
                        .font(.headline)
                        .foregroundStyle(context.state.recording ? Tokens.amber : Tokens.text)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EndButton()
                }
            } compactLeading: {
                PillMark(recording: context.state.recording)
                    .frame(width: 30, height: 14)
            } compactTrailing: {
                TimeLeft(until: context.state.until, compact: true)
                    .frame(width: 42)
            } minimal: {
                PillMark(recording: context.state.recording)
                    .frame(width: 22, height: 12)
            }
            .keylineTint(Tokens.brand)
        }
    }
}
