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
    private var targetBrightness = 0.0
    private var targetOrchestra = AudioOrchestraTarget.silence
    private var currentAmplitude = 0.0
    private var currentBrightness = 0.0
    private var currentOrchestraAmplitude = 0.0
    private var currentOrchestraRichness = 0.0
    private var currentOrchestraMotion = 0.0
    private var phase = 0.0
    private var overtonePhase = 0.0
    private var orchestraPhases = [0.0, 0.0, 0.0, 0.0]
    private var orchestraTremoloPhase = 0.0
    private var muted = true
    private var accents: [AccentVoice] = []
    private var pendingAccents: [AccentVoice] = []

    func update(soundState: SoundState, muted isMuted: Bool) {
        lock.lock()
        muted = isMuted || soundState.isSilent
        targetFrequency = sanitizedFrequency(soundState.frequency)
        targetAmplitude = muted ? 0 : sanitizedUnit(soundState.amplitude)
        targetBrightness = muted ? 0 : sanitizedUnit(soundState.filterBrightness)
        targetOrchestra = muted ? .silence : AudioOrchestraTarget(soundState.orchestra)

        if soundState.accentTriggered, !muted {
            pendingAccents.append(
                AccentVoice(
                    frequency: targetFrequency * 2.5,
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
            targetBrightness = 0
            targetOrchestra = .silence
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
        var brightness = targetBrightness
        var orchestraTarget = targetOrchestra
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
            brightness = 0
            orchestraTarget = .silence
        }

        let amplitudeStep = (amplitude - currentAmplitude) / Double(frameCount)
        let brightnessStep = (brightness - currentBrightness) / Double(frameCount)
        let orchestraAmplitudeStep = (orchestraTarget.amplitude - currentOrchestraAmplitude) / Double(frameCount)
        let orchestraRichnessStep = (orchestraTarget.richness - currentOrchestraRichness) / Double(frameCount)
        let orchestraMotionStep = (orchestraTarget.motion - currentOrchestraMotion) / Double(frameCount)
        let phaseIncrement = twoPi * frequency / sampleRate
        let overtonePhaseIncrement = phaseIncrement * 2

        for _ in 0..<frameCount {
            currentAmplitude += amplitudeStep
            currentBrightness += brightnessStep
            currentOrchestraAmplitude += orchestraAmplitudeStep
            currentOrchestraRichness += orchestraRichnessStep
            currentOrchestraMotion += orchestraMotionStep

            let overtoneMix = currentBrightness * 0.28
            let leadSample = (
                sin(phase) * (1 - overtoneMix)
                    + sin(overtonePhase) * overtoneMix
            ) * currentAmplitude
            let orchestraSample = renderOrchestraSample(target: orchestraTarget)
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
            overtonePhase = wrappedPhase(overtonePhase + overtonePhaseIncrement)
            let sample = Float(max(-1, min(1, leadSample + orchestraSample + accentSample)))
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

    private func renderOrchestraSample(target: AudioOrchestraTarget) -> Double {
        guard
            target.voiceCount > 0,
            currentOrchestraAmplitude > 0,
            target.rootFrequency > 0,
            !target.intervalSemitones.isEmpty
        else {
            return 0
        }

        let voiceCount = min(target.voiceCount, maxOrchestraVoices)
        let padRootFrequency = clamp(target.rootFrequency * 0.5, lower: 55, upper: 1_600)
        let voiceGain = currentOrchestraAmplitude / sqrt(Double(voiceCount)) * 0.55
        let harmonicMix = currentOrchestraRichness * 0.22
        let tremoloRate = 0.28 + currentOrchestraMotion * 4.5
        let tremoloDepth = currentOrchestraMotion * 0.28
        var sample = 0.0

        for voiceIndex in 0..<voiceCount {
            let semitone = target.intervalSemitones[voiceIndex % target.intervalSemitones.count]
            let detuneDirection = voiceIndex.isMultiple(of: 2) ? -1.0 : 1.0
            let detune = detuneDirection * target.detuneCents * (0.35 + Double(voiceIndex) * 0.16)
            let frequency = clamp(
                padRootFrequency * pow(2, (Double(semitone) + detune / 100) / 12),
                lower: 45,
                upper: 3_500
            )
            let phase = orchestraPhases[voiceIndex]
            let tremolo = 1 - tremoloDepth + tremoloDepth * (0.5 + 0.5 * sin(orchestraTremoloPhase + Double(voiceIndex)))
            let tone = sin(phase) * (1 - harmonicMix) + sin(phase * 2) * harmonicMix

            sample += tone * voiceGain * tremolo
            orchestraPhases[voiceIndex] = wrappedPhase(phase + twoPi * frequency / sampleRate)
        }

        orchestraTremoloPhase = wrappedPhase(orchestraTremoloPhase + twoPi * tremoloRate / sampleRate)
        return sample
    }
}

private struct AccentVoice {
    var frequency: Double
    var amplitude: Double
    var phase: Double
    var age: Double
}

private struct AudioOrchestraTarget {
    var rootFrequency: Double
    var amplitude: Double
    var voiceCount: Int
    var intervalSemitones: [Int]
    var richness: Double
    var motion: Double
    var detuneCents: Double

    init(_ state: ScreenOrchestraState) {
        guard state.isActive else {
            self = .silence
            return
        }

        rootFrequency = sanitizedFrequency(state.rootFrequency)
        amplitude = min(sanitizedUnit(state.amplitude), 0.35)
        voiceCount = clamp(state.voiceCount, lower: 0, upper: maxOrchestraVoices)
        intervalSemitones = state.intervalSemitones
        richness = sanitizedUnit(state.richness)
        motion = sanitizedUnit(state.motion)
        detuneCents = clamp(state.detuneCents.isFinite ? state.detuneCents : 0, lower: 0, upper: 16)
    }

    private init(
        rootFrequency: Double,
        amplitude: Double,
        voiceCount: Int,
        intervalSemitones: [Int],
        richness: Double,
        motion: Double,
        detuneCents: Double
    ) {
        self.rootFrequency = rootFrequency
        self.amplitude = amplitude
        self.voiceCount = voiceCount
        self.intervalSemitones = intervalSemitones
        self.richness = richness
        self.motion = motion
        self.detuneCents = detuneCents
    }

    static let silence = AudioOrchestraTarget(
        rootFrequency: 0,
        amplitude: 0,
        voiceCount: 0,
        intervalSemitones: [],
        richness: 0,
        motion: 0,
        detuneCents: 0
    )
}

private let twoPi = Double.pi * 2
private let maxAccentVoices = 5
private let maxOrchestraVoices = 4
private let accentDuration = 0.65
private let accentDecay = 11.0
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

private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
}

private func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
    min(max(value, lower), upper)
}
