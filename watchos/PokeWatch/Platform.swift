// watchOS stand-ins for the firmware's hardware: NVS (Preferences), the
// ES8311 speaker and the AXP2101 battery gauge.
import AVFoundation
import Foundation
import WatchKit

let PREFS_SUITE = "tamapoke"

final class DefaultsStore: Store {
    private let d = UserDefaults(suiteName: PREFS_SUITE) ?? .standard

    func getInt(_ key: String, _ def: Int) -> Int { d.object(forKey: key) as? Int ?? def }
    func putInt(_ key: String, _ v: Int) { d.set(v, forKey: key) }
    func getBool(_ key: String, _ def: Bool) -> Bool { d.object(forKey: key) as? Bool ?? def }
    func putBool(_ key: String, _ v: Bool) { d.set(v, forKey: key) }
    func getString(_ key: String, _ def: String) -> String { d.string(forKey: key) ?? def }
    func putString(_ key: String, _ v: String) { d.set(v, forKey: key) }
    func has(_ key: String) -> Bool { d.object(forKey: key) != nil }
    func clear() { d.removePersistentDomain(forName: PREFS_SUITE) }
    func flush() {}
}

/// Square-wave sound effects, same notes as the firmware's audio.cpp.
final class Sound {
    private struct Note { let f: Int; let ms: Int }

    private static let table: [Sfx: [Note]] = [
        .tap: [Note(f: 880, ms: 35)],
        .eat: [Note(f: 660, ms: 45), Note(f: 0, ms: 12), Note(f: 660, ms: 45)],
        .play: [Note(f: 784, ms: 45), Note(f: 988, ms: 60)],
        .heart: [Note(f: 1047, ms: 55), Note(f: 1319, ms: 90)],
        .hatch: [Note(f: 523, ms: 80), Note(f: 659, ms: 80), Note(f: 784, ms: 110), Note(f: 1047, ms: 170)],
        .evolve: [Note(f: 523, ms: 80), Note(f: 659, ms: 80), Note(f: 784, ms: 80), Note(f: 1047, ms: 90), Note(f: 1319, ms: 230)],
        .medal: [Note(f: 784, ms: 70), Note(f: 0, ms: 25), Note(f: 784, ms: 70), Note(f: 0, ms: 25), Note(f: 1047, ms: 200)],
        .deny: [Note(f: 300, ms: 110), Note(f: 200, ms: 170)],
        .bye: [Note(f: 784, ms: 150), Note(f: 659, ms: 150), Note(f: 523, ms: 280)],
        .level: [Note(f: 784, ms: 70), Note(f: 1047, ms: 130)],
    ]

    private let rate = 22050.0
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var pcm: [Sfx: AVAudioPCMBuffer] = [:]
    private var started = false

    var enabled: Bool {
        didSet { UserDefaults(suiteName: PREFS_SUITE)?.set(enabled, forKey: "snd") }
    }

    init() {
        enabled = UserDefaults(suiteName: PREFS_SUITE)?.object(forKey: "snd") as? Bool ?? true
        format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    private func render(_ notes: [Note]) -> AVAudioPCMBuffer? {
        let total = notes.reduce(0) { $0 + $1.ms } * Int(rate) / 1000
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
              let out = buf.floatChannelData?[0] else { return nil }
        var i = 0
        for n in notes {
            let len = n.ms * Int(rate) / 1000
            let half = n.f > 0 ? Int(rate) / (2 * n.f) : 0
            for k in 0..<len where i < total {
                out[i] = n.f == 0 ? 0 : ((k / half) % 2 == 0 ? 0.15 : -0.15)
                i += 1
            }
        }
        buf.frameLength = AVAudioFrameCount(i)
        return buf
    }

    private func start() -> Bool {
        if started && engine.isRunning { return true }
        do {
            // ambient: respects silent mode and mixes with whatever else is playing
            try AVAudioSession.sharedInstance().setCategory(.ambient)
            try engine.start()
            started = true
        } catch {
            started = false
        }
        return started
    }

    func play(_ id: Sfx) {
        guard enabled, start() else { return }
        if pcm[id] == nil, let notes = Sound.table[id] { pcm[id] = render(notes) }
        guard let buf = pcm[id] else { return }
        player.scheduleBuffer(buf, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}

final class Battery {
    private var cachedAt = 0
    private(set) var percent = -1
    private(set) var charging = false

    init() { WKInterfaceDevice.current().isBatteryMonitoringEnabled = true }

    func poll(_ now: Int) {
        if now - cachedAt < 10_000 && percent >= 0 { return }
        cachedAt = now
        let dev = WKInterfaceDevice.current()
        percent = dev.batteryLevel >= 0 ? Int(dev.batteryLevel * 100) : -1
        charging = dev.batteryState == .charging || dev.batteryState == .full
    }
}

enum Haptics {
    static func longPress() { WKInterfaceDevice.current().play(.click) }
}
