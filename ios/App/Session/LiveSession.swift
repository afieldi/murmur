// SPDX-License-Identifier: GPL-3.0-only
// The session's Live Activity on the Lock Screen and in the Dynamic Island
// (ios/prd.json IOS-016), shown while a session runs.
import ActivityKit
import Foundation

/// The session's Live Activity: one at a time, shown while the session is
/// on, updated when a take starts or ends, and ended with the session.
/// Updates run in order, the newest state winning. Only the activity's id
/// is kept here; ActivityKit's own list holds the activity.
@MainActor final class LiveSession {
    static let shared = LiveSession()

    private var activityID: String?
    private var latest: SessionActivity.ContentState?
    private var running: Task<Void, Never>?

    /// Shows the session's state, or ends the Live Activity when it is off.
    func show(_ state: SessionActivity.ContentState?) {
        latest = state
        guard running == nil else { return }
        running = Task { await drain() }
    }

    private func drain() async {
        while true {
            let want = latest
            await apply(want)
            if latest == want { break }
        }
        running = nil
    }

    private func apply(_ state: SessionActivity.ContentState?) async {
        guard let state else {
            await Self.endAll()
            activityID = nil
            return
        }
        activityID = await Self.present(state, over: activityID)
    }

    /// Updates the activity with this id while it is up, or starts one.
    /// Its id, or nil when iOS would not start one (Live Activities off).
    private nonisolated static func present(_ state: SessionActivity.ContentState, over id: String?) async -> String? {
        let content = ActivityContent(state: state, staleDate: state.until)
        if let id, let open = Activity<SessionActivity>.activities.first(where: { $0.id == id && $0.activityState == .active }) {
            await open.update(content)
            return id
        }
        return (try? Activity.request(attributes: SessionActivity(), content: content))?.id
    }

    private nonisolated static func endAll() async {
        for open in Activity<SessionActivity>.activities {
            await open.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Whether this session's Live Activity is up now; the smoke reads this.
    var isShowing: Bool {
        guard let activityID else { return false }
        return Activity<SessionActivity>.activities.contains { $0.id == activityID && $0.activityState == .active }
    }

    /// Waits until updates have run; the smoke uses this.
    func settle() async {
        while let running { await running.value }
    }
}
