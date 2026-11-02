"""Builds Kobold.koplugin/l10n/kobold.pot, the translation template.

Finds every _("..."), _.N("...", "...") in the plugin's Lua files (string
pieces joined with .. inside the call count as one text) and writes them as
a standard gettext template, each with the files and lines it comes from.

Run it after changing any text in Kobold:
    python tools/make_pot.py
"""
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Kobold.koplugin")
OUT = os.path.join(ROOT, "l10n", "kobold.pot")

STR = r'"(?:[^"\\]|\\.)*"'
JOINED = rf'{STR}(?:\s*\.\.\s*{STR})*'
SINGLE = re.compile(rf'(?<![\w.])_\(\s*({JOINED})\s*\)')
PLURAL = re.compile(rf'(?<![\w.])_\.N\(\s*({JOINED})\s*,\s*({JOINED})\s*,')


def join(lua_strings):
    """Lua literal(s) joined by .. -> the po-escaped text."""
    return "".join(s[1:-1] for s in re.findall(STR, lua_strings))


def main():
    entries = {}  # (msgid, plural or None) -> [refs]
    order = []
    files = []
    for base, dirs, names in os.walk(ROOT):
        dirs.sort()
        for name in sorted(names):
            if name.endswith(".lua") and name != "_meta.lua":
                files.append(os.path.join(base, name))
    files.append(os.path.join(ROOT, "_meta.lua"))
    for path in files:
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        text = open(path, encoding="utf-8").read()
        found = []
        for m in PLURAL.finditer(text):
            found.append((m.start(), (join(m.group(1)), join(m.group(2)))))
        for m in SINGLE.finditer(text):
            found.append((m.start(), (join(m.group(1)), None)))
        for pos, key in sorted(found):
            line = text.count("\n", 0, pos) + 1
            if key not in entries:
                entries[key] = []
                order.append(key)
            entries[key].append(f"{rel}:{line}")

    out = [
        '# Kobold translation template.',
        '# Copy this file to l10n/<language code>/kobold.po (for example',
        '# l10n/de/kobold.po or l10n/pt_BR/kobold.po) and fill in the msgstr lines.',
        '# %1, %2, ... are values filled in by Kobold; keep them, in any order.',
        'msgid ""',
        'msgstr ""',
        '"Project-Id-Version: Kobold\\n"',
        '"MIME-Version: 1.0\\n"',
        '"Content-Type: text/plain; charset=UTF-8\\n"',
        '"Content-Transfer-Encoding: 8bit\\n"',
        '"Plural-Forms: nplurals=2; plural=(n != 1);\\n"',
        '',
    ]
    for key in order:
        msgid, plural = key
        refs = entries[key]
        out.append("#: " + " ".join(refs))
        if any("%" in s for s in key if s):
            out.append("#, lua-format")
        out.append(f'msgid "{msgid}"')
        if plural is None:
            out.append('msgstr ""')
        else:
            out.append(f'msgid_plural "{plural}"')
            out.append('msgstr[0] ""')
            out.append('msgstr[1] ""')
        out.append("")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))
    print(f"{len(order)} texts -> {os.path.relpath(OUT)}")


if __name__ == "__main__":
    main()
