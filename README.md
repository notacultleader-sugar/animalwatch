# PokeWatch

[TamaPoke](https://github.com/socquique/TamaPoke) (a Pokémon tamagotchi for an
ESP32 round display) ported to smartwatches:

- **Wear OS** (Samsung Galaxy Watch 4 and newer, Pixel Watch, any round Wear OS 3+ watch): `wearos/`
- **Garmin Connect IQ** (Fenix 7/8, Epix 2, Forerunner 255/265/955/965, Venu 2/3, Vivoactive 5): `garmin/`
- **Apple Watch** (watchOS 10+, SwiftUI): `watchos/`, see [watchos/README.md](watchos/README.md)

The gameplay, screens and flow follow TamaPoke v1.18: egg and starter choice,
hunger/joy/energy/hygiene, poops, sleep and lights, berries and candy, the ball
minigame, the training bag, stats and medals, daily streaks, evolution (with
the choice to keep the form), shinies, egg rarity, the 151-entry Pokédex, and
the farewell / runaway / release endings.

## Personal use only

The code is MIT. The Pokémon sprites are not included: they're fan-made
(PMD SpriteCollab, CC BY-NC 4.0) and Pokémon is Nintendo's. Like TamaPoke,
you download them on your own computer, and the build you make is for your own
watch. Don't publish it on the Play Store, the Connect IQ Store or the App Store
(the Apple Watch build goes out through TestFlight internal testing or Ad Hoc only).

```sh
pip install pillow
python3 tools/fetch_sprites.py            # all 151 (takes a few minutes)
python3 tools/fetch_sprites.py 1 4 7 25   # or just a few, for a quick test
```

This fills `wearos/app/src/main/assets/mons/`, `watchos/mons/` and `garmin/sprites/`. Without
sprites the apps still run and show a "?" where the Pokémon would be.
`python3 tools/garmin_sprites.py --empty` puts the Garmin placeholders back.

## Wear OS

Needs Android Studio (or the Android SDK with JDK 17+).

```sh
cd wearos
./gradlew :game:test          # game logic tests
./gradlew :app:assembleRelease
```

Install on the watch: turn on Developer options and ADB debugging (Wi-Fi) on
the watch, then `adb connect <watch-ip>:<port>` and
`adb install app/build/outputs/apk/release/app-release.apk`.

Controls are TamaPoke's touch layout: tap the pet to pet it, the four bottom
buttons (food, play, light, bath), swipe up for the stats card, down for
settings, sideways for the Pokédex, hold the pet for 3 s to release it. The
rotating bezel/crown scrolls the Pokédex and card pages. The game's clock is
the watch's clock.

## Garmin

Needs the Connect IQ SDK (via the SDK Manager) and a developer key; the VS
Code "Monkey C" extension is the easiest way.

```sh
cd garmin
monkeyc -f monkey.jungle -d fenix7 -o bin/PokeWatch.prg -y /path/to/developer_key
```

Sideload: plug in the watch and copy the `.prg` into `GARMIN/APPS/`. Add
other models to `manifest.xml` (any watch with a round screen and API 3.2+).

On touch watches the controls match Wear OS. On button-only watches, START
opens an action menu (feed, play, bath, pet, lights, stats, Pokédex,
settings, release) and confirms dialogs, UP/DOWN pick items and pages, BACK
closes things.

Differences from the original, because of watch memory: English only, only
the idle animation per species (eating is a little wiggle), no shiny palettes
in the art, and unseen Pokédex entries show their number instead of a
silhouette.

## Layout

| Path | What |
| --- | --- |
| `wearos/game` | Game logic (Kotlin, port of `pet.cpp`) with tests |
| `wearos/app` | Watch UI (port of `TamaPoke.ino`), Canvas-drawn at 466×466 and scaled |
| `garmin/source` | Monkey C port of the same game and UI |
| `watchos/` | Swift/SwiftUI port of the same game and UI, with tests |
| `codemagic.yaml` | Codemagic build of the Apple Watch app to TestFlight |
| `tools/gen_tables.py` | Generates species/text tables for both apps from TamaPoke's sources |
| `tools/pack_pmd.py`, `make_thumbs.py` | TamaPoke's sprite packers (MIT) |
| `tools/fetch_sprites.py`, `garmin_sprites.py` | Personal sprite download and conversion |

## Credits

Game design and original code: [TamaPoke](https://github.com/socquique/TamaPoke)
by Quique Tortosa (MIT). Sprites: [PMD SpriteCollab](https://sprites.pmdcollab.org/)
contributors (CC BY-NC 4.0). Pokémon © Nintendo / Creatures / Game Freak /
The Pokémon Company. This is an unofficial fan project.
