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
                     --write-codes prebuilt/quick_codes.txt \\
                     --write-cangjie prebuilt/open_cangjie.txt \\
                     --unihan Unihan.zip
  python3 noquick.py --codes prebuilt/quick_codes.txt \\
                     --dict rime/mixed_quick.dict.yaml \\
                     --out rime/mixed_cangjie.dict.yaml

Or, for a pure Cangjie dictionary (build.sh --cangjie-dict open): only the
Cangjie5 table of fcitx5-table-extra (prebuilt/open_cangjie.txt), single
characters in its order; no words, no Cantonese, no English-to-Chinese.
Simplified-only characters (门, 处) are left out unless --keep-simplified:
those whose kTraditionalVariant in Unihan (https://www.unicode.org/Public/
UCD/latest/ucd/Unihan.zip) names other characters but not themselves
(后 lists 后 and 後, so it stays). open_cangjie.txt marks them with "s".
The table orders characters only within a code, so common and rare ones
mix; --mixed-order DICT ranks them by how common the Mixed dictionary has
them instead (build.sh does this unless --table-order).

  python3 noquick.py --open prebuilt/open_cangjie.txt \\
                     --out rime/mixed_cangjie.dict.yaml [--keep-simplified] \\
                     [--mixed-order rime/mixed_quick.dict.yaml]
"""

import argparse
import io
import os
import re
import subprocess
import sys
import zipfile

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


def commit_of(folder):
    try:
        return subprocess.run(["git", "-C", folder, "rev-parse", "HEAD"], text=True,
                              capture_output=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def simplified_only(unihan):
    """Characters whose traditional form is only another character."""
    out = set()
    with zipfile.ZipFile(unihan) as z:
        text = io.TextIOWrapper(z.open("Unihan_Variants.txt"), encoding="utf-8")
        for line in text:
            parts = line.rstrip("\n").split("\t")
            if len(parts) == 3 and parts[1] == "kTraditionalVariant":
                char = chr(int(parts[0][2:], 16))
                trad = {chr(int(u[2:], 16)) for u in parts[2].split()}
                if char not in trad:
                    out.add(char)
    return out


def write_cangjie(tables, path, unihan=None):
    """cangjie5.txt in its own order, as <code>\t<character>[\ts]."""
    simp = simplified_only(unihan) if unihan else set()
    rows, seen = [], set()
    with open(os.path.join(tables, "cangjie5.txt"), encoding="utf-8") as f:
        for line in f:
            m = ENTRY.match(line.rstrip("\n"))  # skips "&a 日", the key labels
            if m and len(m.group(2)) == 1 and m.groups() not in seen:
                seen.add(m.groups())
                rows.append(m.groups())
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Cangjie5, by noquick.py from fcitx5-table-extra (cangjie5.txt),\n"
                "# public domain. In the table's order.\n"
                "# commit: %s\n"
                "# <code>\\t<character>[\\ts]: s = simplified only (Unihan%s)\n"
                % (commit_of(tables), "" if unihan else ": not checked"))
        for code, char in rows:
            f.write("%s\t%s%s\n" % (code, char, "\ts" if char in simp else ""))
    print("%s: %d Cangjie5 codes, %d of them simplified only"
          % (path, len(rows), sum(1 for c, ch in rows if ch in simp)))


def mixed_weights(path):
    """{character: its highest weight in a Mixed dictionary}: near 100000 for
    a character listed first under some code, below 10000 for a rare one."""
    best, body = {}, False
    with open(path, encoding="utf-8") as f:
        for line in f:
            if not body:
                body = line.startswith("...")
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) == 3 and len(parts[0]) == 1:
                w = int(parts[2])
                if w > best.get(parts[0], 0):
                    best[parts[0]] = w
    return best


def write_open(path, dst, keep_simplified=False, weights=None):
    """A Rime dictionary from open_cangjie.txt.

    Without weights: falling weight in the table's order, within each code.
    With weights (mixed_weights()): a character ranks by how common the
    Mixed dictionary has it, the table's order breaking ties; characters
    Mixed lacks come after all it has, in the table's order.
    """
    rank, dropped, borrowed = {}, 0, 0
    with open(path, encoding="utf-8") as f, open(dst, "w", encoding="utf-8") as out:
        out.write("# Generated by noquick.py from prebuilt/open_cangjie.txt\n"
                  "# (fcitx5-table-extra Cangjie5, public domain).\n"
                  "# Do not edit; re-run noquick.py instead.\n"
                  "---\n"
                  "name: mixed_cangjie\n"
                  "version: \"cangjie5\"\n"
                  "sort: by_weight\n"
                  "use_preset_vocabulary: false\n"
                  "columns:\n  - text\n  - code\n  - weight\n"
                  "...\n")
        n = 0
        for line in f:
            if line.startswith("#") or "\t" not in line:
                continue
            code, char, *flag = line.rstrip("\n").split("\t")
            if flag == ["s"] and not keep_simplified:
                dropped += 1
                continue
            rank[code] = rank.get(code, 0) + 1
            if weights is None:
                weight = max(1, 100000 - rank[code] + 1)
            elif char in weights:
                weight = (weights[char] + 1) * 100 + max(0, 100 - rank[code])
                borrowed += 1
            else:
                weight = max(1, 100 - rank[code])
            out.write("%s\t%s\t%d\n" % (char, code, weight))
            n += 1
    print("%s: %d entries, Cangjie5 only (%s; %s)" % (dst, n, "simplified kept"
          if keep_simplified else "%d simplified-only left out" % dropped,
          "order: the table's" if weights is None
          else "order: Mixed's for %d, the table's for the rest" % borrowed))


def write_codes(tables, path):
    quick, cangjie = set(), set()
    for name in QUICK:
        quick |= read_table(os.path.join(tables, name + ".txt"))
    for name in CANGJIE:
        cangjie |= read_table(os.path.join(tables, name + ".txt"))
    pairs = sorted(quick - cangjie)
    commit = commit_of(tables)
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
    ap.add_argument("--write-cangjie", help="with --tables: write the Cangjie5 list here")
    ap.add_argument("--unihan", help="with --write-cangjie: Unihan.zip, to mark "
                    "simplified-only characters")
    ap.add_argument("--mixed-order", metavar="DICT",
                    help="with --open: rank characters as this Mixed dictionary "
                    "(mixed_quick.dict.yaml) does")
    ap.add_argument("--keep-simplified", action="store_true",
                    help="with --open: keep simplified-only characters")
    ap.add_argument("--codes", help="the Quick list (prebuilt/quick_codes.txt)")
    ap.add_argument("--open", help="the Cangjie5 list (prebuilt/open_cangjie.txt): "
                    "write a pure Cangjie dictionary to --out instead")
    ap.add_argument("--dict", help="mixed_quick.dict.yaml to read")
    ap.add_argument("--out", help="mixed_cangjie.dict.yaml to write")
    args = ap.parse_args()
    if args.tables and (args.write_codes or args.write_cangjie):
        if args.write_codes:
            write_codes(args.tables, args.write_codes)
        if args.write_cangjie:
            write_cangjie(args.tables, args.write_cangjie, args.unihan)
    elif args.open and args.out:
        write_open(args.open, args.out, args.keep_simplified,
                   mixed_weights(args.mixed_order) if args.mixed_order else None)
    elif args.codes and args.dict and args.out:
        strip_dict(args.codes, args.dict, args.out)
    else:
        ap.error("give --tables and --write-codes/--write-cangjie, "
                 "--codes, --dict and --out, or --open and --out")


if __name__ == "__main__":
    main()
