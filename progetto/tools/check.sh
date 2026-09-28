#!/usr/bin/env bash
# King's Domain project check for Linux / CI (same rules as tools/check.ps1): headless import, test suite,
# optional screenshot. Any engine ERROR line not in the expected list fails the check.
#   tools/check.sh                      import + all tests
#   tools/check.sh --skip-import --tests test_domain,test_save
#   tools/check.sh --skip-tests --shot local_far -- --kd-view=local --kd-camera=domain,4.5
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${KD_GODOT:-godot}"
SKIP_IMPORT=0; SKIP_TESTS=0; FILTER=""; SHOT=""; FRAMES=45; RES="1600x900"
EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-import) SKIP_IMPORT=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    --tests) FILTER="$2"; shift ;;
    --shot) SHOT="$2"; shift ;;
    --frames) FRAMES="$2"; shift ;;
    --resolution) RES="$2"; shift ;;
    --) shift; EXTRA=("$@"); break ;;
  esac
  shift
done
mkdir -p "$ROOT/logs"
FAILED=0
EXPECTED='SaveMigrator: missing save_version|SaveMigrator: save_version [0-9]+ is newer than the game|Scheduler: duplicate system id dup|SaveSystem: corrupted save user://tests/broken\.kds|SaveSystem: cannot open user://tests/broken\.kds'
# the painted UI kit is not part of the inspection pack: its absence is expected here, the code falls back
MISSING_KIT='Resource file not found: res://assets/ui/(kit|icons)/|Condition "status < 0" is true. Returning: ERR_CANT_OPEN|Could not set V-Sync'

script_errors() {
  grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|Compile Error|Invalid call|Cannot infer|Identifier .* not declared|^\s*ERROR:' "$1" \
    | grep -Ev "$EXPECTED" | grep -Ev "$MISSING_KIT" || true
}

if [ $SKIP_IMPORT -eq 0 ]; then
  echo "== Import =="
  "$GODOT" --headless --path "$ROOT" --import > "$ROOT/logs/import.log" 2>&1
  errs=$(script_errors "$ROOT/logs/import.log")
  if [ -n "$errs" ]; then echo "$errs"; FAILED=1; else echo "import ok"; fi
fi

if [ $SKIP_TESTS -eq 0 ]; then
  echo "== Tests =="
  args=(--headless --path "$ROOT" res://tests/test_runner.tscn)
  [ -n "$FILTER" ] && args+=(-- "--kd-test=$FILTER")
  "$GODOT" "${args[@]}" > "$ROOT/logs/tests.log" 2>&1
  code=$?
  grep -E '^\[FAIL\]|^FAILURE|^TESTS:' "$ROOT/logs/tests.log"
  errs=$(script_errors "$ROOT/logs/tests.log")
  if [ -n "$errs" ]; then echo "$errs"; FAILED=1; fi
  if [ $code -ne 0 ]; then echo "tests failed (exit $code)"; FAILED=1; else echo "tests ok"; fi
fi

if [ -n "$SHOT" ]; then
  echo "== Screenshot =="
  out="tests/output/$SHOT.png"
  xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" --path "$ROOT" --rendering-driver opengl3 --resolution "$RES" -- \
    "--kd-screenshot=$out" "--kd-frames=$FRAMES" --kd-no-autosave "${EXTRA[@]}" > "$ROOT/logs/screenshot_$SHOT.log" 2>&1
  code=$?
  errs=$(script_errors "$ROOT/logs/screenshot_$SHOT.log")
  if [ -n "$errs" ]; then echo "$errs"; FAILED=1; fi
  echo "screenshot -> $out (exit $code)"
fi

if [ $FAILED -ne 0 ]; then echo "CHECK FAILED"; exit 1; fi
echo "CHECK PASSED"
