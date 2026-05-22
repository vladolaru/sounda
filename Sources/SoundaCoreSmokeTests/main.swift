import Foundation
import SoundaCore

let mapper = SoundMapper(settings: .default)
let frame = CursorFrame(
    timestamp: 0,
    normalizedX: 0.5,
    normalizedY: 0.5,
    speed: 0,
    acceleration: 0,
    directionAngle: 0
)

let state = mapper.map(frame)
let expectedState = SoundState.silence

guard state == expectedState else {
    let message = "SoundaCore smoke test failed: expected \(expectedState), got \(state)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}

print("SoundaCore smoke test passed")
