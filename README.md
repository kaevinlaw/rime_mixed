# rime_mixed

[Rime](https://rime.im/) schema built from the
[Mixed Chinese Keyboard Plus](https://github.com/holleeb/Mixed-Chinese-Keyboard-Plus-Dicts)
dictionaries (速成/倉頡 + English words), for people who want the Android
app's behaviour on a desktop:

- candidates in the app's order, traditional first, rare characters last
- learning: what you pick moves forward (Rime user dictionary)
- prefix completion: `bac` also lists `back*`, `background` ... (`~~xx` shows
  the rest of the code)
- English words give Chinese: `background` → 背景
- associated phrases after a commit: 我 → 的 人 會 …; the last few characters
  count however they were typed, so 我 then 是 also offers 中國人;
  what you write after a character comes first next time (我 們 → 們 first)
- Cangjie hint: pick a character typed some other way (Quick `hi`,
  Cantonese `ngo`) or from the associated phrases (我 → 想) and the input
  line shows its Cangjie code as radicals, 〔我 竹手戈〕
- space pages forward and wraps to page 1; pick with 1-9 (or: space commits
  the first candidate, or types the letters as English, see Settings)

Works with any Rime frontend: fcitx5-rime, ibus-rime, Weasel (Windows),
Squirrel (macOS). Needs librime-lua for the last two items (Debian/Ubuntu:
`librime-plugin-lua`).

## Layout

| path        | what                                                      |
|-------------|-----------------------------------------------------------|
| `build.sh`  | assembles `rime/`, the folder you copy to your machine    |
| `convert.py`| `.ms2` dictionaries → Rime dictionaries                   |
| `cangjie.py`| Unihan → `prebuilt/mixed_cangjie.txt`, codes for the Cangjie hint |
| `schema/`   | hand-written: `*.schema.yaml`, `default.custom.yaml`, `lua/` |
| `prebuilt/` | generated dictionaries, so no source repo is needed; `SOURCE` says which commit |
| `rime/`     | build output (not tracked)                                |
| `test/`     | Docker console to try the schema without an input method  |
| `extra/trime/` | on-screen keyboard for Trime (Android), copied by hand |

## Build

```bash
./build.sh                    # prebuilt dictionaries (default)
./build.sh --rebuild          # regenerate from ../Mixed-Chinese-Keyboard-Plus-Dicts/v2.1
./build.sh --src DIR          # regenerate from another folder of .ms2 files, e.g. .../v2
./build.sh --out DIR          # write somewhere other than ./rime
./build.sh --update-prebuilt  # refresh prebuilt/ (then commit it)
./build.sh --space first      # space commits the first candidate (or --space-commits)
./build.sh --space raw        # space types the letters + a space (phones)
```

`--space` sets `mixed/space` in the built schema; the same can be done after
installing, see [Settings](#settings):

| mode    | space while typing                      | for                       |
|---------|-----------------------------------------|---------------------------|
| `page`  | next page, wraps to page 1 (default)    | Quick users with a keyboard |
| `first` | commits the first candidate             | Cangjie habits            |
| `raw`   | commits the letters you typed + a space | touch keyboards: tap Chinese in the candidate bar, space types English |

In `raw` mode punctuation is ASCII unless the character right before it is
Chinese: `hello` + `,` → `hello,`, 我 + `,` → 我，, `我 ` + `,` → `我 ,`.

`--rebuild` expects the dictionary repo next to this one:

```
some_dir/
  Mixed-Chinese-Keyboard-Plus-Dicts/   git clone https://github.com/holleeb/Mixed-Chinese-Keyboard-Plus-Dicts
  rime_mixed/
```

Regenerating needs only Python 3 and takes a few seconds.

The Cangjie hint's codes (`prebuilt/mixed_cangjie.txt`) come from the
`kCangjie` field of Unicode's
[Unihan database](https://www.unicode.org/Public/UCD/latest/ucd/Unihan.zip),
checked against the dictionary (Unihan has Cangjie 3; where the dictionary
lists the character under a close Cangjie 5 code, that one is used):

```bash
python3 cangjie.py --unihan Unihan.zip --dict prebuilt/mixed_quick.dict.yaml \
                   --out prebuilt/mixed_cangjie.txt
```

## Install

1. Install the frontend and the lua plugin, e.g. Ubuntu 24.04+:
   `sudo apt install fcitx5-rime librime-plugin-lua`
2. Copy `rime/` into the Rime user folder:

   | frontend    | folder                          |
   |-------------|---------------------------------|
   | fcitx5-rime | `~/.local/share/fcitx5/rime/`   |
   | ibus-rime   | `~/.config/ibus/rime/`          |
   | Weasel      | `%APPDATA%\Rime\`               |
   | Squirrel    | `~/Library/Rime/`               |

   ```bash
   rsync -av rime/ ~/.local/share/fcitx5/rime/          # local
   rsync -av rime/ host:.local/share/fcitx5/rime/       # another machine
   ```
   `default.custom.yaml` sets the schema list to just `mixed_quick`; if you
   already have one, merge it by hand.
3. Add Rime as an input method (`fcitx5-configtool`), then **Deploy** from
   the tray menu. The first deploy compiles 1.4 M entries and can take a minute.

Copying again later only replaces these files. Learned words (`*.userdb`)
and learned associated phrases (`mixed_predict.user.txt`) are kept.

### Android (Trime)

Tested with [Trime](https://github.com/osfans/trime) 3.3 (同文輸入法, GPL-3.0;
F-Droid, GitHub or Play Store), which includes librime-lua.

```bash
./build.sh --space raw --out rime_android
cp extra/trime/trime.custom.yaml rime_android/
```

1. In Trime, Profile: data storage *sync from external storage*, user
   directory e.g. `trime` (`Internal storage/trime/`).
2. Copy the contents of `rime_android/` there (USB file transfer, or
   `adb push rime_android/. /sdcard/trime/`).
3. Profile → **Sync user data immediately**: copies the folder into the app
   and deploys (there is no separate Deploy button). The first deploy takes
   a few minutes.
4. After changing a `lua/` script, also force stop Trime (Android Settings →
   Apps → Trime): the scripts stay loaded until the app restarts.

`trime.custom.yaml` adds a keyboard named after the schema, which Trime uses
for it: the 26-key qwerty layout where each letter key shows its long-press
symbol on top, the Cangjie radical in the middle (the letter in English
mode) and the letter at the bottom; long press `,` `.` for `，` `。`. It
replaces any `trime.custom.yaml` you already have; merge by hand if so.
Trime rewrites `default.custom.yaml` when you pick schemas in its settings.

The candidate bar scrolls sideways and takes taps, so `raw` space mode suits
it: space and punctuation type what you typed, tap to pick Chinese.

## Test without installing

`test/` builds an Ubuntu 24.04 image (librime 1.10 + lua plugin) with a small
console on the librime C API, and mounts `rime/` as the Rime user folder.
Nothing on the host's input method is touched.

```bash
./build.sh
test/run.sh build                  # once
test/run.sh test                   # interactive: type hi, 1, {space}, {Escape} ...
test/run.sh test qi 1 {space}      # one key sequence per argument
test/run.sh reset-learning         # forget what was learned (rime/*.userdb,
                                   # rime/mixed_predict.user.txt)
```

Each step prints the commit, the input and the candidate page (`page 2/3:`).
`RIME_DIR=dir test/run.sh ...` tests another folder.

## Keys

| key                  | typing                     | associated phrases          |
|----------------------|----------------------------|-----------------------------|
| 1-9                  | pick                       | pick, then chain            |
| space                | next page, wraps (*)       | next page, wraps (*)        |
| `-` `=` `,` `.` PgUp PgDn | page                  | page                        |
| Esc                  | clear input                | dismiss                     |
| BackSpace            | delete a letter            | dismiss                     |
| Return               | commit the letters         | dismiss, Return reaches the app |
| a letter             | type                       | dismiss, start typing       |

(*) With `mixed/space: first` space commits the first candidate; with `raw`
it commits the typed letters and a space. With either, space on associated
phrases dismisses them and types a space.

`.` pages forward while candidates are showing and `,` pages back from page 2;
otherwise they type `，` `。` as usual. These come from Rime's `default.yaml`.

## Settings

Change behaviour with a `mixed_quick.custom.yaml` next to the schema in your
Rime folder, then Deploy. `build.sh` never writes this file, so it survives
rebuilds and copies. All keys go under one `patch:`:

```yaml
# mixed_quick.custom.yaml
patch:
  # what space does while typing: page (default; next page, wraps),
  # first (commit the first candidate) or raw (commit the letters + a space)
  mixed/space: first

  # no suggestions after a commit (and no learning of them)
  mixed/associated_phrases: false

  # no Cangjie code shown after picking a character typed another way
  mixed/cangjie_hint: false

  # the radicals of the typed letters as a candidate ("mm": 一一, "hqi": 竹手戈):
  # its place in the list, 1 = first (default), 2 = second ...; 0 = off
  mixed/radical_candidate: 2

  # candidates per page (default 9; also set in default.custom.yaml for all schemas)
  menu/page_size: 6

  # only exact codes: typing "hq" no longer lists 我 (hqi) and longer words
  translator/enable_completion: false

  # keep completion but hide the "~xx" hint showing the rest of the code
  translator/comment_format:
    - xform/^~.*$//

  # stop learning: candidates stay in the dictionary's order
  translator/enable_user_dict: false

  # input line without the Cangjie radicals: "hqi" instead of "hqi 竹手戈"
  translator/preedit_format: []

  # more keys; appended to the defaults
  key_binder/bindings/+:
    - { when: paging,   accept: bracketleft,  send: Page_Up }    # [ previous page
    - { when: has_menu, accept: bracketright, send: Page_Down }  # ] next page
    - { when: has_menu, accept: semicolon,    send: 2 }          # ; second candidate
    - { when: has_menu, accept: apostrophe,   send: 3 }          # ' third candidate
```

`;` is also Rime's code delimiter; with the binding above it picks the second
candidate whenever candidates are showing.

### Suggested sets

**Quick (速成) users**, close to the Android app: the defaults. Optionally hide
the completion hints:

```yaml
patch:
  translator/comment_format:
    - xform/^~.*$//
```

**Cangjie (倉頡) users**: the dictionary already holds full Cangjie codes
(我 `hqi`, 時 `agdi`) ranked first, so type as usual. Space commits, and only
exact codes are listed:

```yaml
patch:
  mixed/space: first
  translator/enable_completion: false
  mixed/radical_candidate: 2      # else space commits 竹手戈 for hqi
```

Quick codes stay in the dictionary; a 1-2 letter code still lists the Quick
characters for it after the Cangjie ones (`ab`: 明 first, then 閒 晴 …). Rare
characters with a 1-2 letter Cangjie code can be on a later page; picking one
once moves it forward.

**Phone (Trime, fcitx5-android)**: no comfortable space-to-page, and the
candidate bar scrolls and takes taps. Space types what you typed, so English
needs no mode switch:

```yaml
patch:
  mixed/space: raw
```

## Source format

How the `.ms2` files are laid out is in the `convert.py` docstring and the
dictionary repo's `explain.md`. Only the traditional sections are used.

## Licence

Apache License 2.0, see [LICENSE](LICENSE).

The dictionaries in `prebuilt/` are generated from
[holleeb/Mixed-Chinese-Keyboard-Plus-Dicts](https://github.com/holleeb/Mixed-Chinese-Keyboard-Plus-Dicts),
also Apache-2.0; `prebuilt/SOURCE` names the commit they came from.

`prebuilt/mixed_cangjie.txt` is derived from the Unicode Character Database
(Unihan), © Unicode, Inc., under the
Unicode License v3 ([LICENSE-UNICODE.txt](LICENSE-UNICODE.txt)); its header names
the Unicode version.
