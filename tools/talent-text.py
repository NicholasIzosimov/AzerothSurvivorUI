# Rebuilds SurvivorUI/TalentText.lua from the game's own data. Run after a
# game update:
#   python tools/talent-text.py path\to\AzerothSurvivors.exe SurvivorUI/TalentIcons.lua SurvivorUI/TalentText.lua
#
# The descriptions come from the game's English text table, where each
# talent's name comes just before its description. A description holds {v}
# where the game puts the talent's number; the number is read from the
# game's talent data, the bytes just before the description's own copy of
# the text: the first value there that fits the text ("{v}%" a fraction from
# 0 to 1, shown as a percentage; any other {v} a whole number from 1). Where
# none fits, {v} is left for the addon to show as unknown.

import re, sys, struct

data = open(sys.argv[1], 'rb').read()
a = data.find(b'"Milestone. Shadow Bolt splits')
start = max(data.rfind(b'{\r\n', 0, a), data.rfind(b'{\n', 0, a))
end = data.find(b'\n}', a)
table = data[start:end + 2].decode('utf-8', 'replace').replace('\r\n', '\n')
pairs = re.findall(r'^\s*"((?:[^"\\]|\\.)*)": "((?:[^"\\]|\\.)*)",?$', table, re.M)
names = set(re.findall(r'\["([^"]+)"\]\s*=', open(sys.argv[2], encoding='utf-8').read()))
order = [k for k, v in pairs]


def is_name(k):
    return len(k) < 40 and not k.endswith('.') and re.match(r"^[A-Z][A-Za-z' :\-]+$", k)


texts = {}
for i, k in enumerate(order[:-1]):
    nxt = order[i + 1]
    if not (nxt.endswith('.') and ' ' in nxt and is_name(k)):
        continue
    # A talent: one the icon list knows, or a text in the talents' own style.
    if k in names or nxt.startswith('Milestone. ') or nxt.startswith('Capstone. ') or '{v}' in nxt:
        texts[k] = nxt.replace('\\"', '"')


def talent_gap(text):
    # The talent data just before the text's own copy (not the text table's,
    # which is quoted): from the end of the strings before it to the text.
    needle = text.encode('utf-8')
    pos = 0
    while True:
        pos = data.find(needle, pos + 1)
        if pos < 0:
            return b''
        if data[pos - 1:pos] != b'"':
            break
    first = pos
    while first > 0 and pos - first < 120 and not all(0x20 <= c <= 0x7e for c in data[first - 3:first]):
        first -= 1
    return data[first:pos]


def candidates(text):
    # The values there stored as decimals: a percentage as a fraction (0.15).
    gap = talent_gap(text)
    found = []
    for k in range(len(gap) - 3):
        f = struct.unpack('<f', gap[k:k + 4])[0]
        if 0.001 <= f <= 1000 and abs(f * 100 - round(f * 100)) < 1e-3:
            found.append(f)
    return found


def whole_number(text):
    # A count stored as a whole number ("every 5th spell", Maelstrom Weapon):
    # the four bytes after a 1, with zeros after them, where that 1 does not
    # end a reference to a string (a pointer's bytes before it).
    gap = talent_gap(text)
    for k in range(len(gap) - 11):
        if gap[k:k + 4] != b'\x01\x00\x00\x00' or gap[k + 8:k + 12] != b'\x00\x00\x00\x00':
            continue
        if k > 0 and gap[k - 1] != 0:
            continue
        n = struct.unpack('<I', gap[k + 4:k + 8])[0]
        if 1 <= n <= 1000:
            return n
    return None


def number(f):
    text = ('%.1f' % f).rstrip('0').rstrip('.')
    return text


def fill(text):
    if '{v}' not in text:
        return text
    percent = '{v}%' in text
    # A value the text already writes out is one of its fixed numbers, not
    # its {v} ("stacking up to 30%": Ardent Defender's {v} is 8, not 30).
    written = set(re.findall(r'(?<![\d.])(\d+(?:\.\d+)?)', text.replace('{v}', '')))
    for f in candidates(text):
        if percent and 0 < f <= 1 and number(f * 100) not in written:
            return text.replace('{v}', number(f * 100))
        if not percent and f >= 1 and f == int(f) and number(f) not in written:
            return text.replace('{v}', number(f))
    if not percent:
        n = whole_number(text)
        if n:
            return text.replace('{v}', str(n))
    return text


# Numbers the reader cannot find in the talent data, as the game's own talent
# pane shows them.
SEEN_IN_GAME = {
    'Pyroclasm': '25',
}

out = {k: fill(v) for k, v in texts.items()}
for k, v in SEEN_IN_GAME.items():
    if k in out:
        out[k] = out[k].replace('{v}', v)


def snake(text):
    return re.sub(r'[^a-z0-9]+', '_', re.sub(r"'s\b", '', text.lower())).strip('_')


# Talents one class has under a name another's has too ("flurry_shaman" is
# the Shaman's Flurry, not the Warrior's): the text table keeps a name once,
# so these are read from the talent data, by their key, where their text
# differs from the name's.
CLASSES = ['warrior', 'paladin', 'hunter', 'rogue', 'priest', 'shaman', 'mage', 'warlock', 'druid']
by_snake = {snake(name): name for name in texts}
anchor_at = data.find(b'Milestone. Shadow Bolt splits: every bolt that lands forks to 2 more enemies for {v}% of it.devastation')
talent_pool = data[max(0, anchor_at - 2500000):anchor_at + 2500000]
by_class = {}
key_pattern = rb'(?<![a-z_])([a-z][a-z_]*?)_(' + '|'.join(CLASSES).encode() + rb')(?=[^\x20-\x7e]|[A-Z])'
for m in re.finditer(key_pattern, talent_pool):
    name = by_snake.get(m.group(1).decode())
    if not name:
        continue
    after = talent_pool[m.end():m.end() + 400]
    run = re.search(rb'[\x20-\x7e]{12,}', after)
    if not run:
        continue
    pieces = re.split(r'(?<=[a-z0-9])(?=[A-Z])|(?<=\.)(?=[a-z])', run.group().decode('latin1'))
    text = next((p for p in pieces if ' ' in p and p.endswith('.')), None)
    if text and text != texts.get(name):
        by_class.setdefault(m.group(2).decode().upper(), {})[name] = fill(text)


def lua(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


lines = [
    '-- Survivor UI: each talent\'s description, by name, as the game\'s own talent',
    '-- screen words it, with its number, taken from the game\'s data',
    '-- (tools/talent-text.py). {v} is left where the number could not be read.',
    '-- A talent whose description the game shares with another is missing. The',
    '-- damage meter\'s card shows a talent\'s proc with its text.',
    '',
    'SurvivorUI_TALENT_TEXTS = {',
]
for k in sorted(out):
    lines.append('\t[' + lua(k) + '] = ' + lua(out[k]) + ',')
lines.append('}')
lines += [
    '',
    '-- A class\'s own talent of a name another class has too, by class token:',
    '-- read first for the hero\'s class (SurvivorUI_TalentRaw, CritCard.lua).',
    'SurvivorUI_TALENT_TEXTS_BY_CLASS = {',
]
for cls in sorted(by_class):
    lines.append('\t' + cls + ' = {')
    for k in sorted(by_class[cls]):
        lines.append('\t\t[' + lua(k) + '] = ' + lua(by_class[cls][k]) + ',')
    lines.append('\t},')
lines.append('}')
open(sys.argv[3], 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
print('class talents:', ', '.join(cls + ' ' + k for cls in sorted(by_class) for k in sorted(by_class[cls])), file=sys.stderr)
unread = [k for k in out if '{v}' in out[k]]
print(len(out), 'talents;', len(unread), 'numbers unread:', ', '.join(sorted(unread)), file=sys.stderr)

# The icons: TalentIcons.lua gains the icon the game's talent data gives each
# talent it lacks. In the data a talent's key, name and icon run together
# ("seed_of_corruptionSeed of CorruptionSpell_Shadow_CurseOfMannoroth"); an
# icon may have the keys of the spells the talent names run onto its end
# ("Ability_Gougerend" for Improved Rend), or the next talent's key and name;
# those are taken off. An icon that still holds a key ("_abc") is left out.
icons_text = open(sys.argv[2], encoding='utf-8').read()
existing = dict(re.findall(r'\["([^"]+)"\]\s*=\s*"Interface\\\\Icons\\\\([^"]+)"', icons_text))
known = set(existing) | set(texts)
anchor = data.find(b'Milestone. Shadow Bolt splits: every bolt that lands forks to 2 more enemies for {v}% of it.devastation')
pool = data[max(0, anchor - 400000):anchor + 400000]
ICON = rb'((?:Spell|Ability|INV|Trade|Racial|Temp)_[A-Za-z0-9_]+)(?=[^\x20-\x7e])'


def snake(text):
    return re.sub(r'[^a-z0-9]+', '_', re.sub(r"'s\b", '', text.lower())).strip('_')


def spell_keys(description):
    # Every run of one to four words that starts with a capital, in snake case.
    words = re.findall(r"[A-Za-z][A-Za-z'\-]*", description or '')
    keys = set()
    for size in range(1, 5):
        for i in range(len(words) - size + 1):
            if words[i][0].isupper():
                keys.add(snake(' '.join(words[i:i + size])))
    return keys


def trim(name, icon):
    for other in known:
        p = icon.find(other, 1)
        if p > 0 and len(other) >= 4:
            key = snake(other)
            if not icon[:p].endswith(key):
                return None
            icon = icon[:p - len(key)]
    keys = sorted(spell_keys(texts.get(name, '')), key=len, reverse=True)
    changed = True
    while changed:
        changed = False
        for key in keys:
            if len(key) >= 3 and icon.endswith(key) and len(icon) > len(key) + 6 and icon[-len(key) - 1].isalnum():
                icon = icon[:-len(key)]
                changed = True
                break
    return None if re.search(r'_[a-z]', icon) else icon


added = {}
for name in sorted(known - set(existing)):
    for m in re.finditer(re.escape(name.encode()) + ICON, pool):
        if re.match(rb'[a-z0-9_]', pool[m.start() - 1:m.start()]):
            icon = trim(name, m.group(1).decode())
            if icon:
                added[name] = icon
            break
if added:
    every = dict(existing)
    every.update(added)
    head = icons_text[:icons_text.index('SurvivorUI_TALENT_ICONS = {')]
    body = ['SurvivorUI_TALENT_ICONS = {']
    for k in sorted(every):
        body.append('\t[' + lua(k) + '] = ' + lua('Interface\\Icons\\' + every[k]) + ',')
    body.append('}')
    open(sys.argv[2], 'w', encoding='utf-8', newline='\n').write(head + '\n'.join(body) + '\n')
print(len(added), 'talent icons added:', ', '.join(sorted(added)), file=sys.stderr)
