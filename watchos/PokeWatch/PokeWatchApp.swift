// The watch app: one full-screen Canvas redrawn ~10 times a second (the
// firmware's frame pacing), with touch and the Digital Crown fed to Game.
import SwiftUI

@main
struct PokeWatchApp: App {
    private let game = Game(sound: Sound(), battery: Battery())

    var body: some Scene {
        WindowGroup {
            GameScreen(game: game)
        }
    }
}

struct GameScreen: View {
    let game: Game
    @Environment(\.scenePhase) private var scenePhase
    @State private var pressing = false
    @State private var crown = 0.0
    @State private var crownStep = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.085)) { timeline in
            Canvas { ctx, size in
                _ = timeline.date
                game.draw(ctx, size)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    if !pressing {
                        pressing = true
                        game.touchDown(v.startLocation)
                    }
                    game.touchMove(v.location)
                }
                .onEnded { _ in
                    pressing = false
                    game.touchUp()
                }
        )
        .focusable()
        .focusEffectDisabled()
        .digitalCrownRotation($crown, from: -1_000_000, through: 1_000_000, by: 1,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, value in
            let step = Int(value.rounded())
            if step != crownStep {
                game.onCrown(step > crownStep ? -1 : 1)
                crownStep = step
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: game.onResumeGame()
            default: game.onPauseGame()
            }
        }
    }
}
