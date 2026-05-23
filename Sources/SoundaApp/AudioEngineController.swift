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
    private(set) var earlyRMS = 0.0
    private(set) var lateRMS = 0.0
    private var earlySumOfSquares = 0.0
    private var lateSumOfSquares = 0.0
    private var earlyFrameCount = 0
    private var lateFrameCount = 0
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

        if frameCount <= 1_024 {
            earlyFrameCount += 1
            earlySumOfSquares += sample * sample
            earlyRMS = sqrt(earlySumOfSquares / Double(earlyFrameCount))
        } else {
            lateFrameCount += 1
            lateSumOfSquares += sample * sample
            lateRMS = sqrt(lateSumOfSquares / Double(lateFrameCount))
        }
    }
}

private final class AudioRenderState {
    var sampleRate = 44_100.0

    private let lock = NSLock()
    private var targetFrequency = 0.0
    private var targetAmplitude = 0.0
    private var targetBrightness = 0.0
    private var targetLeadTimbre = SoundState.LeadTimbre.synth
    private var targetOrchestra = AudioOrchestraTarget.silence
    private var currentAmplitude = 0.0
    private var currentBrightness = 0.0
    private var currentOrchestraAmplitude = 0.0
    private var currentOrchestraRichness = 0.0
    private var currentOrchestraMotion = 0.0
    private var currentKickIntensity = 0.0
    private var currentSnareIntensity = 0.0
    private var currentHatIntensity = 0.0
    private var phase = 0.0
    private var overtonePhase = 0.0
    private var leadVibratoPhase = 0.0
    private var leadBowAge = 10.0
    private var lastLeadTimbre = SoundState.LeadTimbre.synth
    private var violinBodyLow = 0.0
    private var violinBodyMid = 0.0
    private var violinBodyHigh = 0.0
    private var orchestraPhases = [0.0, 0.0, 0.0, 0.0]
    private var orchestraTremoloPhase = 0.0
    private var grooveBeatPosition = 0.0
    private var lastGrooveStep = -1
    private var latchedLeadFrequency = 0.0
    private var leadStepAge = 10.0
    private var drumVoices: [DrumVoice] = []
    private var pendingDrumVoices: [DrumVoice] = []
    private var noiseState: UInt64 = 0x1234_5678_9ABC_DEF0
    private var previousHatNoise = 0.0
    private var muted = true
    private var accents: [AccentVoice] = []
    private var pendingAccents: [AccentVoice] = []

    func update(soundState: SoundState, muted isMuted: Bool) {
        lock.lock()
        muted = isMuted || soundState.isSilent
        targetFrequency = sanitizedFrequency(soundState.frequency)
        targetAmplitude = muted ? 0 : sanitizedUnit(soundState.amplitude)
        targetBrightness = muted ? 0 : sanitizedUnit(soundState.filterBrightness)
        targetLeadTimbre = muted ? .synth : soundState.leadTimbre
        targetOrchestra = muted ? .silence : AudioOrchestraTarget(soundState.orchestra)

        if targetOrchestra.clapTriggered, !muted {
            pendingDrumVoices.append(.snare(amplitude: max(0.2, targetOrchestra.snareIntensity)))
            if pendingDrumVoices.count > maxDrumVoices {
                pendingDrumVoices.removeFirst(pendingDrumVoices.count - maxDrumVoices)
            }
        }

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
            targetLeadTimbre = .synth
            targetOrchestra = .silence
            accents.removeAll(keepingCapacity: true)
            pendingAccents.removeAll(keepingCapacity: true)
            drumVoices.removeAll(keepingCapacity: true)
            pendingDrumVoices.removeAll(keepingCapacity: true)
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
        let leadTimbre = targetLeadTimbre
        var orchestraTarget = targetOrchestra
        let isMuted = muted
        var localAccents = accents
        var localDrumVoices = drumVoices
        localAccents.append(contentsOf: pendingAccents)
        localDrumVoices.append(contentsOf: pendingDrumVoices)
        pendingAccents.removeAll(keepingCapacity: true)
        pendingDrumVoices.removeAll(keepingCapacity: true)
        if localAccents.count > maxAccentVoices {
            localAccents.removeFirst(localAccents.count - maxAccentVoices)
        }
        if localDrumVoices.count > maxDrumVoices {
            localDrumVoices.removeFirst(localDrumVoices.count - maxDrumVoices)
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
        let kickIntensityStep = (orchestraTarget.kickIntensity - currentKickIntensity) / Double(frameCount)
        let snareIntensityStep = (orchestraTarget.snareIntensity - currentSnareIntensity) / Double(frameCount)
        let hatIntensityStep = (orchestraTarget.hatIntensity - currentHatIntensity) / Double(frameCount)

        for _ in 0..<frameCount {
            currentAmplitude += amplitudeStep
            currentBrightness += brightnessStep
            currentOrchestraAmplitude += orchestraAmplitudeStep
            currentOrchestraRichness += orchestraRichnessStep
            currentOrchestraMotion += orchestraMotionStep
            currentKickIntensity += kickIntensityStep
            currentSnareIntensity += snareIntensityStep
            currentHatIntensity += hatIntensityStep

            let overtoneMix = currentBrightness * 0.28
            updateLeadArticulation(timbre: leadTimbre, frequency: frequency)
            advanceGroove(
                target: orchestraTarget,
                desiredLeadFrequency: frequency,
                drumVoices: &localDrumVoices
            )
            let activeLeadFrequency = grooveLeadFrequency(fallback: frequency, target: orchestraTarget)
            let leadEnvelope = grooveLeadEnvelope(target: orchestraTarget)
            let leadSample = renderLeadSample(timbre: leadTimbre, overtoneMix: overtoneMix) * currentAmplitude * leadEnvelope
            let orchestraSample = renderOrchestraSample(target: orchestraTarget)
            let drumSample = renderDrumSample(drumVoices: &localDrumVoices)
            var accentSample = 0.0

            for accentIndex in localAccents.indices {
                let envelope = exp(-localAccents[accentIndex].age * accentDecay)
                accentSample += sin(localAccents[accentIndex].phase) * localAccents[accentIndex].amplitude * envelope
                localAccents[accentIndex].phase = wrappedPhase(
                    localAccents[accentIndex].phase + twoPi * localAccents[accentIndex].frequency / sampleRate
                )
                localAccents[accentIndex].age += 1 / sampleRate
            }

            let phaseIncrement = twoPi * activeLeadFrequency * leadVibratoMultiplier(timbre: leadTimbre) / sampleRate
            phase = wrappedPhase(phase + phaseIncrement)
            overtonePhase = wrappedPhase(overtonePhase + phaseIncrement * 2)
            advanceLeadModulation(timbre: leadTimbre)
            leadBowAge += 1 / sampleRate
            leadStepAge += 1 / sampleRate
            let sample = Float(max(-1, min(1, leadSample + orchestraSample + drumSample + accentSample)))
            observe(sample, Float(accentSample))
        }

        localAccents.removeAll { accent in
            accent.age >= accentDuration || accent.amplitude * exp(-accent.age * accentDecay) < accentSilenceThreshold
        }
        localDrumVoices.removeAll { drumVoice in
            drumVoice.age >= drumVoice.duration
        }

        lock.lock()
        if muted {
            accents.removeAll(keepingCapacity: true)
            drumVoices.removeAll(keepingCapacity: true)
        } else {
            accents = localAccents
            drumVoices = localDrumVoices
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
        let voiceGain = currentOrchestraAmplitude / sqrt(Double(voiceCount)) * 0.46
        let harmonicMix = currentOrchestraRichness * 0.18
        let tremoloRate = 0.12 + currentOrchestraMotion * 0.7
        let tremoloDepth = currentOrchestraMotion * 0.035
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
            let tone = softTriangle(phase) * (1 - harmonicMix) + sin(phase * 2) * harmonicMix

            sample += tone * voiceGain * tremolo
            orchestraPhases[voiceIndex] = wrappedPhase(phase + twoPi * frequency / sampleRate)
        }

        orchestraTremoloPhase = wrappedPhase(orchestraTremoloPhase + twoPi * tremoloRate / sampleRate)
        return sample
    }

    private func renderLeadSample(timbre: SoundState.LeadTimbre, overtoneMix: Double) -> Double {
        switch timbre {
        case .synth:
            return sin(phase) * (1 - overtoneMix) + sin(overtonePhase) * overtoneMix
        case .violin:
            let bowedEnvelope = min(1, 0.48 + leadBowAge * 13)
            let transientEnvelope = exp(-leadBowAge * 34)
            let bowMix = clamp(0.52 + currentBrightness * 0.28, lower: 0.52, upper: 0.80)
            let string = softTriangle(phase) * (1 - bowMix) + softSaw(phase) * bowMix
            let rosin = nextNoise() * transientEnvelope * 0.34
            let harmonicInput = string
                + sin(phase * 2) * 0.18
                + sin(phase * 3) * 0.10
                + sin(phase * 5) * currentBrightness * 0.045
            let body = violinBody(input: harmonicInput)
            return (body * bowedEnvelope + rosin) * 1.04
        }
    }

    private func leadVibratoMultiplier(timbre: SoundState.LeadTimbre) -> Double {
        guard timbre == .violin else {
            return 1
        }

        let vibratoFade = clamp((leadBowAge - 0.14) * 5.5, lower: 0, upper: 1)
        let depth = (0.002 + currentBrightness * 0.0032) * vibratoFade
        return 1 + sin(leadVibratoPhase) * depth
    }

    private func advanceLeadModulation(timbre: SoundState.LeadTimbre) {
        guard timbre == .violin else {
            return
        }

        let vibratoRate = 4.6 + currentBrightness * 1.4
        leadVibratoPhase = wrappedPhase(leadVibratoPhase + twoPi * vibratoRate / sampleRate)
    }

    private func updateLeadArticulation(timbre: SoundState.LeadTimbre, frequency: Double) {
        defer {
            lastLeadTimbre = timbre
        }

        guard timbre == .violin else {
            return
        }

        let desired = sanitizedFrequency(frequency)
        let changedTimbre = lastLeadTimbre != timbre
        let changedPitch = desired > 0 && latchedLeadFrequency > 0 && abs(log2(desired / latchedLeadFrequency)) > 0.035
        if changedTimbre || changedPitch || leadStepAge < 1 / sampleRate {
            leadBowAge = 0
        }
    }

    private func violinBody(input: Double) -> Double {
        violinBodyLow = resonantLowpass(current: violinBodyLow, input: input, coefficient: 0.035)
        violinBodyMid = resonantLowpass(current: violinBodyMid, input: input - violinBodyLow, coefficient: 0.095)
        violinBodyHigh = resonantLowpass(current: violinBodyHigh, input: input - violinBodyMid, coefficient: 0.28)

        let body = violinBodyLow * 0.62 + violinBodyMid * 1.32 + violinBodyHigh * 0.28
        return tanh(body * 1.55)
    }

    private func advanceGroove(
        target: AudioOrchestraTarget,
        desiredLeadFrequency: Double,
        drumVoices: inout [DrumVoice]
    ) {
        guard target.grooveIsActive else {
            return
        }

        let step = Int(floor(grooveBeatPosition * 4)) % 16
        if step != lastGrooveStep {
            triggerLead(for: step, desiredLeadFrequency: desiredLeadFrequency)
            triggerDrums(for: step, drumVoices: &drumVoices)
            lastGrooveStep = step
        }

        let beatsPerSecond = target.tempoBPM / 60
        grooveBeatPosition = (grooveBeatPosition + beatsPerSecond / sampleRate).truncatingRemainder(dividingBy: 4)
    }

    private func triggerLead(for step: Int, desiredLeadFrequency: Double) {
        let syncopatedStep = currentHatIntensity > 0.62 && (step == 3 || step == 7 || step == 11 || step == 15)
        guard step.isMultiple(of: 2) || syncopatedStep else {
            return
        }

        latchedLeadFrequency = sanitizedFrequency(desiredLeadFrequency)
        leadStepAge = 0
    }

    private func grooveLeadFrequency(fallback frequency: Double, target: AudioOrchestraTarget) -> Double {
        guard target.grooveIsActive else {
            latchedLeadFrequency = 0
            return frequency
        }

        if latchedLeadFrequency <= 0 {
            latchedLeadFrequency = sanitizedFrequency(frequency)
        }

        return latchedLeadFrequency > 0 ? latchedLeadFrequency : frequency
    }

    private func grooveLeadEnvelope(target: AudioOrchestraTarget) -> Double {
        guard target.grooveIsActive else {
            return 1
        }

        let attack = min(1, leadStepAge * 90)
        let decayRate = 12 + currentHatIntensity * 9
        let body = 0.16 + 0.84 * exp(-leadStepAge * decayRate)
        return attack * body
    }

    private func triggerDrums(for step: Int, drumVoices: inout [DrumVoice]) {
        if step == 0 || (step == 8 && currentKickIntensity > 0.45) || (step == 6 && currentKickIntensity > 0.78) {
            drumVoices.append(.kick(amplitude: currentKickIntensity))
        }

        if (step == 4 || step == 12), currentSnareIntensity > 0.18 {
            drumVoices.append(.snare(amplitude: currentSnareIntensity * 0.58))
        }

        let isEighth = step.isMultiple(of: 2)
        let isFunkySixteenth = !isEighth && currentHatIntensity > 0.68 && (step == 3 || step == 7 || step == 11 || step == 15)
        if currentHatIntensity > 0.12, isEighth || isFunkySixteenth {
            let accent = step.isMultiple(of: 4) ? 1.0 : 0.68
            drumVoices.append(.hat(amplitude: currentHatIntensity * accent))
        }

        if drumVoices.count > maxDrumVoices {
            drumVoices.removeFirst(drumVoices.count - maxDrumVoices)
        }
    }

    private func renderDrumSample(drumVoices: inout [DrumVoice]) -> Double {
        var sample = 0.0

        for index in drumVoices.indices {
            let age = drumVoices[index].age
            switch drumVoices[index].kind {
            case .kick:
                let envelope = exp(-age * 18)
                let frequency = 44 + 96 * exp(-age * 28)
                sample += sin(drumVoices[index].phase) * drumVoices[index].amplitude * envelope * 0.82
                drumVoices[index].phase = wrappedPhase(drumVoices[index].phase + twoPi * frequency / sampleRate)
            case .snare:
                let envelope = exp(-age * 24)
                let noise = nextNoise()
                let tone = sin(drumVoices[index].phase) * 0.18
                sample += (noise * 0.82 + tone) * drumVoices[index].amplitude * envelope * 0.58
                drumVoices[index].phase = wrappedPhase(drumVoices[index].phase + twoPi * 185 / sampleRate)
            case .hat:
                let envelope = exp(-age * 72)
                let noise = nextNoise()
                let highPassedNoise = noise - previousHatNoise
                previousHatNoise = noise
                sample += highPassedNoise * drumVoices[index].amplitude * envelope * 0.24
            }

            drumVoices[index].age += 1 / sampleRate
        }

        return sample
    }

    private func nextNoise() -> Double {
        noiseState = noiseState &* 6_364_136_223_846_793_005 &+ 1
        let value = Double((noiseState >> 33) & 0xFFFF_FFFF) / Double(UInt32.max)
        return value * 2 - 1
    }
}

private struct AccentVoice {
    var frequency: Double
    var amplitude: Double
    var phase: Double
    var age: Double
}

private struct DrumVoice {
    enum Kind {
        case kick
        case snare
        case hat
    }

    var kind: Kind
    var amplitude: Double
    var phase: Double
    var age: Double
    var duration: Double

    static func kick(amplitude: Double) -> DrumVoice {
        DrumVoice(kind: .kick, amplitude: sanitizedUnit(amplitude), phase: 0, age: 0, duration: 0.42)
    }

    static func snare(amplitude: Double) -> DrumVoice {
        DrumVoice(kind: .snare, amplitude: sanitizedUnit(amplitude), phase: 0, age: 0, duration: 0.32)
    }

    static func hat(amplitude: Double) -> DrumVoice {
        DrumVoice(kind: .hat, amplitude: sanitizedUnit(amplitude), phase: 0, age: 0, duration: 0.12)
    }
}

private struct AudioOrchestraTarget {
    var rootFrequency: Double
    var amplitude: Double
    var voiceCount: Int
    var intervalSemitones: [Int]
    var richness: Double
    var motion: Double
    var detuneCents: Double
    var grooveIsActive: Bool
    var kickIntensity: Double
    var snareIntensity: Double
    var hatIntensity: Double
    var clapTriggered: Bool
    var tempoBPM: Double

    init(_ state: ScreenOrchestraState) {
        guard state.isActive || state.groove.isActive else {
            self = .silence
            return
        }

        rootFrequency = sanitizedFrequency(state.rootFrequency)
        amplitude = min(sanitizedUnit(state.amplitude), 0.24)
        voiceCount = clamp(state.voiceCount, lower: 0, upper: maxOrchestraVoices)
        intervalSemitones = state.intervalSemitones
        richness = sanitizedUnit(state.richness)
        motion = min(sanitizedUnit(state.motion), 0.12)
        detuneCents = clamp(state.detuneCents.isFinite ? state.detuneCents : 0, lower: 0, upper: 3)
        grooveIsActive = state.groove.isActive
        kickIntensity = sanitizedUnit(state.groove.kickIntensity)
        snareIntensity = sanitizedUnit(state.groove.snareIntensity)
        hatIntensity = sanitizedUnit(state.groove.hatIntensity)
        clapTriggered = state.groove.clapTriggered
        tempoBPM = clamp(state.groove.tempoBPM.isFinite ? state.groove.tempoBPM : 108, lower: 90, upper: 150)
    }

    private init(
        rootFrequency: Double,
        amplitude: Double,
        voiceCount: Int,
        intervalSemitones: [Int],
        richness: Double,
        motion: Double,
        detuneCents: Double,
        grooveIsActive: Bool,
        kickIntensity: Double,
        snareIntensity: Double,
        hatIntensity: Double,
        clapTriggered: Bool,
        tempoBPM: Double
    ) {
        self.rootFrequency = rootFrequency
        self.amplitude = amplitude
        self.voiceCount = voiceCount
        self.intervalSemitones = intervalSemitones
        self.richness = richness
        self.motion = motion
        self.detuneCents = detuneCents
        self.grooveIsActive = grooveIsActive
        self.kickIntensity = kickIntensity
        self.snareIntensity = snareIntensity
        self.hatIntensity = hatIntensity
        self.clapTriggered = clapTriggered
        self.tempoBPM = tempoBPM
    }

    static let silence = AudioOrchestraTarget(
        rootFrequency: 0,
        amplitude: 0,
        voiceCount: 0,
        intervalSemitones: [],
        richness: 0,
        motion: 0,
        detuneCents: 0,
        grooveIsActive: false,
        kickIntensity: 0,
        snareIntensity: 0,
        hatIntensity: 0,
        clapTriggered: false,
        tempoBPM: 108
    )
}

private let twoPi = Double.pi * 2
private let maxAccentVoices = 5
private let maxOrchestraVoices = 3
private let maxDrumVoices = 24
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

private func softTriangle(_ phase: Double) -> Double {
    asin(sin(phase)) * (2 / Double.pi)
}

private func softSaw(_ phase: Double) -> Double {
    (
        sin(phase)
            + sin(phase * 2) * 0.42
            + sin(phase * 3) * 0.22
            + sin(phase * 4) * 0.12
    ) / 1.76
}

private func resonantLowpass(current: Double, input: Double, coefficient: Double) -> Double {
    current + (input - current) * coefficient
}

private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
}

private func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
    min(max(value, lower), upper)
}
