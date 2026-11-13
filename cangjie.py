#!/usr/bin/env python3
"""Write mixed_cangjie.txt: the Cangjie code of each character, for the
code hint after a commit (lua/mixed_predict.lua).

Source: the kCangjie field of Unicode's Unihan database (Unihan.zip from
https://www.unicode.org/Public/UCD/latest/ucd/), Unicode License v3.

Unihan gives Cangjie 3 codes; the app's dictionary uses Cangjie 5, and the
two differ for a few characters (泎: Unihan ehs, dictionary eos). Where the
Unihan code is not one of the character's codes in mixed_quick.dict.yaml,
the closest dictionary code with the same first letter is used instead
(the Quick code, first and last letter only, is not a candidate); if none
is close enough, Unihan's code is kept.

Output, one line per character, after a few # comment lines:

  <character>\\t<code>

  python3 cangjie.py --unihan Unihan.zip --dict prebuilt/mixed_quick.dict.yaml \\
                     --out prebuilt/mixed_cangjie.txt
"""

import argparse
import difflib
import io
import re
import zipfile
from collections import defaultdict

UNIHAN_FILE = "Unihan_DictionaryLikeData.txt"


def read_unihan(path):
    """{character: code}, and the Unicode version from the header."""
    with zipfile.ZipFile(path) as z:
        text = io.TextIOWrapper(z.open(UNIHAN_FILE), encoding="utf-8")
        codes, version = {}, "?"
        for line in text:
            m = re.match(r"# Unicode Version (\S+)", line)
            if m:
                version = m.group(1)
            if "\tkCangjie\t" not in line:
                continue
            point, _, code = line.rstrip("\n").split("\t")
            codes[chr(int(point[2:], 16))] = code.lower()
    return codes, version


def read_dict(path):
    """{character: set of codes} for the single characters in a Rime dict."""
    codes = defaultdict(set)
    body = False
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("..."):
                body = True
                continue
            if not body or line.startswith("#"):
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2 and len(parts[0]) == 1:
                codes[parts[0]].add(parts[1])
    return codes


def resolve(char, code, dict_codes):
    """The dictionary's code for char closest to Unihan's, or Unihan's."""
    have = dict_codes.get(char)
    if not have:
        return code, "nodict"
    if code in have:
        return code, "same"
    best, score = None, 0.0
    for c in have:
        if not c.isalpha() or c[0] != code[0] or len(c) > 5:
            continue
        if len(code) > 2 and len(c) <= 2:
            continue                    # a Quick code
        r = difflib.SequenceMatcher(None, code, c).ratio()
        if r > score:
            best, score = c, r
    if best and score >= 0.6:
        return best, "dict"
    return code, "unihan"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--unihan", required=True, help="Unihan.zip")
    ap.add_argument("--dict", required=True, help="mixed_quick.dict.yaml")
    ap.add_argument("--out", required=True, help="mixed_cangjie.txt to write")
    args = ap.parse_args()

    unihan, version = read_unihan(args.unihan)
    dict_codes = read_dict(args.dict)
    count = defaultdict(int)
    lines = []
    for char in sorted(unihan):
        code, how = resolve(char, unihan[char], dict_codes)
        count[how] += 1
        lines.append(f"{char}\t{code}\n")
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(f"# Cangjie codes, by cangjie.py from Unihan {version} (kCangjie)\n")
        f.write("# Unihan: (c) Unicode, Inc., Unicode License v3,\n")
        f.write("#   https://www.unicode.org/license.txt\n")
        f.writelines(lines)
    print(f"{args.out}: {len(lines)} characters "
          f"(Unihan's code: {count['same']} also in the dictionary, "
          f"{count['nodict']} not in the dictionary, {count['unihan']} not "
          f"found there; {count['dict']} replaced by the dictionary's)")


if __name__ == "__main__":
    main()
