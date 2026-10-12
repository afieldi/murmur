// SPDX-License-Identifier: GPL-3.0-only
// A stand-in microphone for the smoke and the tests: it hands back the
// samples it was given, so a take runs end to end with no hardware.
import Foundation
import MurmurCore

@MainActor final class ScriptedMicrophone: Microphone {
    var allowed = true
    var startError: (any Error)?
    var samples: [Float]
    private(set) var asked = 0
    private(set) var started = 0

    init(samples: [Float] = []) {
        self.samples = samples
    }

    func allow() async -> Bool {
        asked += 1
        return allowed
    }

    func start() throws {
        if let startError { throw startError }
        started += 1
    }

    func stop() -> [Float] { samples }

    /// A second of a 220 Hz tone at speaking level between half seconds
    /// of silence, at 16 kHz.
    nonisolated static let tone: [Float] = {
        let rate = Double(Wav.targetSampleRate)
        let quiet = [Float](repeating: 0, count: Wav.targetSampleRate / 2)
        let voiced = (0..<Wav.targetSampleRate).map { Float(0.3 * sin(2 * Double.pi * 220 * Double($0) / rate)) }
        return quiet + voiced + quiet
    }()

    /// Two seconds of nothing.
    nonisolated static let silence = [Float](repeating: 0, count: Wav.targetSampleRate * 2)
}
