@testable import SoundaCore

#if canImport(XCTest)
import XCTest

final class SoundMapperTests: XCTestCase {
    func testDefaultMapperMapsBasicCursorFrameWithoutCrashing() {
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

        XCTAssertFalse(state.accentTriggered)
    }
}
#else
func defaultMapperMapsBasicCursorFrameWithoutCrashing() {
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

    precondition(!state.accentTriggered)
}
#endif
