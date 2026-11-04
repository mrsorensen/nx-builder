#!/usr/bin/env python3
"""Checks Localizations/*.json against the texts in Sources: every L("…") key is translated, no key is
left over, and each translation has the key's placeholders (%@ in the key; %@ or %1$@ %2$@ … in the
translation, each argument once). Usage: python3 Tools/check_localizations.py [language code …]
Exit code 1 when a file has a problem. To add a language: copy nb.json to <code>.json, translate the
values (the keys are the English texts), add the code to AppLanguage in Sources/L10n.swift, and run this."""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent


def literal(src, i):
    """The Swift string literal at src[i] == '"' as written (escapes kept), and the index after it."""
    j = i + 1
    while src[j] != '"':
        if src[j] == '\\' and src[j + 1] == '(':
            depth, j = 1, j + 2
            while depth:
                if src[j] == '"': _, j = literal(src, j); continue
                depth += {'(': 1, ')': -1}.get(src[j], 0)
                j += 1
            continue
        j += 2 if src[j] == '\\' else 1
    raw = src[i + 1:j]
    text = re.sub(r'\\(.)', lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), raw)
    return text, j + 1


def source_keys():
    keys = set()
    for path in (root / 'Sources').glob('*.swift'):
        src = path.read_text()
        for m in re.finditer(r'(?<![A-Za-z0-9_.])L\(\s*"', src):
            text, _ = literal(src, m.end() - 1)
            keys.add(text)
    return keys


def placeholders(s):
    """('seq', n) for n plain %@, or ('pos', {numbers}) for %n$@; %% is not one."""
    s = s.replace('%%', '')
    seq = len(re.findall(r'%@', s))
    pos = [int(n) for n in re.findall(r'%(\d+)\$@', s)]
    return seq, pos


# Keys whose arguments repeat one value (the same version named twice): a translation may name it once.
REPEATED = {
    'Made for %@, but the folder\'s newest file is %@. Put the %@ update in the folder, or the recipe\'s fixes do not apply.': {3},
    'The recipe was made for %@, but you are building %@. Its fixes apply to that version only, so the game may misbehave or not start. Put the %@ update in the game folder and build again; what is already extracted is reused.': {3},
}


def repeats(key, value, unused):
    return unused <= REPEATED.get(key, set())


def check(path, keys):
    problems = []
    try:
        table = json.loads(path.read_text())
    except Exception as e:
        return [f'not valid JSON: {e}']
    missing, extra = keys - table.keys(), table.keys() - keys
    problems += [f'missing: {k!r}' for k in sorted(missing)]
    problems += [f'not in the sources: {k!r}' for k in sorted(extra)]
    for key, value in table.items():
        if key not in keys: continue
        if not isinstance(value, str) or not value.strip() and key.strip():
            problems.append(f'empty: {key!r}'); continue
        want, _ = placeholders(key)
        seq, pos = placeholders(value)
        if seq and pos:
            problems.append(f'mixes %@ and %n$@: {value!r}')
        elif seq and seq != want:
            problems.append(f'{seq} placeholders, key has {want}: {value!r}')
        elif pos and not set(pos) <= set(range(1, want + 1)):
            problems.append(f'placeholders {sorted(set(pos))}, key has {want}: {value!r}')
        elif pos and set(pos) != set(range(1, want + 1)) and not repeats(key, value, set(range(1, want + 1)) - set(pos)):
            problems.append(f'argument(s) {sorted(set(range(1, want + 1)) - set(pos))} unused: {value!r}')
        elif not seq and not pos and want:
            problems.append(f'no placeholders, key has {want}: {value!r}')
    return problems


keys = source_keys()
codes = sys.argv[1:] or sorted(p.stem for p in (root / 'Localizations').glob('*.json'))
bad = False
for code in codes:
    problems = check(root / 'Localizations' / f'{code}.json', keys)
    print(f'{code}: {len(keys)} texts, ' + ('ok' if not problems else f'{len(problems)} problem(s)'))
    for p in problems[:40]: print('  ', p)
    bad |= bool(problems)
sys.exit(1 if bad else 0)
