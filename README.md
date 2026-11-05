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
```

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

| key                | typing                     | associated phrases          |
|--------------------|----------------------------|-----------------------------|
| 1-9                | pick                       | pick, then chain            |
| space              | next page, wraps           | next page, wraps            |
| `-` `=` PgUp PgDn  | page                       | page                        |
| Esc                | clear input                | dismiss                     |
| BackSpace          | delete a letter            | dismiss                     |
| Return             | commit the letters         | dismiss, Return reaches the app |
| a letter           | type                       | dismiss, start typing       |

## Source format

How the `.ms2` files are laid out is in the `convert.py` docstring and the
dictionary repo's `explain.md`. Only the traditional sections are used.

## Licence

Apache License 2.0, see [LICENSE](LICENSE).

The dictionaries in `prebuilt/` are generated from
[holleeb/Mixed-Chinese-Keyboard-Plus-Dicts](https://github.com/holleeb/Mixed-Chinese-Keyboard-Plus-Dicts),
also Apache-2.0; `prebuilt/SOURCE` names the commit they came from.
