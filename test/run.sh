#!/usr/bin/env bash
# Build and run the Rime test bench. Never touches the host's fcitx5/Rime.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="rime-mixed-test"
RIME_DIR="${RIME_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)/rime}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [command]

  build            Build the image
  test [keys ...]  Run rime_test: interactive without keys, else one
                   key sequence per argument (default)
  shell            Interactive bash inside the container
  reset-learning   Delete the learned user dictionaries (*.userdb)

Environment:
  RIME_DIR   Rime user data folder mounted at /rime
             (default: ../rime, the build output)

Examples:
  ./run.sh build
  ./run.sh test                      # type hi, 3, {space} ...
  ./run.sh test hi 3 hi {Escape}     # pick 我 for hi, then look again
USAGE
}

run_container() {
  docker run --rm -i $([ -t 0 ] && echo -t) \
    -u "$(id -u):$(id -g)" \
    -v "${RIME_DIR}:/rime" \
    "$@"
}

cmd="${1:-test}"
shift || true

case "$cmd" in
  -h|--help|help) usage ;;
  build)          docker build -t "$IMAGE_NAME" "$SCRIPT_DIR" ;;
  test)           run_container "$IMAGE_NAME" "$@" ;;
  shell)          run_container --entrypoint bash "$IMAGE_NAME" ;;
  reset-learning) rm -rf "${RIME_DIR}"/*.userdb && echo "learning reset" ;;
  *)              echo "Unknown command: $cmd"; usage; exit 1 ;;
esac
