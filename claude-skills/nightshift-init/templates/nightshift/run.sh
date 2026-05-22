#!/usr/bin/env bash
#
# nightshift/run.sh — autonomous overnight Night Shift loop (PORTABLE).
#
# This script is generic. All repo-specific settings live in
# nightshift/nightshift.conf — edit THAT, not this file. Installed/tailored by
# the /nightshift-init skill.
#
# Each iteration is a fresh `claude -p` session that does ONE task from
# nightshift/TODOS.md and (on green gates) commits it on a night-shift/<date>
# branch. Safety: branch-only (never main), never push, refuses a dirty tree,
# bounded by per-iter timeout + $ cap + max-turns + idle stop, and a denylist
# (base + DENY_EXTRA) that blocks destructive commands.
#
# Usage: bash nightshift/run.sh [--with-extra-dirs] [--dry-run]
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/nightshift.conf"

REPO_DIR="${REPO_DIR:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
DATE_TAG="$(date +%Y-%m-%d)"
BRANCH="night-shift/${DATE_TAG}"
LOG_DIR="${REPO_DIR}/nightshift/logs/${DATE_TAG}"
MAX_ITERS="${MAX_ITERS:-12}"
ITER_TIMEOUT="${ITER_TIMEOUT:-2400}"
ITER_BUDGET="${ITER_BUDGET:-4}"
ITER_MAX_TURNS="${ITER_MAX_TURNS:-120}"
MODEL="${MODEL:-sonnet}"             # lean default; set MODEL=opus in nightshift.conf for hard nights
IDLE_LIMIT="${IDLE_LIMIT:-2}"
LIMIT_BACKOFF="${LIMIT_BACKOFF:-1800}"       # seconds to wait when a usage limit is hit
MAX_LIMIT_RETRIES="${MAX_LIMIT_RETRIES:-12}" # max limit waits before giving up (~6h at 1800s)
# Markers meaning "account usage / rate / overload limit" — wait & retry.
# (Excludes the per-iteration --max-budget-usd cap, which is not an account limit.)
LIMIT_PATTERN='usage limit|rate.?limit|429|too many requests|limit reached|overloaded|service unavailable'
CONVENTIONS_DOC="${CONVENTIONS_DOC:-}"
ALLOW_EXTRA="${ALLOW_EXTRA:-}"
DENY_EXTRA="${DENY_EXTRA:-}"
EXTRA_DIRS="${EXTRA_DIRS:-}"
DOCKER_RESTART_SERVICES="${DOCKER_RESTART_SERVICES:-}"
GATES="${GATES:-}"

WITH_EXTRA_DIRS=0; DRY_RUN=0
for arg in "$@"; do case "$arg" in
  --with-extra-dirs|--with-frontend) WITH_EXTRA_DIRS=1;;
  --dry-run) DRY_RUN=1;;
  -h|--help) sed -n '2,16p' "$0"; exit 0;;
  *) echo "unknown arg: $arg" >&2; exit 2;;
esac; done
mkdir -p "$LOG_DIR"

# --- permissions: universal base + repo-specific extras from the .conf ---
BASE_ALLOW="Read,Edit,Write,Grep,Glob,TodoWrite,Task,\
Bash(git add *),Bash(git commit *),Bash(git status*),Bash(git diff*),\
Bash(git log*),Bash(git show*),Bash(git branch*),Bash(git rev-parse*),\
Bash(git switch night-shift/*),Bash(git checkout night-shift/*),\
Bash(grep *),Bash(rg *),Bash(ls *),Bash(cat *),Bash(head *),Bash(tail *),\
Bash(find *),Bash(wc *),Bash(echo *),Bash(sed -n *),Bash(awk *),Bash(jq *),\
Bash(curl -s http://localhost*),Bash(curl http://localhost*)"
BASE_DENY="Bash(git push*),Bash(git reset --hard*),Bash(git clean*),\
Bash(git stash*),Bash(git restore*),Bash(git switch main*),\
Bash(git switch master*),Bash(git checkout main*),Bash(git checkout master*),\
Bash(git checkout -- *),Bash(rm *),Bash(rmdir *),Bash(sudo *),\
Bash(*docker*down*),Bash(*docker*volume*),Bash(*docker*prune*),\
Bash(*docker*exec*),Bash(docker rm*),Bash(docker stop*),Bash(docker kill*)"
ALLOW="$BASE_ALLOW"; [ -n "$ALLOW_EXTRA" ] && ALLOW="${ALLOW},${ALLOW_EXTRA}"
DENY="$BASE_DENY";  [ -n "$DENY_EXTRA" ] && DENY="${DENY},${DENY_EXTRA}"
if [ -n "$DOCKER_RESTART_SERVICES" ]; then
  ALLOW="${ALLOW},Bash(docker-compose restart*),Bash(docker compose restart*),\
Bash(docker-compose ps*),Bash(docker compose ps*),Bash(docker-compose logs*),Bash(docker compose logs*)"
fi

# --- per-iteration prompt, built from the .conf ---
GATES_TEXT=""
if [ -n "$GATES" ]; then
  while IFS= read -r g; do
    [ -n "$g" ] && GATES_TEXT="${GATES_TEXT}       - ${g}"$'\n'
  done <<EOF
$GATES
EOF
fi
RESTART_TEXT=""
[ -n "$DOCKER_RESTART_SERVICES" ] && RESTART_TEXT="If you changed code run by these services, restart them BEFORE the gates so async paths test the new code: docker-compose restart ${DOCKER_RESTART_SERVICES} (never docker-compose down)."
CONV_TEXT=""
[ -n "$CONVENTIONS_DOC" ] && CONV_TEXT="Honor every rule in ${CONVENTIONS_DOC} — it is the contract for this repo."

LOOP_PROMPT="You are the NIGHT SHIFT agent for $(basename "$REPO_DIR").

Read nightshift/AGENT_LOOP.md and follow it EXACTLY. ${CONV_TEXT}

Do ONE unit of work from nightshift/TODOS.md this session, then stop:
  1. Pick the highest-priority unchecked task.
  2. Execute it — write/repair tests FIRST, then make the root-cause change.
  3. Gates that MUST pass before you commit:
${GATES_TEXT}  ${RESTART_TEXT}
  4. On green: check the task off in nightshift/TODOS.md, append a CHANGELOG.md
     entry, and commit that ONE unit of work with a detailed message.
  5. Append unrelated discoveries as new unchecked tasks in TODOS.md.

HARD RULES (a violation is a failed shift):
  - You are on a night-shift/<date> branch. NEVER switch to or commit on main.
  - NEVER push. NEVER run the destructive commands the runner blocks.
  - Your only git writes are add + commit on the current branch.

If no unchecked tasks remain, write nightshift/REPORT.md (a morning recap) and
print the single token NIGHT_SHIFT_DONE on its own line, then stop."

# --- repo guard: refuse main, refuse dirty, ensure the night-shift branch ---
prepare_repo() {
  local dir="$1" label="$2"
  pushd "$dir" >/dev/null || { echo "[nightshift] missing dir: $dir" >&2; return 1; }
  local cur; cur="$(git branch --show-current)"
  if [ -n "$(git status --porcelain)" ]; then
    echo "[nightshift] ABORT: $label ($dir) has uncommitted changes. Commit or" >&2
    echo "             stash YOUR work first — Night Shift won't touch a dirty tree." >&2
    git status --short >&2; popd >/dev/null; return 1
  fi
  if [ "$cur" = "main" ] || [ "$cur" = "master" ]; then
    git switch -c "$BRANCH" 2>/dev/null || git switch "$BRANCH"
  elif [ "$cur" != "$BRANCH" ]; then
    echo "[nightshift] ABORT: $label on '$cur'; expected main/master or $BRANCH." >&2
    popd >/dev/null; return 1
  fi
  echo "[nightshift] $label ready on $(git branch --show-current)"; popd >/dev/null
}
remaining_tasks() { grep -c '^- \[ \]' "${REPO_DIR}/nightshift/TODOS.md" 2>/dev/null || echo 0; }
md5_of() { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | awk '{print $1}'; }

# Commit any uncommitted work left by an interrupted/limited iteration so the
# next attempt starts on a clean tree and nothing is lost. Marked needs-review.
# Covers the main repo + any --add-dir extra repos.
snapshot_partial() {
  local d dirs="$REPO_DIR"
  [ "$WITH_EXTRA_DIRS" = "1" ] && [ -n "$EXTRA_DIRS" ] && dirs="$dirs $EXTRA_DIRS"
  for d in $dirs; do
    if [ -n "$(git -C "$d" status --porcelain)" ]; then
      git -C "$d" add -A
      git -C "$d" commit -q \
        -m "wip(nightshift): partial snapshot — needs review" \
        -m "Auto-saved by nightshift/run.sh after an interrupted or rate-limited iteration. Review and keep, fold into the real task commit, or drop in the morning."
      echo "[nightshift] snapshotted partial work in $(basename "$d")"
    fi
  done
}

# Decide how long to sleep after a usage limit. Tries to parse a reset epoch
# from the limit message and sleeps exactly until then (+60s); falls back to
# LIMIT_BACKOFF; capped at 6h. Echoes seconds to stdout; logs to stderr.
compute_limit_sleep() {
  local logf="$1" now epoch secs
  now="$(date +%s)"
  epoch="$(grep -aoiE '(reset|resets_at|resetsat|retry[_-]?after)[^0-9]{0,24}[0-9]{10}' "$logf" 2>/dev/null \
            | grep -oE '[0-9]{10}' | sort -nr | head -1)"
  if [ -n "$epoch" ] && [ "$epoch" -gt "$now" ] && [ "$epoch" -lt $((now + 86400)) ]; then
    secs=$(( epoch - now + 60 ))
    echo "[nightshift] parsed reset epoch ${epoch}; sleeping until reset (+60s)." >&2
  else
    secs="$LIMIT_BACKOFF"
    echo "[nightshift] no reset time parsed; using fixed backoff ${LIMIT_BACKOFF}s." >&2
  fi
  [ "$secs" -gt 21600 ] && secs=21600
  [ "$secs" -lt 60 ] && secs=60
  echo "$secs"
}

# Sleep in chunks with a heartbeat so a long limit-wait doesn't look frozen.
sleep_with_heartbeat() {
  local left="$1" chunk=300 nap
  while [ "$left" -gt 0 ]; do
    nap="$chunk"; [ "$left" -lt "$chunk" ] && nap="$left"
    sleep "$nap"; left=$((left - nap))
    [ "$left" -gt 0 ] && echo "[nightshift] …still waiting on limit reset: ~$((left/60))m left ($(date '+%H:%M:%S'))"
  done
}

cd "$REPO_DIR"
echo "════════════════════════════════════════════════════════════════"
echo " NIGHT SHIFT  ${DATE_TAG}  branch=${BRANCH}  repo=$(basename "$REPO_DIR")"
echo " logs: ${LOG_DIR}"
echo "════════════════════════════════════════════════════════════════"
prepare_repo "$REPO_DIR" "repo" || exit 1

# Build the claude args once (always non-empty → no empty-array hazard on bash 3.2)
CLAUDE_ARGS=(--model "$MODEL" --permission-mode acceptEdits
  --allowedTools "$ALLOW" --disallowedTools "$DENY"
  --max-turns "$ITER_MAX_TURNS" --max-budget-usd "$ITER_BUDGET"
  --output-format stream-json --verbose)
if [ "$WITH_EXTRA_DIRS" = "1" ] && [ -n "$EXTRA_DIRS" ]; then
  for d in $EXTRA_DIRS; do
    prepare_repo "$d" "extra-dir" || exit 1
    CLAUDE_ARGS+=(--add-dir "$d")
  done
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "[dry-run] $(remaining_tasks) task(s) pending; up to ${MAX_ITERS} iterations."
  echo "[dry-run] gates:"; printf '%s' "$GATES_TEXT"
  echo "[dry-run] ALLOW=${ALLOW}"; echo ""; echo "[dry-run] DENY=${DENY}"; exit 0
fi

iter=0           # completed (non-waited) iterations
idle=0           # consecutive no-progress iterations
limit_retries=0  # consecutive usage-limit waits
while [ "$iter" -lt "$MAX_ITERS" ]; do
  pending="$(remaining_tasks)"
  echo ""; echo "──── attempt $((iter+1)) (done=${iter}/${MAX_ITERS})  ($(date '+%H:%M:%S'))  pending=${pending} ────"
  [ "$pending" -eq 0 ] && { echo "[nightshift] no tasks left — stopping."; break; }
  todos_before="$(md5_of "${REPO_DIR}/nightshift/TODOS.md")"
  log="${LOG_DIR}/iter_$((iter+1))_$(date '+%H%M%S').jsonl"

  timeout "$ITER_TIMEOUT" claude -p "$LOOP_PROMPT" "${CLAUDE_ARGS[@]}" 2>&1 | tee "$log"

  # 1) Always rescue any uncommitted work so the tree is clean for the next run.
  snapshot_partial

  # 2) Usage / rate / overload limit? Wait and retry WITHOUT consuming an
  #    iteration — this is how the run survives a mid-night limit reset.
  if grep -qiE "$LIMIT_PATTERN" "$log"; then
    limit_retries=$((limit_retries + 1))
    if [ "$limit_retries" -gt "$MAX_LIMIT_RETRIES" ]; then
      echo "[nightshift] usage limit still active after ${MAX_LIMIT_RETRIES} waits — stopping."; break
    fi
    wait_secs="$(compute_limit_sleep "$log")"
    echo "[nightshift] usage/rate limit detected — sleeping ${wait_secs}s (~$((wait_secs/60))m) then retrying (wait ${limit_retries}/${MAX_LIMIT_RETRIES})."
    sleep_with_heartbeat "$wait_secs"
    continue
  fi
  limit_retries=0
  iter=$((iter + 1))

  # Only the agent's FINAL result message counts — not the prompt echo or
  # AGENT_LOOP.md content (both contain the token and would false-trigger).
  if grep -a '"type":"result"' "$log" | tail -1 | grep -q 'NIGHT_SHIFT_DONE'; then
    echo "[nightshift] agent signalled NIGHT_SHIFT_DONE — stopping."; break
  fi

  # 3) Progress = a task was checked off in TODOS.md (HEAD alone is unreliable
  #    now that partial snapshots can advance it).
  todos_after="$(md5_of "${REPO_DIR}/nightshift/TODOS.md")"
  if [ "$todos_before" = "$todos_after" ]; then
    idle=$((idle + 1)); echo "[nightshift] no TODOS progress this iteration (idle=${idle}/${IDLE_LIMIT})."
    [ "$idle" -ge "$IDLE_LIMIT" ] && { echo "[nightshift] idle limit hit — stopping."; break; }
  else idle=0; fi
done

echo ""; echo "════════════════════════════════════════════════════════════════"
echo " NIGHT SHIFT complete  $(date '+%H:%M:%S'). Commits this shift:"
git log --oneline "${BRANCH}" --not main master 2>/dev/null | sed 's/^/   /'
echo " Review: nightshift/REPORT.md + nightshift/CHANGELOG.md + logs/${DATE_TAG}/"
echo "════════════════════════════════════════════════════════════════"
