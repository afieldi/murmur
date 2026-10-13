// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import murmur

@MainActor @Suite struct SetupTests {
    let defaults: UserDefaults
    let report = Cell<KeyboardReport?>(nil)
    let key = Cell(false)

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "murmur.tests.\(UUID().uuidString)"))
    }

    func setup(_ access: ScriptedAccess = ScriptedAccess(answer: true)) -> Setup {
        Setup(microphone: access, report: { [report] in report.value }, hasKey: { [key] in key.value }, defaults: defaults)
    }

    /// Four steps in order, then the practice take.
    @Test func theStepsGoInOrder() {
        #expect(Setup.Step.allCases == [.microphone, .keyboard, .fullAccess, .key, .practice])
        let fresh = setup()
        #expect(fresh.next == .microphone)
        #expect(fresh.remaining == Setup.Step.allCases)
        #expect(!fresh.isFinished)
        #expect(!fresh.seen)
    }

    @Test func allowingTheMicrophoneMovesOn() async {
        let setup = setup(ScriptedAccess(answer: true))
        await setup.allowMicrophone()
        #expect(setup.status(.microphone) == .done)
        #expect(setup.next == .keyboard)
    }

    /// A refused microphone says so, and stays first in line.
    @Test func aRefusedMicrophoneWaitsForSettings() async {
        let setup = setup(ScriptedAccess(answer: false))
        await setup.allowMicrophone()
        #expect(setup.status(.microphone) == .denied)
        #expect(setup.next == .microphone)
        #expect(setup.remaining.first == .microphone)
    }

    /// The keyboard's own report, written only with Full Access, proves the
    /// keyboard is added and Full Access is on.
    @Test func theKeyboardsReportProvesBothSteps() {
        let setup = setup()
        report.value = KeyboardReport(fullAccess: true, at: .now)
        setup.refresh()
        #expect(setup.status(.keyboard) == .done)
        #expect(setup.status(.fullAccess) == .done)
    }

    /// Without Full Access the keyboard cannot report, so your word that it
    /// is added does that step alone.
    @Test func yourWordAddsTheKeyboardOnly() {
        let setup = setup()
        setup.keyboardAdded()
        #expect(setup.status(.keyboard) == .done)
        #expect(setup.status(.fullAccess) == .todo)
    }

    @Test func aSavedKeyChecksItself() {
        let setup = setup()
        #expect(setup.status(.key) == .todo)
        key.value = true
        setup.refresh()
        #expect(setup.status(.key) == .done)
    }

    /// A skipped step stays skipped, waits on Home, and first run moves to
    /// the next step still to do.
    @Test func aSkippedStepWaitsOnHome() {
        let first = setup()
        first.skip(.microphone)
        #expect(first.status(.microphone) == .skipped)
        #expect(first.next == .keyboard)
        let again = setup()
        #expect(again.status(.microphone) == .skipped)
        #expect(again.remaining.contains(.microphone))
    }

    @Test func everyStepDoneFinishesSetup() async {
        let setup = setup()
        await setup.allowMicrophone()
        report.value = KeyboardReport(fullAccess: true, at: .now)
        key.value = true
        setup.practiced()
        #expect(setup.isFinished)
        #expect(setup.remaining.isEmpty)
        #expect(setup.next == nil)
    }

    @Test func firstRunShowsOnce() {
        let first = setup()
        first.seen = true
        #expect(setup().seen)
    }
}
