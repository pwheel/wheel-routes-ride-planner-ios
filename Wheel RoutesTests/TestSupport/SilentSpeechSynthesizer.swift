//
//  SilentSpeechSynthesizer.swift
//  Wheel RoutesTests
//

import AVFoundation
import FerrostarCore

/// A `SpeechSynthesizer` that never speaks, for `NavigationViewModel` tests.
///
/// The real default, `AVSpeechSynthesizer()`, is created on the main actor and can
/// block it for seconds on a cold simulator (CI). Because Swift Testing runs suites
/// concurrently on the main actor, that stall starved unrelated tests past their
/// `waitUntil` deadlines on CI. Speech output itself is never under test.
final class SilentSpeechSynthesizer: SpeechSynthesizer {
    private(set) var isSpeaking = false

    func speak(_: AVSpeechUtterance) {}

    @discardableResult
    func stopSpeaking(at _: AVSpeechBoundary) -> Bool { true }
}
