import Foundation

public struct ScreenSampleFeatures: Equatable, Sendable {
    public var sampleCount: Int
    public var meanBrightness: Double
    public var meanSaturation: Double
    public var meanHue: Double
    public var contrast: Double
    public var warmth: Double

    public init(
        sampleCount: Int,
        meanBrightness: Double,
        meanSaturation: Double,
        meanHue: Double,
        contrast: Double,
        warmth: Double
    ) {
        self.sampleCount = sampleCount
        self.meanBrightness = meanBrightness
        self.meanSaturation = meanSaturation
        self.meanHue = meanHue
        self.contrast = contrast
        self.warmth = warmth
    }
}

public struct ScreenSampleFeatureAccumulator: Sendable {
    private var sampleCount = 0
    private var brightnessSum = 0.0
    private var saturationSum = 0.0
    private var hueXSum = 0.0
    private var hueYSum = 0.0
    private var redSum = 0.0
    private var blueSum = 0.0
    private var minBrightness = 1.0
    private var maxBrightness = 0.0

    public init() {}

    public mutating func add(red: Double, green: Double, blue: Double) {
        let red = clamp(red, lower: 0, upper: 1)
        let green = clamp(green, lower: 0, upper: 1)
        let blue = clamp(blue, lower: 0, upper: 1)
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let brightness = (red + green + blue) / 3
        let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
        let hue = hueUnit(red: red, green: green, blue: blue, minimum: minimum, maximum: maximum)

        sampleCount += 1
        brightnessSum += brightness
        saturationSum += saturation
        hueXSum += cos(hue * .pi * 2)
        hueYSum += sin(hue * .pi * 2)
        redSum += red
        blueSum += blue
        minBrightness = min(minBrightness, brightness)
        maxBrightness = max(maxBrightness, brightness)
    }

    public func finish() -> ScreenSampleFeatures {
        guard sampleCount > 0 else {
            return ScreenSampleFeatures(
                sampleCount: 0,
                meanBrightness: 0,
                meanSaturation: 0,
                meanHue: 0,
                contrast: 0,
                warmth: 0
            )
        }

        let count = Double(sampleCount)
        let hue = atan2(hueYSum, hueXSum) / (.pi * 2)
        return ScreenSampleFeatures(
            sampleCount: sampleCount,
            meanBrightness: brightnessSum / count,
            meanSaturation: saturationSum / count,
            meanHue: hue >= 0 ? hue : hue + 1,
            contrast: maxBrightness - minBrightness,
            warmth: clamp((redSum - blueSum) / count, lower: -1, upper: 1)
        )
    }
}

private func hueUnit(
    red: Double,
    green: Double,
    blue: Double,
    minimum: Double,
    maximum: Double
) -> Double {
    let delta = maximum - minimum
    guard delta > 0 else {
        return 0
    }

    let hueDegrees: Double
    if maximum == red {
        hueDegrees = 60 * (((green - blue) / delta).truncatingRemainder(dividingBy: 6))
    } else if maximum == green {
        hueDegrees = 60 * (((blue - red) / delta) + 2)
    } else {
        hueDegrees = 60 * (((red - green) / delta) + 4)
    }

    let normalizedDegrees = hueDegrees >= 0 ? hueDegrees : hueDegrees + 360
    return normalizedDegrees / 360
}

private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value.isFinite ? value : lower, lower), upper)
}
