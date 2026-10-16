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
start = data.rfind(b'{\r\n', 0, a)
end = data.find(b'\r\n}', a)
table = data[start:end + 3].decode('utf-8', 'replace').replace('\r\n', '\n')
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


def candidates(text):
    # The values in the talent data just before the text's own copy (not the
    # text table's, which is quoted).
    needle = text.encode('utf-8')
    pos = 0
    while True:
        pos = data.find(needle, pos + 1)
        if pos < 0:
            return []
        if data[pos - 1:pos] != b'"':
            break
    first = pos
    while first > 0 and pos - first < 120 and not all(0x20 <= c <= 0x7e for c in data[first - 3:first]):
        first -= 1
    gap = data[first:pos]
    found = []
    for k in range(len(gap) - 3):
        f = struct.unpack('<f', gap[k:k + 4])[0]
        if 0.001 <= f <= 1000 and abs(f * 100 - round(f * 100)) < 1e-3:
            found.append(f)
    return found


def number(f):
    text = ('%.1f' % f).rstrip('0').rstrip('.')
    return text


def fill(text):
    if '{v}' not in text:
        return text
    percent = '{v}%' in text
    for f in candidates(text):
        if percent and 0 < f <= 1:
            return text.replace('{v}', number(f * 100))
        if not percent and f >= 1 and f == int(f):
            return text.replace('{v}', number(f))
    return text


out = {k: fill(v) for k, v in texts.items()}


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
open(sys.argv[3], 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
unread = [k for k in out if '{v}' in out[k]]
print(len(out), 'talents;', len(unread), 'numbers unread:', ', '.join(sorted(unread)), file=sys.stderr)
