// SPDX-License-Identifier: GPL-3.0-only
// The microphone (ios/prd.json IOS-006): it asks the first time a take
// needs it, records mono through AVAudioSession, and hands back the take
// at 16 kHz, the rate the speech gate and the WAV use.
import AVFoundation
import MurmurCore
import Synchronization

@MainActor protocol Microphone: AnyObject {
    /// Asks the first time; true when murmur may record.
    func allow() async -> Bool
    func start() throws
    /// Stops and returns the take at 16 kHz.
    func stop() -> [Float]
}

enum MicrophoneError: Error {
    case noInput
}

@MainActor final class DeviceMicrophone: Microphone {
    private let engine = AVAudioEngine()
    private var capture: Capture?

    func allow() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: true
        case .denied: false
        default: await AVAudioApplication.requestRecordPermission()
        }
    }

    /// Music that is playing keeps playing (mixWithOthers).
    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
        try session.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard let capture = Capture(from: format) else { throw MicrophoneError.noInput }
        self.capture = capture
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: capture.tap)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.capture = nil
            throw error
        }
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        defer { capture = nil }
        return capture?.finish() ?? []
    }
}

/// Turns the input's buffers into 16 kHz mono as they arrive, on the
/// audio thread, so nothing here belongs to the main actor. The
/// converter keeps its state between buffers, so a take converts as one
/// stream.
final class Capture: Sendable {
    private struct State: ~Copyable {
        let converter: AVAudioConverter
        let output: AVAudioFormat
        var samples: [Float] = []
    }

    private let state: Mutex<State>

    /// Nil for a format with no audio in it (no input device).
    init?(from input: AVAudioFormat) {
        guard input.sampleRate > 0, input.channelCount > 0,
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(Wav.targetSampleRate), channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: output)
        else { return nil }
        converter.downmix = true
        state = Mutex(State(converter: converter, output: output))
    }

    /// The take, with the last samples the converter holds back flushed
    /// out. Call once, after the last buffer.
    func finish() -> [Float] {
        state.withLock { state in
            if let out = AVAudioPCMBuffer(pcmFormat: state.output, frameCapacity: 4_096) {
                var error: NSError?
                let status = state.converter.convert(to: out, error: &error) { _, inputStatus in
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                if status != .error, let channel = out.floatChannelData {
                    state.samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
                }
            }
            return state.samples
        }
    }

    /// The tap's block, made here so it never inherits the main actor.
    var tap: AVAudioNodeTapBlock {
        { [self] buffer, _ in append(buffer) }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        state.withLock { state in
            let ratio = state.output.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: state.output, frameCapacity: capacity) else { return }
            var fed = false
            var error: NSError?
            let status = state.converter.convert(to: out, error: &error) { _, inputStatus in
                if fed {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                fed = true
                inputStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, let channel = out.floatChannelData else { return }
            state.samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
        }
    }
}
