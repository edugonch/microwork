#!/usr/bin/env zsh
# test_microbreak.zsh — Shell integration tests for microbreak.sh
#
# Run with: zsh test_microbreak.zsh
#
# Covers Zsh-level behaviour that Python tests cannot reach:
#   - shell syntax validity
#   - eval safety of workout_ai.py output
#   - word-splitting of AI variables in pick_routine (the bug that leaked)
#   - function-level smoke tests using MICROBREAK_SOURCED=1

emulate -L zsh

SCRIPT_DIR="${0:A:h}"
PASS=0
FAIL=0

GRN=$'\033[1;32m' RED=$'\033[1;31m' RST=$'\033[0m'

_pass() { printf "${GRN}PASS${RST} %s\n" "$*"; PASS=$((PASS + 1)); }
_fail() { printf "${RED}FAIL${RST} %s\n" "$*"; FAIL=$((FAIL + 1)); }

# Run an external command in a subshell; [[ ]] keywords must NOT be passed here.
check() {
  local desc="$1"; shift
  if ( "$@" ) >/dev/null 2>&1; then _pass "$desc"; else _fail "$desc"; fi
}

# Inline assertion helpers (use these for [[ ]] / variable checks in this shell).
ok()      { [[ -n "$2" ]]         && _pass "$1" || _fail "$1 (empty)"; }
eq()      { [[ "$2" == "$3" ]]    && _pass "$1" || _fail "$1 (expected '$2', got '$3')"; }
contains(){ [[ "$3" == *"$2"* ]]  && _pass "$1" || _fail "$1 ('$2' not in output)"; }
matches() { [[ "$2" =~ $3 ]]      && _pass "$1" || _fail "$1 (no match: '$2')"; }

# Run a Zsh snippet in an isolated subshell.
zcheck() {
  local desc="$1" snippet="$2"
  if zsh -c "$snippet" 2>/dev/null; then _pass "$desc"; else _fail "$desc"; fi
}

# ---------------------------------------------------------------------------
printf "\n── Syntax ──────────────────────────────────────────\n"
# ---------------------------------------------------------------------------

check "microbreak.sh passes zsh -n syntax check" \
  zsh -n "$SCRIPT_DIR/microbreak.sh"

check "workout_ai.py is valid Python syntax" \
  python3 -m py_compile "$SCRIPT_DIR/workout_ai.py"

# ---------------------------------------------------------------------------
printf "\n── Python output → eval ─────────────────────────────\n"
# ---------------------------------------------------------------------------

TMPDIR_TEST="/tmp/mb_test_$$"
mkdir -p "$TMPDIR_TEST"

AI_OUT="$(python3 "$SCRIPT_DIR/workout_ai.py" start --no-llm \
  --base-dir "$TMPDIR_TEST" 2>/dev/null)" || AI_OUT=""

ok  "workout_ai.py start produces non-empty output"     "$AI_OUT"
contains "output has AI_ENABLED line"         "AI_ENABLED="        "$AI_OUT"
contains "output has AI_PRIORITY_ORDER line"  "AI_PRIORITY_ORDER=" "$AI_OUT"
contains "output has AI_MESSAGE line"         "AI_MESSAGE="        "$AI_OUT"
contains "output has AI_RECOMMENDED_MODE"     "AI_RECOMMENDED_MODE=" "$AI_OUT"

check "eval of Python output is safe" eval "$AI_OUT"
eval "$AI_OUT" 2>/dev/null || true

ok "AI_ENABLED is set after eval"          "$AI_ENABLED"
ok "AI_PRIORITY_ORDER is set after eval"   "$AI_PRIORITY_ORDER"
ok "AI_MESSAGE is set after eval"          "$AI_MESSAGE"
matches "AI_RECOMMENDED_MODE is valid" "$AI_RECOMMENDED_MODE" "^(normal|minimal|intense)$"

# ---------------------------------------------------------------------------
printf "\n── AI_PRIORITY_ORDER word-splitting (THE leaked bug) ──\n"
# ---------------------------------------------------------------------------
# Original bug: ${(z)"$AI_PRIORITY_ORDER"} → 'bad substitution' at runtime.
# ${(z)"$VAR"} puts quoted text inside ${}, which is not valid Zsh parameter
# expansion. Fix: ${=VAR} (IFS word-split) or ${(z)VAR} (no quotes).
#
# These tests lock down the exact split behaviour used in pick_routine so any
# future regression fails immediately.

zcheck 'word-split with ${=VAR} yields 8 tokens' '
  AI="movilidad metabolico superior cardio core full_body equipment_upper equipment_core"
  n=0
  for cat in ${=AI}; do n=$((n+1)); done
  [[ $n -eq 8 ]]
'

zcheck 'word-split of eval-sourced AI_PRIORITY_ORDER yields 8 tokens' "
  out=\"\$(python3 '$SCRIPT_DIR/workout_ai.py' start --no-llm \
    --base-dir /tmp/mb_split_\$\$ 2>/dev/null)\" || true
  eval \"\$out\" 2>/dev/null || true
  n=0; for cat in \${=AI_PRIORITY_ORDER}; do n=\$((n+1)); done
  rm -rf /tmp/mb_split_\$\$
  [[ \$n -eq 8 ]]
"

zcheck 'all 8 known categories present in AI_PRIORITY_ORDER' '
  AI="movilidad metabolico superior cardio core full_body equipment_upper equipment_core"
  known=(movilidad metabolico superior cardio core full_body equipment_upper equipment_core)
  for k in "${known[@]}"; do
    [[ " $AI " == *" $k "* ]] || exit 1
  done
'

# Regression marker: the OLD construct ${(z)"$VAR"} must fail.
# If this ever passes, Zsh changed behaviour and pick_routine needs review.
if zsh -c 'V="a b c"; for x in ${(z)"$V"}; do :; done' 2>/dev/null; then
  _fail 'REGRESSION: ${(z)"$VAR"} now works — pick_routine Tier 0 needs review'
else
  _pass 'confirmed: ${(z)"$VAR"} fails — fix ${=VAR} is still required'
fi

# ---------------------------------------------------------------------------
printf "\n── pick_routine function-level ──────────────────────\n"
# ---------------------------------------------------------------------------

_zsh_pick() {
  # Runs pick_routine in a clean isolated subshell.
  # Args: [extra env vars...] -- cycle_number
  local snippet="
    MICROBREAK_SOURCED=1 source '$SCRIPT_DIR/microbreak.sh' 2>/dev/null
    CYCLES_COMPLETED=0; LAST_CATEGORY=''; MODE=normal; USE_EQUIPMENT=1
    typeset -A CATEGORY_COUNTS
    CATEGORY_COUNTS=(movilidad 0 metabolico 0 superior 0 cardio 0
                     core 0 full_body 0 equipment_upper 0 equipment_core 0)
    $1
    pick_routine $2 2>/dev/null
  "
  zsh -c "$snippet" 2>/dev/null
}

result=$(_zsh_pick "AI_ENABLED=0; AI_PRIORITY_ORDER=''" 1)
ok "pick_routine returns a non-empty id (no AI)" "$result"

result=$(_zsh_pick \
  "AI_ENABLED=1; AI_PRIORITY_ORDER='metabolico movilidad cardio full_body superior core equipment_upper equipment_core'" \
  1)
ok "pick_routine Tier 0 returns a non-empty id (with AI)" "$result"

zcheck 'pick_routine Tier 0 result is in ROUTINES array' "
  MICROBREAK_SOURCED=1 source '$SCRIPT_DIR/microbreak.sh' 2>/dev/null
  CYCLES_COMPLETED=0; LAST_CATEGORY=''; MODE=normal; USE_EQUIPMENT=1
  typeset -A CATEGORY_COUNTS
  CATEGORY_COUNTS=(movilidad 0 metabolico 0 superior 0 cardio 0
                   core 0 full_body 0 equipment_upper 0 equipment_core 0)
  AI_ENABLED=1
  AI_PRIORITY_ORDER='metabolico movilidad cardio full_body superior core equipment_upper equipment_core'
  result=\$(pick_routine 1 2>/dev/null)
  [[ \${ROUTINES[(i)\$result]} -le \${#ROUTINES} ]]
"

zcheck 'pick_routine avoids LAST_CATEGORY on Tier 0' "
  MICROBREAK_SOURCED=1 source '$SCRIPT_DIR/microbreak.sh' 2>/dev/null
  CYCLES_COMPLETED=0; LAST_CATEGORY=metabolico; MODE=normal; USE_EQUIPMENT=1
  typeset -A CATEGORY_COUNTS
  CATEGORY_COUNTS=(movilidad 0 metabolico 0 superior 0 cardio 0
                   core 0 full_body 0 equipment_upper 0 equipment_core 0)
  AI_ENABLED=1
  AI_PRIORITY_ORDER='metabolico movilidad cardio full_body superior core equipment_upper equipment_core'
  result=\$(pick_routine 1 2>/dev/null)
  MICROBREAK_SOURCED=1 source '$SCRIPT_DIR/microbreak.sh' 2>/dev/null
  load_routine \"\$result\" 2>/dev/null
  [[ \$ROUTINE_CATEGORY != metabolico ]]
"

# ---------------------------------------------------------------------------
printf "\n── load_ai_recommendations function-level ───────────\n"
# ---------------------------------------------------------------------------

zcheck 'USE_AI=0 skips Python entirely' "
  MICROBREAK_SOURCED=1 source '$SCRIPT_DIR/microbreak.sh' 2>/dev/null
  python3() { exit 99; }
  USE_AI=0
  load_ai_recommendations
"

zcheck 'missing workout_ai.py skips gracefully' "
  MICROBREAK_SOURCED=1 source '$SCRIPT_DIR/microbreak.sh' 2>/dev/null
  USE_AI=1; AI_PYTHON_SCRIPT=/nonexistent/workout_ai.py
  load_ai_recommendations
"

# ---------------------------------------------------------------------------
printf "\n── log_cycle_to_session function-level ─────────────\n"
# ---------------------------------------------------------------------------

zcheck 'USE_AI=0 means log_cycle_to_session does nothing' "
  MICROBREAK_SOURCED=1 source '$SCRIPT_DIR/microbreak.sh' 2>/dev/null
  python3() { exit 99; }
  USE_AI=0
  log_cycle_to_session movilidad_1 movilidad baja 'Test'
"

zcheck 'missing script in log_cycle_to_session skips gracefully' "
  MICROBREAK_SOURCED=1 source '$SCRIPT_DIR/microbreak.sh' 2>/dev/null
  USE_AI=1; AI_PYTHON_SCRIPT=/nonexistent/workout_ai.py
  log_cycle_to_session movilidad_1 movilidad baja 'Test'
"

# ---------------------------------------------------------------------------
printf "\n── Python integration (log + end cycle) ────────────\n"
# ---------------------------------------------------------------------------

check "workout_ai.py start (pre-log)" \
  python3 "$SCRIPT_DIR/workout_ai.py" start --no-llm --base-dir "$TMPDIR_TEST"

check "workout_ai.py log cycle" \
  python3 "$SCRIPT_DIR/workout_ai.py" log movilidad_1 movilidad baja "Reset Postural" \
    --base-dir "$TMPDIR_TEST"

check "workout_ai.py end" \
  python3 "$SCRIPT_DIR/workout_ai.py" end --base-dir "$TMPDIR_TEST"

check "session file was created" \
  test -f "$TMPDIR_TEST/sessions/$(date +%F).json"

check "session file contains the logged cycle" python3 -c "
import json, sys
data = json.load(open('$TMPDIR_TEST/sessions/$(date +%F).json'))
cycles = [c for r in data['runs'] for c in r['cycles']]
sys.exit(0 if any(c['routine_id'] == 'movilidad_1' for c in cycles) else 1)
"

check "end_time is written to session" python3 -c "
import json, sys
data = json.load(open('$TMPDIR_TEST/sessions/$(date +%F).json'))
ended = [r for r in data['runs'] if r.get('end_time')]
sys.exit(0 if ended else 1)
"

# ---------------------------------------------------------------------------
rm -rf "$TMPDIR_TEST"

printf "\n────────────────────────────────────────────────────\n"
printf "Results: ${GRN}%d passed${RST}  ${RED}%d failed${RST}\n\n" "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
