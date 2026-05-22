import AVFoundation
import Foundation
import SoundaCore

final class AudioEngineController {
    private let engine = AVAudioEngine()
    private let sourceNode: AVAudioSourceNode
    private let renderState = AudioRenderState()
    private(set) var errorMessage: String?

    init() {
        sourceNode = AVAudioSourceNode { [renderState] _, _, frameCount, audioBufferList in
            renderState.render(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }

        engine.attach(sourceNode)

        let mixer = engine.mainMixerNode
        let sampleRate = mixer.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate > 0 ? sampleRate : 44_100,
            channels: 2
        )

        renderState.sampleRate = format?.sampleRate ?? 44_100
        engine.connect(sourceNode, to: mixer, format: format)
    }

    var isRunning: Bool {
        engine.isRunning
    }

    func start() -> Bool {
        guard !engine.isRunning else {
            return true
        }

        do {
            try engine.start()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Audio unavailable: \(error.localizedDescription)"
            renderState.update(soundState: .silence, muted: true)
            return false
        }
    }

    func stop() {
        renderState.update(soundState: .silence, muted: true)
        engine.stop()
    }

    func setMuted(_ isMuted: Bool) {
        renderState.setMuted(isMuted)
    }

    func updateState(_ soundState: SoundState) {
        renderState.update(soundState: soundState, muted: !soundState.isEnabled)
    }

    func renderDebugMetrics(
        for soundStates: [SoundState],
        framesPerState: Int = 2_048
    ) -> AudioDebugMetrics {
        let debugRenderState = AudioRenderState()
        debugRenderState.sampleRate = renderState.sampleRate
        var metrics = AudioDebugMetrics()

        for soundState in soundStates {
            debugRenderState.update(soundState: soundState, muted: !soundState.isEnabled)
            debugRenderState.renderSamples(frameCount: framesPerState) { sample, accentSample in
                metrics.observe(sample: sample, accentSample: accentSample)
            }
        }

        return metrics
    }
}

struct AudioDebugMetrics {
    private(set) var frameCount = 0
    private(set) var peak = 0.0
    private(set) var accentPeak = 0.0
    private var sumOfSquares = 0.0

    var rms: Double {
        guard frameCount > 0 else {
            return 0
        }

        return sqrt(sumOfSquares / Double(frameCount))
    }

    mutating func observe(sample: Float, accentSample: Float) {
        let sample = Double(sample)
        let accentSample = Double(accentSample)
        frameCount += 1
        peak = max(peak, abs(sample))
        accentPeak = max(accentPeak, abs(accentSample))
        sumOfSquares += sample * sample
    }
}

private final class AudioRenderState {
    var sampleRate = 44_100.0

    private let lock = NSLock()
    private var targetFrequency = 0.0
    private var targetAmplitude = 0.0
    private var currentAmplitude = 0.0
    private var phase = 0.0
    private var muted = true
    private var accents: [AccentVoice] = []
    private var pendingAccents: [AccentVoice] = []

    func update(soundState: SoundState, muted isMuted: Bool) {
        lock.lock()
        muted = isMuted || soundState.isSilent
        targetFrequency = sanitizedFrequency(soundState.frequency)
        targetAmplitude = muted ? 0 : sanitizedUnit(soundState.amplitude)

        if soundState.accentTriggered, !muted {
            pendingAccents.append(
                AccentVoice(
                    frequency: targetFrequency * 2,
                    amplitude: sanitizedUnit(soundState.accentIntensity),
                    phase: 0,
                    age: 0
                )
            )

            if pendingAccents.count > maxAccentVoices {
                pendingAccents.removeFirst(pendingAccents.count - maxAccentVoices)
            }
        }
        lock.unlock()
    }

    func setMuted(_ isMuted: Bool) {
        lock.lock()
        muted = isMuted
        if isMuted {
            targetAmplitude = 0
            accents.removeAll(keepingCapacity: true)
            pendingAccents.removeAll(keepingCapacity: true)
        }
        lock.unlock()
    }

    func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard frameCount > 0 else {
            clear(bufferList: bufferList, frameCount: frameCount)
            return
        }

        var frameIndex = 0
        renderSamples(frameCount: frameCount) { sample, _ in
            for buffer in bufferList {
                guard let data = buffer.mData else {
                    continue
                }

                let channel = data.assumingMemoryBound(to: Float.self)
                channel[frameIndex] = sample
            }

            frameIndex += 1
        }
    }

    func renderSamples(
        frameCount: Int,
        observe: (_ sample: Float, _ accentSample: Float) -> Void
    ) {
        guard frameCount > 0 else {
            return
        }

        lock.lock()
        let frequency = targetFrequency
        var amplitude = targetAmplitude
        let isMuted = muted
        var localAccents = accents
        localAccents.append(contentsOf: pendingAccents)
        pendingAccents.removeAll(keepingCapacity: true)
        if localAccents.count > maxAccentVoices {
            localAccents.removeFirst(localAccents.count - maxAccentVoices)
        }
        lock.unlock()

        if isMuted {
            amplitude = 0
        }

        let amplitudeStep = (amplitude - currentAmplitude) / Double(frameCount)
        let phaseIncrement = twoPi * frequency / sampleRate

        for _ in 0..<frameCount {
            currentAmplitude += amplitudeStep

            let leadSample = sin(phase) * currentAmplitude
            var accentSample = 0.0

            for accentIndex in localAccents.indices {
                let envelope = exp(-localAccents[accentIndex].age * accentDecay)
                accentSample += sin(localAccents[accentIndex].phase) * localAccents[accentIndex].amplitude * envelope
                localAccents[accentIndex].phase = wrappedPhase(
                    localAccents[accentIndex].phase + twoPi * localAccents[accentIndex].frequency / sampleRate
                )
                localAccents[accentIndex].age += 1 / sampleRate
            }

            phase = wrappedPhase(phase + phaseIncrement)
            let sample = Float(max(-1, min(1, leadSample + accentSample)))
            observe(sample, Float(accentSample))
        }

        localAccents.removeAll { accent in
            accent.age >= accentDuration || accent.amplitude * exp(-accent.age * accentDecay) < accentSilenceThreshold
        }

        lock.lock()
        if muted {
            accents.removeAll(keepingCapacity: true)
        } else {
            accents = localAccents
        }
        lock.unlock()
    }

    private func clear(bufferList: UnsafeMutableAudioBufferListPointer, frameCount: Int) {
        for buffer in bufferList {
            guard let data = buffer.mData else {
                continue
            }

            data.assumingMemoryBound(to: Float.self).initialize(repeating: 0, count: frameCount)
        }
    }
}

private struct AccentVoice {
    var frequency: Double
    var amplitude: Double
    var phase: Double
    var age: Double
}

private let twoPi = Double.pi * 2
private let maxAccentVoices = 8
private let accentDuration = 0.9
private let accentDecay = 8.0
private let accentSilenceThreshold = 0.0005

private func wrappedPhase(_ phase: Double) -> Double {
    let wrapped = phase.truncatingRemainder(dividingBy: twoPi)
    return wrapped >= 0 ? wrapped : wrapped + twoPi
}

private func sanitizedFrequency(_ frequency: Double) -> Double {
    guard frequency.isFinite, frequency > 0 else {
        return 0
    }

    return min(frequency, 4_000)
}

private func sanitizedUnit(_ value: Double) -> Double {
    guard value.isFinite else {
        return 0
    }

    return min(max(value, 0), 1)
}
