import AVFoundation

@MainActor
final class TypingSoundPlayer {
    static let shared = TypingSoundPlayer()

    private var preparedSound: TypingSound?
    private var regularPlayers: [AVAudioPlayer] = []
    private var deepPlayers: [AVAudioPlayer] = []

    func prepare(_ sound: TypingSound) {
        guard preparedSound != sound else { return }
        regularPlayers = makePlayers(for: sound, deep: false)
        deepPlayers = makePlayers(for: sound, deep: true)
        preparedSound = sound
    }

    func play(_ sound: TypingSound, volume: Double, deep: Bool = false) {
        guard volume > 0, volume.isFinite else { return }
        prepare(sound)
        let players = deep ? deepPlayers : regularPlayers
        guard let player = players.first(where: { !$0.isPlaying }) ?? players.first else { return }
        player.volume = Float(min(volume, 1))
        player.currentTime = 0
        if !player.play() {
            Logger.typingSound.warning("Could not play the typing sound")
        }
    }

    private func makePlayers(for sound: TypingSound, deep: Bool) -> [AVAudioPlayer] {
        guard let url = sound.resourceURL(deep: deep) else {
            Logger.typingSound.error("Missing typing sound asset: \(sound.rawValue)")
            return []
        }
        do {
            return try (0..<2).map { _ in
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                return player
            }
        } catch {
            Logger.typingSound.error("Could not load typing sound: \(error.localizedDescription)")
            return []
        }
    }
}
