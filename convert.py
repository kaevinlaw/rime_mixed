#!/usr/bin/env python3
"""Convert Mixed Chinese Keyboard Plus dictionaries to Rime table dictionaries.

Source: https://github.com/holleeb/Mixed-Chinese-Keyboard-Plus-Dicts (v2.1/*.ms2)

  mix_map_ext_<c>.ms2, mix_map_ext_<c>1.ms2   ->  mixed_quick.dict.yaml
  eng_*.ms2                                   ->  mixed_eng.dict.yaml
  phrase_*.ms2                                ->  mixed_predict.txt

.ms2 format (see the repo's explain.md), one entry per line:

  <key>\t<candidates>

  - In mix_map_ext_<c>[1], the code is <c> + <key>; the "1" file holds the
    codes whose second letter is l..z. mix_map_ext_0 holds symbol codes in
    full (skipped: Rime's speller here only takes a..z).
  - Candidates: a run of single characters, then words prefixed by their
    UTF-16 length as one ASCII digit ("2時間", "2𥄫" for one supplementary
    character).
  - Sections: traditional | \\x00 traditional rare | \\x08 simplified |
    \\x0c simplified rare. Only the two traditional sections are kept.

Order in the app's list becomes a falling weight, so Rime shows candidates
in the app's order; rare characters rank after all common ones.
"""

import argparse
import glob
import os
import re
import sys

SEC_TRAD, SEC_TRAD_RARE, SEC_SIMP, SEC_SIMP_RARE = range(4)
SEPARATORS = {"\x00": SEC_TRAD_RARE, "\x08": SEC_SIMP, "\x0c": SEC_SIMP_RARE}

WEIGHT_TOP = 100000     # first common candidate of a code
WEIGHT_RARE = 10000     # first rare candidate; stays below every common one

CODE_RE = re.compile(r"^[a-z]+$")


def utf16_len(ch):
    return 2 if ord(ch) > 0xFFFF else 1


def parse_candidates(s):
    """Yield (word, section) in list order; raise ValueError on a bad length."""
    section = SEC_TRAD
    i = 0
    while i < len(s):
        ch = s[i]
        if ch in SEPARATORS:
            # sections only move forward; a later separator never goes back
            section = max(section, SEPARATORS[ch])
            i += 1
            continue
        if ch in "123456789" and i + 1 < len(s):
            want = int(ch)
            j = i + 1
            units = 0
            while j < len(s) and units < want:
                units += utf16_len(s[j])
                j += 1
            if units != want:
                raise ValueError("length %d does not fit at %d" % (want, i))
            yield s[i + 1:j], section
            i = j
            continue
        yield ch, section
        i += 1


def usable(word):
    return word and not any(c in "\t\n\r" or ord(c) < 0x20 for c in word)


def read_lines(path):
    with open(path, encoding="utf-8") as f:
        for line in f.read().split("\n"):
            if "\t" in line:
                yield line.split("\t", 1)


def convert_mixed(src, stats):
    entries = []
    seen = set()
    files = sorted(glob.glob(os.path.join(src, "mix_map_ext_*.ms2")))
    for path in files:
        m = re.match(r"mix_map_ext_([a-z0-9])1?\.ms2$", os.path.basename(path))
        if not m:
            continue
        first = m.group(1)
        for key, cands in read_lines(path):
            code = key if first == "0" else first + key
            if not CODE_RE.match(code):
                stats["mixed_skipped_codes"] += 1
                continue
            try:
                parsed = list(parse_candidates(cands))
            except ValueError:
                stats["mixed_bad_lines"] += 1
                continue
            common = rare = 0
            for word, section in parsed:
                if section >= SEC_SIMP or not usable(word):
                    continue
                if (code, word) in seen:
                    continue
                seen.add((code, word))
                if section == SEC_TRAD:
                    weight = max(WEIGHT_RARE + 1, WEIGHT_TOP - common)
                    common += 1
                else:
                    weight = max(1, WEIGHT_RARE - rare)
                    rare += 1
                entries.append((word, code, weight))
    stats["mixed_files"] = len(files)
    stats["mixed_entries"] = len(entries)
    return entries


def convert_english(src, stats):
    """eng_*.ms2: key is the word; candidates are its other forms.

    "aaron\\t5Aaron" -> aaron, Aaron. An empty list means the word itself.
    """
    entries = []
    seen = set()
    for path in sorted(glob.glob(os.path.join(src, "eng_*.ms2"))):
        for key, cands in read_lines(path):
            if key == "null" or not CODE_RE.match(key):
                stats["eng_skipped_codes"] += 1
                continue
            try:
                words = [w for w, s in parse_candidates(cands) if s == SEC_TRAD]
            except ValueError:
                stats["eng_bad_lines"] += 1
                continue
            for pos, word in enumerate([key] + words):
                if not usable(word) or (key, word) in seen:
                    continue
                seen.add((key, word))
                entries.append((word, key, max(1, WEIGHT_TOP - pos)))
    stats["eng_entries"] = len(entries)
    return entries


def convert_phrases(src, stats):
    """phrase_N.ms2: key is committed text, candidates are what may follow.

    "我\\t的人會…2唔係3的最愛" -> 我: 的, 人, 會, …, 唔係, 的最愛
    Read by lua/mixed_predict.lua; traditional sections only, app order.
    """
    rows = []
    for path in sorted(glob.glob(os.path.join(src, "phrase_*.ms2"))):
        for key, cands in read_lines(path):
            if not usable(key):
                continue
            try:
                words = [w for w, s in parse_candidates(cands) if s < SEC_SIMP]
            except ValueError:
                stats["phrase_bad_lines"] += 1
                continue
            words = [w for w in dict.fromkeys(words) if usable(w)]
            if words:
                rows.append((key, words))
    stats["phrase_keys"] = len(rows)
    return rows


def write_phrases(path, rows):
    with open(path, "w", encoding="utf-8") as f:
        for key, words in rows:
            f.write("%s\t%s\n" % (key, "\t".join(words)))


def write_dict(path, name, version, entries):
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Generated by convert.py from Mixed-Chinese-Keyboard-Plus-Dicts v%s\n"
                "# (https://github.com/holleeb/Mixed-Chinese-Keyboard-Plus-Dicts, Apache-2.0)\n"
                "# Do not edit; re-run convert.py instead.\n"
                "---\n"
                "name: %s\n"
                "version: \"%s\"\n"
                "sort: by_weight\n"
                "use_preset_vocabulary: false\n"
                "columns:\n  - text\n  - code\n  - weight\n"
                "...\n" % (version, name, version))
        for word, code, weight in entries:
            f.write("%s\t%s\t%d\n" % (word, code, weight))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--src", default=os.path.join(
        here, "..", "Mixed-Chinese-Keyboard-Plus-Dicts", "v2.1"),
        help="folder with the .ms2 files (default: ../Mixed-Chinese-Keyboard-Plus-Dicts/v2.1)")
    ap.add_argument("--out", default=os.path.join(here, "rime"),
                    help="folder to write the generated files into (default: ./rime)")
    args = ap.parse_args()

    if not glob.glob(os.path.join(args.src, "mix_map_ext_*.ms2")):
        sys.exit("no mix_map_ext_*.ms2 in %s" % args.src)
    os.makedirs(args.out, exist_ok=True)
    # folder name is the dictionary version: .../v2.1 -> "2.1"
    version = os.path.basename(os.path.normpath(args.src)).lstrip("v") or "unknown"

    stats = {k: 0 for k in ("mixed_skipped_codes", "mixed_bad_lines",
                            "eng_skipped_codes", "eng_bad_lines",
                            "phrase_bad_lines")}
    write_dict(os.path.join(args.out, "mixed_quick.dict.yaml"), "mixed_quick", version,
               convert_mixed(args.src, stats))
    write_dict(os.path.join(args.out, "mixed_eng.dict.yaml"), "mixed_eng", version,
               convert_english(args.src, stats))
    write_phrases(os.path.join(args.out, "mixed_predict.txt"),
                  convert_phrases(args.src, stats))
    for k, v in stats.items():
        print("%-20s %d" % (k, v))


if __name__ == "__main__":
    main()
