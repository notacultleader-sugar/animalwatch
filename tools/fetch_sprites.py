#!/usr/bin/env python3
"""Download and pack the Pokémon sprites for YOUR OWN build of the watch apps.

The sprites come from PMD SpriteCollab (CC BY-NC 4.0, Pokémon (c) Nintendo /
Game Freak / The Pokémon Company). They are for personal, non-commercial use
only, so this repository does not include them: run this script on your own
computer, the same way TamaPoke asks its users to.

  pip install pillow
  python3 tools/fetch_sprites.py            # all 151, normal + shiny
  python3 tools/fetch_sprites.py 1 4 7 25   # just some (handy for a quick test)

Writes:
  wearos/app/src/main/assets/mons/   pNNN.bin, psNNN.bin, thumbs.bin
  garmin/sprites/                    PNG strips + SpriteIds.mc for the Garmin build
"""
import os
import shutil
import subprocess
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
PACKED = os.path.join(TOOLS, 'sdcard', 'mons')
WEAR = os.path.join(ROOT, 'wearos', 'app', 'src', 'main', 'assets', 'mons')


def main():
    args = sys.argv[1:]
    subprocess.run([sys.executable, os.path.join(TOOLS, 'pack_pmd.py'), *args], check=True)
    # thumbnails need every packed file that exists; missing ones are skipped
    subprocess.run([sys.executable, os.path.join(TOOLS, 'make_thumbs.py')], check=True)

    os.makedirs(WEAR, exist_ok=True)
    n = 0
    for name in sorted(os.listdir(PACKED)):
        if name.endswith('.bin'):
            shutil.copy2(os.path.join(PACKED, name), os.path.join(WEAR, name))
            n += 1
    print(f'Wear OS: copied {n} files to {os.path.relpath(WEAR, ROOT)}')

    garmin = os.path.join(TOOLS, 'garmin_sprites.py')
    if os.path.exists(garmin):
        subprocess.run([sys.executable, garmin], check=True)


if __name__ == '__main__':
    main()
