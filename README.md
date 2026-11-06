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
- associated phrases after a commit: 我 → 的 人 會 …, chaining 我 → 不 → 能
- space pages forward and wraps to page 1; pick with 1-9

Works with any Rime frontend: fcitx5-rime, ibus-rime, Weasel (Windows),
Squirrel (macOS). Needs librime-lua for the last two items (Debian/Ubuntu:
`librime-plugin-lua`).

## Layout

| path        | what                                                      |
|-------------|-----------------------------------------------------------|
| `build.sh`  | assembles `rime/`, the folder you copy to your machine    |
| `convert.py`| `.ms2` dictionaries → Rime dictionaries                   |
| `schema/`   | hand-written: `*.schema.yaml`, `default.custom.yaml`, `lua/` |
| `prebuilt/` | generated dictionaries, so no source repo is needed; `SOURCE` says which commit |
| `rime/`     | build output (not tracked)                                |
| `test/`     | Docker console to try the schema without an input method  |

## Build

```bash
./build.sh                    # prebuilt dictionaries (default)
./build.sh --rebuild          # regenerate from ../Mixed-Chinese-Keyboard-Plus-Dicts/v2.1
./build.sh --src DIR          # regenerate from another folder of .ms2 files, e.g. .../v2
./build.sh --out DIR          # write somewhere other than ./rime
./build.sh --update-prebuilt  # refresh prebuilt/ (then commit it)
./build.sh --space-commits    # space commits the first candidate instead of paging
```

`--space-commits` is for people used to Cangjie, where code + space types the
character. It only flips `mixed/space_pages` in the built schema; the same
can be done after installing, see [Settings](#settings).

`--rebuild` expects the dictionary repo next to this one:

```
some_dir/
  Mixed-Chinese-Keyboard-Plus-Dicts/   git clone https://github.com/holleeb/Mixed-Chinese-Keyboard-Plus-Dicts
  rime_mixed/
```

Regenerating needs only Python 3 and takes a few seconds.

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
are kept.

## Test without installing

`test/` builds an Ubuntu 24.04 image (librime 1.10 + lua plugin) with a small
console on the librime C API, and mounts `rime/` as the Rime user folder.
Nothing on the host's input method is touched.

```bash
./build.sh
test/run.sh build                  # once
test/run.sh test                   # interactive: type hi, 1, {space}, {Escape} ...
test/run.sh test qi 1 {space}      # one key sequence per argument
test/run.sh reset-learning         # forget what was learned (deletes rime/*.userdb)
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

(*) With `space_pages: false`: space commits the first candidate, and on
associated phrases it dismisses them and types a space.

`.` pages forward while candidates are showing and `,` pages back from page 2;
otherwise they type `，` `。` as usual. These come from Rime's `default.yaml`.

## Settings

Change behaviour with a `mixed_quick.custom.yaml` next to the schema in your
Rime folder, then Deploy. `build.sh` never writes this file, so it survives
rebuilds and copies. All keys go under one `patch:`:

```yaml
# mixed_quick.custom.yaml
patch:
  # space commits the first candidate (default true: space = next page, wraps)
  mixed/space_pages: false

  # no suggestions after a commit
  mixed/associated_phrases: false

  # candidates per page (default 9; also set in default.custom.yaml for all schemas)
  menu/page_size: 6

  # only exact codes: typing "hq" no longer lists 我 (hqi) and longer words
  translator/enable_completion: false

  # keep completion but hide the "~xx" hint showing the rest of the code
  translator/comment_format:
    - xform/^~.*$//

  # stop learning: candidates stay in the dictionary's order
  translator/enable_user_dict: false

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
  mixed/space_pages: false
  translator/enable_completion: false
```

Quick codes stay in the dictionary; a 1-2 letter code still lists the Quick
characters for it after the Cangjie ones (`ab`: 明 first, then 閒 晴 …). Rare
characters with a 1-2 letter Cangjie code can be on a later page; picking one
once moves it forward.

## Source format

How the `.ms2` files are laid out is in the `convert.py` docstring and the
dictionary repo's `explain.md`. Only the traditional sections are used.

## Licence

Apache License 2.0, see [LICENSE](LICENSE).

The dictionaries in `prebuilt/` are generated from
[holleeb/Mixed-Chinese-Keyboard-Plus-Dicts](https://github.com/holleeb/Mixed-Chinese-Keyboard-Plus-Dicts),
also Apache-2.0; `prebuilt/SOURCE` names the commit they came from.
