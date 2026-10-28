#!/usr/bin/env python3
"""Turn TamaPoke's C tables (dex.h, species.h, i18n.cpp) into source for the
watch ports, so game data stays identical to the original firmware.

  python3 tools/gen_tables.py <path-to-TamaPoke-checkout>

Writes:
  wearos/game/src/main/kotlin/com/pokewatch/game/Tables.kt
  garmin/source/Tables.mc
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ESC = {'n': '\n', 't': '\t', '"': '"', '\\': '\\', "'": "'"}


def c_string(body):
    """Decode a C string literal body. Octal escapes are CP437 bytes (the
    firmware's bitmap font); everything else is UTF-8 source text."""
    out = bytearray()
    i = 0
    raw = body.encode('utf-8')
    while i < len(raw):
        ch = raw[i]
        if ch == 0x5C:  # backslash
            nxt = chr(raw[i + 1])
            if nxt in '01234567':
                j = i + 1
                while j < len(raw) and j < i + 4 and chr(raw[j]) in '01234567':
                    j += 1
                out += bytes([int(raw[i + 1:j], 8)]).decode('cp437').encode('utf-8')
                i = j
                continue
            out += ESC[nxt].encode('utf-8')
            i += 2
            continue
        out.append(ch)
        i += 1
    return out.decode('utf-8')


STR_RE = re.compile(r'"((?:[^"\\]|\\.)*)"|\bnullptr\b')


def literals(block):
    return [c_string(m.group(1)) if m.group(1) is not None or m.group(0) != 'nullptr' else None
            for m in STR_RE.finditer(block)]


def array_block(src, name):
    m = re.search(re.escape(name) + r'\s*\[[^\]]*\](?:\s*\[[^\]]*\])?\s*=\s*\{', src)
    if not m:
        raise SystemExit(f'{name} not found')
    depth, i = 1, m.end()
    in_str = False
    while depth:
        c = src[i]
        if in_str:
            if c == '\\':
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
        elif src.startswith('//', i):
            i = src.index('\n', i)
        i += 1
    return src[m.end():i - 1]


def strip_comments(block):
    out, i, in_str = [], 0, False
    while i < len(block):
        c = block[i]
        if in_str:
            out.append(c)
            if c == '\\':
                out.append(block[i + 1])
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            out.append(c)
        elif block.startswith('//', i):
            i = block.index('\n', i)
            continue
        else:
            out.append(c)
        i += 1
    return ''.join(out)


def rgb565_to_argb(v):
    r = (v >> 11) & 31
    g = (v >> 5) & 63
    b = v & 31
    return 0xFF000000 | ((r * 255 // 31) << 16) | ((g * 255 // 63) << 8) | (b * 255 // 31)


def parse(src_dir):
    dex_src = open(os.path.join(src_dir, 'dex.h'), encoding='utf-8').read()
    spe_src = open(os.path.join(src_dir, 'species.h'), encoding='utf-8').read()
    i18n_src = open(os.path.join(src_dir, 'i18n.cpp'), encoding='utf-8').read()
    i18n_h = open(os.path.join(src_dir, 'i18n.h'), encoding='utf-8').read()

    rar = {'R_EVO': 0, 'R_COMUN': 1, 'R_RARO': 2, 'R_LEGENDARIO': 3}
    dex = []
    for m in re.finditer(r'\{\s*"([^"]*)",\s*(\d+),\s*(\d+),\s*(\w+),\s*(0x[0-9A-Fa-f]+),'
                         r'\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\s*\}', array_block(dex_src, 'DEX_TBL')):
        name, evo, lvl, r, acc, hp, atk, df, spe, bio = m.groups()
        dex.append(dict(name=name, evo=int(evo), lvl=int(lvl), rar=int(r) if r.isdigit() else rar[r],
                        acc=rgb565_to_argb(int(acc, 16)), hp=int(hp), atk=int(atk), df=int(df),
                        spe=int(spe), bio=int(bio)))
    assert len(dex) == 152, len(dex)
    names = {}
    for lang in ('FR', 'DE', 'JA', 'KO'):
        lst = literals(strip_comments(array_block(dex_src, f'DEX_NAME_{lang}')))
        assert len(lst) == 152, (lang, len(lst))
        names[lang] = lst

    colors = {}
    for m in re.finditer(r"case '(.)': return (0x[0-9A-Fa-f]+);", spe_src):
        colors[m.group(1)] = rgb565_to_argb(int(m.group(2), 16))
    sprites = {}
    for m in re.finditer(r'static const char\* const (SPR_\w+)\[(\d+)\] = \{(.*?)\};', spe_src, re.S):
        sprites[m.group(1)] = literals(m.group(3))
    flash = []
    for m in re.finditer(r'\{\s*"(\w+)",\s*TYPE_\w+,\s*(SPR_\w+),\s*(\d+),\s*(-?\w+),\s*(\d+),'
                         r'\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(0x\w+),\s*(0x\w+)\s*\}', spe_src):
        flash.append(dict(sprite=m.group(2), scale=int(m.group(3)), eyeRow=int(m.group(6)),
                          eyeL=int(m.group(7)), eyeR=int(m.group(8)), mouthRow=int(m.group(9)),
                          mouthCol=int(m.group(10)), body=rgb565_to_argb(int(m.group(11), 16))))
    ui = {m.group(1): rgb565_to_argb(int(m.group(2), 16))
          for m in re.finditer(r'#define (UI_\w+) (0x[0-9A-Fa-f]+)', spe_src)}

    ids = re.search(r'enum StrId : uint8_t \{(.*?)STR_COUNT', i18n_h, re.S).group(1)
    ids = re.findall(r'\b(S_\w+)\b', strip_comments(ids))
    langs = re.search(r'enum Lang : uint8_t \{(.*?)LANG_COUNT', i18n_h, re.S).group(1)
    langs = re.findall(r'LANG_(\w\w)\b', langs)
    rows = []
    block = strip_comments(array_block(i18n_src, 'STRINGS'))
    for sub in re.findall(r'\{(.*?)\}', block, re.S):
        row = literals(sub)
        assert len(row) == len(ids), (len(row), len(ids))
        rows.append(row)
    assert len(rows) == len(langs)
    medals = {}
    for k in ('MED_NAME', 'MED_LBL', 'MED_DSC'):
        medals[k] = [literals(s) for s in re.findall(r'\{(.*?)\}', strip_comments(array_block(i18n_src, k)), re.S)]
    return dict(dex=dex, names=names, colors=colors, sprites=sprites, flash=flash, ui=ui,
                ids=ids, langs=langs, rows=rows, medals=medals)


def kq(s):
    if s is None:
        return 'null'
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('$', '\\$').replace('\n', '\\n') + '"'


def emit_kotlin(t):
    o = ['// GENERATED by tools/gen_tables.py from TamaPoke (MIT) - do not edit.',
         'package com.pokewatch.game', '']
    d = t['dex']
    o.append('object DexTables {')
    o.append('    val NAME = arrayOf(' + ', '.join(kq(e['name']) for e in d) + ')')
    for key, col in (('evo', 'EVOLVES_TO'), ('lvl', 'EVOLVE_LEVEL'), ('rar', 'RARITY'), ('hp', 'B_HP'),
                     ('atk', 'B_ATK'), ('df', 'B_DEF'), ('spe', 'B_SPE'), ('bio', 'BIOME')):
        o.append(f'    val {col} = intArrayOf(' + ', '.join(str(e[key]) for e in d) + ')')
    o.append('    val ACCENT = intArrayOf(' + ', '.join(f'0x{e["acc"]:08X}.toInt()' for e in d) + ')')
    for lang, lst in t['names'].items():
        o.append(f'    val NAME_{lang} = arrayOf<String?>(' + ', '.join(kq(s) for s in lst) + ')')
    o.append('}')
    o.append('')
    o.append('object SpriteTables {')
    o.append('    val COLORS: Map<Char, Int> = mapOf(' +
             ', '.join(f"'{c}' to 0x{v:08X}.toInt()" for c, v in t['colors'].items()) + ')')
    for k, rows in t['sprites'].items():
        o.append(f'    val {k} = arrayOf(' + ', '.join(kq(r) for r in rows) + ')')
    o.append('    class Flash(val sprite: Array<String>, val scale: Int, val eyeRow: Int, val eyeL: Int, '
             'val eyeR: Int, val mouthRow: Int, val mouthCol: Int, val body: Int)')
    o.append('    // dex 1..9 -> the firmware\'s built-in fallback sprites')
    order = [3, 4, 5, 0, 1, 2, 6, 7, 8]
    fl = t['flash']
    o.append('    val FLASH = arrayOf(' + ', '.join(
        f'Flash({fl[i]["sprite"]}, {fl[i]["scale"]}, {fl[i]["eyeRow"]}, {fl[i]["eyeL"]}, {fl[i]["eyeR"]}, '
        f'{fl[i]["mouthRow"]}, {fl[i]["mouthCol"]}, 0x{fl[i]["body"]:08X}.toInt())' for i in order) + ')')
    o.append('}')
    o.append('')
    o.append('object Ui {')
    for k, v in t['ui'].items():
        o.append(f'    const val {k[3:]} = 0x{v:08X}.toInt()')
    o.append('}')
    o.append('')
    o.append('enum class S { ' + ', '.join(i[2:] for i in t['ids']) + ' }')
    o.append('')
    o.append('object StringTables {')
    o.append('    val LANG_CODES = arrayOf(' + ', '.join(kq(l) for l in t['langs']) + ')')
    o.append('    val STRINGS = arrayOf(')
    for row in t['rows']:
        o.append('        arrayOf(' + ', '.join(kq(s) for s in row) + '),')
    o.append('    )')
    for k, rows in t['medals'].items():
        o.append(f'    val {k} = arrayOf(')
        for row in rows:
            o.append('        arrayOf(' + ', '.join(kq(s) for s in row) + '),')
        o.append('    )')
    o.append('}')
    return '\n'.join(o) + '\n'


def mq(s):
    if s is None:
        return 'null'
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def garmin_fmt(s):
    """C printf (%s %u %lu %d) -> Monkey C Lang.format ($1$ $2$ ...)."""
    n = [0]

    def rep(m):
        n[0] += 1
        return f'${n[0]}$'
    return re.sub(r'%l?[sud]', rep, s)


def emit_monkeyc(t):
    """Garmin only gets English text and the non-name tables (memory is tight)."""
    d = t['dex']
    en = t['langs'].index('EN')
    o = ['// GENERATED by tools/gen_tables.py from TamaPoke (MIT) - do not edit.',
         'import Toybox.Lang;', '', 'module Tables {']
    o.append('    const NAME = [' + ', '.join(mq(e['name']) for e in d) + '] as Array<String>;')
    for key, col in (('evo', 'EVOLVES_TO'), ('lvl', 'EVOLVE_LEVEL'), ('rar', 'RARITY'), ('hp', 'B_HP'),
                     ('atk', 'B_ATK'), ('df', 'B_DEF'), ('spe', 'B_SPE'), ('bio', 'BIOME')):
        o.append(f'    const {col} = [' + ', '.join(str(e[key]) for e in d) + '] as Array<Number>;')
    o.append('    const ACCENT = [' + ', '.join(f'0x{e["acc"] & 0xFFFFFF:06X}' for e in d) + '] as Array<Number>;')
    o.append('    const S = [' + ', '.join(mq(garmin_fmt(s)) for s in t['rows'][en]) + '] as Array<String>;')
    for k, rows in t['medals'].items():
        o.append(f'    const {k} = [' + ', '.join(mq(s) for s in rows[en]) + '] as Array<String>;')
    o.append('}')
    o.append('')
    o.append('// string ids, same order as TamaPoke\'s StrId')
    o.append('module Str {')
    for n, i in enumerate(t['ids']):
        o.append(f'    const {i[2:]} = {n};')
    o.append('}')
    return '\n'.join(o) + '\n'


# char-map sprites the Garmin build needs, and their sizes in the firmware's
# 466 px space (sprite px * the scale TamaPoke draws them at)
GARMIN_MAPS = [
    ('SPR_EGG', 5, 'Egg'),
    ('SPR_ICON_FOOD', 2, 'IcoFood'), ('SPR_ICON_PLAY', 2, 'IcoPlay'),
    ('SPR_ICON_LIGHT', 2, 'IcoLight'), ('SPR_ICON_CLEAN', 2, 'IcoClean'),
    ('SPR_ICON_FOOD', 3, 'MenuRed'), ('SPR_ICON_BERRY_B', 3, 'MenuBlue'),
    ('SPR_ICON_BERRY_G', 3, 'MenuGreen'), ('SPR_ICON_CANDY', 3, 'MenuCandy'),
    ('SPR_ICON_PLAY', 3, 'Ball'),
    ('SPR_HEART', 2, 'Heart'), ('SPR_HEART', 1, 'HeartSmall'), ('SPR_POOP', 2, 'Poop'),
]


def emit_garmin_drawables(t):
    from PIL import Image
    out = os.path.join(ROOT, 'garmin', 'resources', 'drawables')
    os.makedirs(out, exist_ok=True)
    xml = ['<!-- GENERATED by tools/gen_tables.py - do not edit. Sizes are relative to the',
           '     screen so they match TamaPoke\'s 466 px layout on every watch. -->', '<drawables>',
           '    <bitmap id="LauncherIcon" filename="launcher_icon.png" />']
    for name, scale, rid in GARMIN_MAPS:
        rows = t['sprites'][name]
        n, w = len(rows), len(rows[0])
        im = Image.new('RGBA', (w * scale, n * scale), (0, 0, 0, 0))
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch == '.':
                    continue
                v = t['colors'][ch]
                c = ((v >> 16) & 255, (v >> 8) & 255, v & 255, 255)
                for dy in range(scale):
                    for dx in range(scale):
                        im.putpixel((x * scale + dx, y * scale + dy), c)
        fname = f'{rid.lower()}.png'
        im.save(os.path.join(out, fname))
        pct = w * scale * 100 / 466
        xml.append(f'    <bitmap id="{rid}" filename="{fname}" scaleX="{pct:.2f}%" scaleY="{pct:.2f}%" '
                   f'scaleRelativeTo="screen" dithering="none" />')
    # launcher icon: the firmware's ball icon on a round cream badge
    rows = t['sprites']['SPR_ICON_PLAY']
    icon = Image.new('RGBA', (70, 70), (0, 0, 0, 0))
    from PIL import ImageDraw
    ImageDraw.Draw(icon).ellipse((0, 0, 69, 69), fill=(242, 239, 225, 255))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != '.':
                v = t['colors'][ch]
                for dy in range(3):
                    for dx in range(3):
                        icon.putpixel((11 + x * 3 + dx, 11 + y * 3 + dy), ((v >> 16) & 255, (v >> 8) & 255, v & 255, 255))
    icon.save(os.path.join(out, 'launcher_icon.png'))
    xml.append('</drawables>')
    with open(os.path.join(out, 'drawables.xml'), 'w') as f:
        f.write('\n'.join(xml) + '\n')
    print('wrote garmin/resources/drawables')


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    t = parse(sys.argv[1])
    targets = [
        (os.path.join(ROOT, 'wearos/game/src/main/kotlin/com/pokewatch/game/Tables.kt'), emit_kotlin(t)),
        (os.path.join(ROOT, 'garmin/source/Tables.mc'), emit_monkeyc(t)),
    ]
    for path, text in targets:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8') as f:
            f.write(text)
        print('wrote', os.path.relpath(path, ROOT))
    emit_garmin_drawables(t)


if __name__ == '__main__':
    main()
