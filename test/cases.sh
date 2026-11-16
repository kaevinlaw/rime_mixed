#!/usr/bin/env bash
# Regression cases for the schemas, run on the Docker test bench (run.sh).
#
#   ./cases.sh              build, run every case, delete the work folders
#   ./cases.sh --keep       keep test/.work/ (later runs skip build and deploy)
#   ./cases.sh PATTERN      only the cases whose name matches PATTERN (grep -E)
#
# Each case starts from a fresh state: learning (*.userdb,
# mixed_predict.user.txt) and settings (mixed_*.custom.yaml) are removed first.
# A build variant (build.sh options) gets its own folder, built and deployed
# once: test/.work/<variant>/. Needs the image: ./run.sh build.
#
# A case:
#
#   tc NAME SCHEMA [options] -- KEYS...
#
#   --build "OPTS"   build.sh options (default: none)
#   --set KEY=VALUE  a setting, written to SCHEMA.custom.yaml (repeatable)
#   KEYS             one argument per bench step, as for run.sh test
#
# then checks, each on the output of one step (default: the last; --step N
# for the Nth, counting from 1):
#
#   has REGEX        the step's output matches (grep -P)
#   not REGEX        it does not
#   learned "A→B N ..."  the associated phrases learned, exactly (pairs
#                    with count, space separated; "" = none), after all steps
#   userdb DICT REGEX    Rime's learned words for DICT (rime_dict_manager
#                    export) match, after all steps
#
# Example:
#
#   tc "fuzzy: one key off" mixed_cangjie -- hqo
#   has '1\.竹手人 2\.失 3\.我 '
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
WORK="$HERE/.work"
IMAGE=rime-mixed-test
KEEP=0
FILTER=""
for a in "$@"; do
	case "$a" in
		--keep) KEEP=1 ;;
		-h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
		*) FILTER="$a" ;;
	esac
done

pass=0 fail=0 skipped=0
failed=()
CUR="" OUT="" DIR="" SCHEMA="" SKIP=0

# the folder for a build variant, built on first use
variant_dir() {
	local opts="$1" name
	name="$(echo "${opts:-default}" | tr -c 'a-z0-9\n' '_')"
	local dir="$WORK/$name"
	if [ ! -f "$dir/.built" ]; then
		rm -rf "$dir"
		mkdir -p "$dir"
		# shellcheck disable=SC2086
		"$REPO/build.sh" --out "$dir" $opts >/dev/null || { echo "build.sh $opts failed" >&2; exit 1; }
		touch "$dir/.built"
	fi
	echo "$dir"
}

bench() {
	docker run --rm -i -u "$(id -u):$(id -g)" -v "$DIR:/rime" "$@"
}

ok() { pass=$((pass + 1)); }
bad() {
	fail=$((fail + 1))
	failed+=("$CUR")
	echo "FAIL  $CUR: $1"
	[ -n "${2:-}" ] && echo "$2" | sed 's/^/        /'
}

# output of step N (1-based), or of the last step
step_out() {
	local n="${1:-0}"
	awk -v n="$n" '
		/^> / { s++ }
		{ if (s > 0) out[s] = out[s] $0 "\n" }
		END { if (n == 0) n = s; printf "%s", out[n] }' <<<"$OUT"
}

STEP=0
tc() {
	CUR="$1" SCHEMA="$2"
	shift 2
	local build="" sets=()
	while [ $# -gt 0 ] && [ "$1" != "--" ]; do
		case "$1" in
			--build) build="$2"; shift 2 ;;
			--set) sets+=("$2"); shift 2 ;;
			*) echo "tc $CUR: unknown option $1" >&2; exit 2 ;;
		esac
	done
	shift
	STEP=0
	if [ -n "$FILTER" ] && ! grep -qE "$FILTER" <<<"$CUR"; then
		SKIP=1
		skipped=$((skipped + 1))
		return
	fi
	SKIP=0
	DIR="$(variant_dir "$build")"
	rm -rf "$DIR"/*.userdb "$DIR"/mixed_predict.user.txt \
		"$DIR"/mixed_quick.custom.yaml "$DIR"/mixed_cangjie.custom.yaml
	if [ ${#sets[@]} -gt 0 ]; then
		{
			echo "patch:"
			for kv in "${sets[@]}"; do
				echo "  ${kv%%=*}: ${kv#*=}"
			done
		} > "$DIR/$SCHEMA.custom.yaml"
	fi
	OUT="$(bench "$IMAGE" -s "$SCHEMA" "$@" 2>&1 | grep -v '^[EWI][0-9]')"
	# every key step must have run, or checks such as `learned ""` pass on nothing
	local steps
	steps="$(grep -c '^> ' <<<"$OUT")"
	if [ "$steps" -ne $# ] || grep -q 'cannot select schema' <<<"$OUT"; then
		bad "the bench ran $steps of $# steps" "$OUT"
	fi
}

step() { STEP="$1"; }

has() {
	[ "$SKIP" = 1 ] && return
	local s
	s="$(step_out "$STEP")"
	if grep -qP -- "$1" <<<"$s"; then ok; else bad "step ${STEP/#0/last} lacks /$1/" "$s"; fi
}

not() {
	[ "$SKIP" = 1 ] && return
	local s
	s="$(step_out "$STEP")"
	if ! grep -qE '^(page |commit: )' <<<"$s"; then
		bad "step ${STEP/#0/last} shows nothing, so /$1/ proves nothing" "$s"
	elif grep -qP -- "$1" <<<"$s"; then bad "step ${STEP/#0/last} has /$1/" "$s"; else ok; fi
}

# the learned associated phrases, as the loader reads them: the last line
# for each pair wins, count 0 = deleted
learned() {
	[ "$SKIP" = 1 ] && return
	local got want
	got="$(awk -F'\t' '{ v[$1 "→" $2] = $3 } END { for (k in v) if (v[k] > 0) print k, v[k] }' \
		"$DIR/mixed_predict.user.txt" 2>/dev/null | sort | paste -sd' ')"
	want=""
	[ -n "$1" ] && want="$(tr ' ' '\n' <<<"$1" | paste -d' ' - - | sort | paste -sd' ')"
	if [ "$got" = "$want" ]; then ok; else bad "learned: want '$want', got '$got'"; fi
}

userdb() {
	[ "$SKIP" = 1 ] && return
	local got
	got="$(bench --entrypoint sh "$IMAGE" -c \
		"rime_dict_manager -e $1 /tmp/x.txt >/dev/null 2>&1; grep -v '^#' /tmp/x.txt")"
	if grep -qP -- "$2" <<<"$got"; then ok; else bad "userdb $1 lacks /$2/" "$got"; fi
}

docker image inspect "$IMAGE" >/dev/null 2>&1 || { echo "no image $IMAGE: ./run.sh build" >&2; exit 1; }

# shellcheck source=cases.txt
source "$HERE/cases.txt"

[ "$KEEP" = 1 ] || rm -rf "$WORK"
echo "$pass passed, $fail failed$([ "$skipped" -gt 0 ] && echo ", $skipped cases skipped")"
for f in "${failed[@]}"; do echo "  failed: $f"; done
[ "$fail" -eq 0 ]
