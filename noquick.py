#!/usr/bin/env python3
"""Write mixed_cangjie.dict.yaml: mixed_quick.dict.yaml without the Quick codes.

Quick (速成) types a character with the first and last letter of its
Cangjie code: 我 (hqi) is "hi". The Mixed dictionary holds both, so "hi"
lists 的我得風...; for the mixed_cangjie schema those entries are removed.
Everything else stays: Cangjie codes, Cantonese codes (你 ni, 好 ho),
words, English. A short code that is also the character's real Cangjie
code stays too: 明 ab, 鬼 hi, 日 a.

Which (code, character) pairs are Quick comes from the Quick tables of
fcitx5-table-extra (https://github.com/fcitx/fcitx5-table-extra, tables/;
Quick and Cangjie tables there are in the public domain): every pair in
quick-classic, quick3 or quick5 that is not also in cangjie3 or cangjie5.
That list is kept in prebuilt/quick_codes.txt, so the build needs no copy
of fcitx5-table-extra:

  python3 noquick.py --tables fcitx5-table-extra/tables \\
                     --write-codes prebuilt/quick_codes.txt
  python3 noquick.py --codes prebuilt/quick_codes.txt \\
                     --dict rime/mixed_quick.dict.yaml \\
                     --out rime/mixed_cangjie.dict.yaml
"""

import argparse
import os
import re
import subprocess
import sys

QUICK = ("quick-classic", "quick3", "quick5")
CANGJIE = ("cangjie3", "cangjie5")
ENTRY = re.compile(r"^([a-z]+) (\S+)$")   # fcitx table: "<code> <text>"


def read_table(path):
    pairs = set()
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = ENTRY.match(line.rstrip("\n"))
            if m and len(m.group(2)) == 1:
                pairs.add((m.group(1), m.group(2)))
    return pairs


def write_codes(tables, path):
    quick, cangjie = set(), set()
    for name in QUICK:
        quick |= read_table(os.path.join(tables, name + ".txt"))
    for name in CANGJIE:
        cangjie |= read_table(os.path.join(tables, name + ".txt"))
    pairs = sorted(quick - cangjie)
    try:
        commit = subprocess.run(["git", "-C", tables, "rev-parse", "HEAD"], text=True,
                                capture_output=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        commit = "unknown"
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Quick codes that are not also Cangjie codes, by noquick.py from\n"
                "# fcitx5-table-extra (%s minus %s), public domain.\n"
                "# commit: %s\n"
                "# <code>\\t<character>\n" % (", ".join(QUICK), ", ".join(CANGJIE), commit))
        for code, char in pairs:
            f.write("%s\t%s\n" % (code, char))
    print("%s: %d Quick codes (%d in the Quick tables, %d also Cangjie)"
          % (path, len(pairs), len(quick), len(quick & cangjie)))


def read_codes(path):
    pairs = set()
    with open(path, encoding="utf-8") as f:
        for line in f:
            if not line.startswith("#") and "\t" in line:
                code, char = line.rstrip("\n").split("\t")
                pairs.add((code, char))
    return pairs


def strip_dict(codes, src, dst):
    quick = read_codes(codes)
    body, dropped, kept = False, 0, 0
    with open(src, encoding="utf-8") as f, open(dst, "w", encoding="utf-8") as out:
        for line in f:
            if not body:
                if line.startswith("name: "):
                    line = "name: mixed_cangjie\n"
                elif line.startswith("# Do not edit"):
                    out.write("# Without the Quick codes: noquick.py, prebuilt/quick_codes.txt.\n")
                out.write(line)
                body = line.startswith("...")
                continue
            parts = line.split("\t")
            if len(parts) >= 2 and (parts[1], parts[0]) in quick:
                dropped += 1
                continue
            kept += 1
            out.write(line)
    if not body:
        sys.exit("%s: no '...' line, not a Rime dictionary" % src)
    print("%s: %d entries, %d Quick codes removed" % (dst, kept, dropped))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--tables", help="fcitx5-table-extra's tables/ folder")
    ap.add_argument("--write-codes", help="with --tables: write the Quick list here")
    ap.add_argument("--codes", help="the Quick list (prebuilt/quick_codes.txt)")
    ap.add_argument("--dict", help="mixed_quick.dict.yaml to read")
    ap.add_argument("--out", help="mixed_cangjie.dict.yaml to write")
    args = ap.parse_args()
    if args.tables and args.write_codes:
        write_codes(args.tables, args.write_codes)
    elif args.codes and args.dict and args.out:
        strip_dict(args.codes, args.dict, args.out)
    else:
        ap.error("give --tables and --write-codes, or --codes, --dict and --out")


if __name__ == "__main__":
    main()
