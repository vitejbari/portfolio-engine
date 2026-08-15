#!/usr/bin/env bash
# Quality gate for portfolio repos.
#
# Run from the root of a TARGET repo (clinical-llm-eval, ml-lab, ...), not from the
# orchestrator. Every check runs even after an earlier one fails, so a single run
# reports the full list of problems rather than one at a time.
#
# The gate encodes the parts of CLAUDE.md that can be checked mechanically. It is
# deliberately blunt: the point is that a hollow or unsafe commit cannot land while
# nobody is watching.
#
# Configuration (environment):
#   QG_MIN_COVERAGE   minimum % coverage on src/            (default 80)
#   QG_BASE_REF       ref to diff against for size checks   (default origin/main)
#   QG_MAX_FILE_KB    reject any tracked file larger        (default 1024)
#   QG_DENYLIST       extra newline-separated regexes file  (default .quality-gate-denylist)
#   QG_SKIP           comma-separated check names to skip   (default empty)
#                     names: structure,lint,format,types,tests,readme,data,logging,
#                            results,denylist,substance
#
# Exit 0 = safe to commit. Exit 1 = do not commit.

set -uo pipefail

# A repo may declare its own defaults in .quality-gate.env — needed because not
# every target is a src/-layout Python package (the orchestrator itself is not).
# Write entries as `: "${QG_SKIP:=lint,types}"` so that a value already present
# in the environment wins and CI can still override per run.
if [[ -f .quality-gate.env ]]; then
  # shellcheck disable=SC1091
  set -a; source ./.quality-gate.env; set +a
fi

MIN_COVERAGE="${QG_MIN_COVERAGE:-80}"
BASE_REF="${QG_BASE_REF:-origin/main}"
MAX_FILE_KB="${QG_MAX_FILE_KB:-1024}"
DENYLIST_FILE="${QG_DENYLIST:-.quality-gate-denylist}"
SKIP="${QG_SKIP:-}"

FAILURES=()
WARNINGS=()

if [[ -t 1 ]]; then
  RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; OFF=$'\033[0m'
else
  RED=""; YEL=""; GRN=""; DIM=""; OFF=""
fi

fail()  { FAILURES+=("$1"); printf '%s FAIL %s %s\n' "$RED" "$OFF" "$1"; }
warn()  { WARNINGS+=("$1"); printf '%s WARN %s %s\n' "$YEL" "$OFF" "$1"; }
pass()  { printf '%s PASS %s %s\n' "$GRN" "$OFF" "$1"; }
note()  { printf '%s      %s%s\n' "$DIM" "$1" "$OFF"; }

skipped() {
  case ",$SKIP," in *",$1,"*) note "skipping $1 (QG_SKIP)"; return 0 ;; *) return 1 ;; esac
}

have() { command -v "$1" >/dev/null 2>&1; }

# uv run is preferred so the checks use the project's own pinned toolchain rather
# than whatever happens to be on PATH in the runner.
run_tool() {
  if have uv && [[ -f pyproject.toml ]]; then
    uv run --quiet "$@"
  else
    "$@"
  fi
}

# A tool that is not installed must not be reported as "the code has violations".
# Silently treating an absent linter as a pass is worse still: the gate would go
# green on a runner with a broken toolchain.
tool_available() {
  have uv && [[ -f pyproject.toml ]] && return 0
  have "$1" && return 0
  fail "toolchain unavailable: $1 is not installed and there is no uv project to run it from"
  return 1
}

printf '\n== quality gate: %s ==\n\n' "$(basename "$PWD")"

# ---------------------------------------------------------------- structure --
if ! skipped structure; then
  if [[ ! -f pyproject.toml ]]; then
    fail "no pyproject.toml — CLAUDE.md requires an installable src/ layout"
  elif [[ ! -d src ]]; then
    fail "no src/ directory — CLAUDE.md requires the src layout"
  else
    pass "project structure (pyproject.toml + src/)"
  fi
fi

# --------------------------------------------------------------------- lint --
if ! skipped lint && tool_available ruff; then
  if run_tool ruff check . ; then pass "ruff check"; else fail "ruff check reported violations"; fi
fi

if ! skipped format && tool_available ruff; then
  if run_tool ruff format --check . ; then pass "ruff format"; else fail "ruff format would reformat files"; fi
fi

# -------------------------------------------------------------------- types --
if ! skipped types && [[ -d src ]] && tool_available mypy; then
  if run_tool mypy --strict src ; then pass "mypy --strict src"; else fail "mypy --strict reported errors"; fi
fi

# -------------------------------------------------------------------- tests --
if ! skipped tests; then
  if [[ ! -d tests ]] || [[ -z "$(find tests -name 'test_*.py' -print -quit 2>/dev/null)" ]]; then
    fail "no tests/ with test_*.py — untested code does not ship"
  elif tool_available pytest; then
    if run_tool pytest -q \
        --cov=src --cov-report=term-missing \
        "--cov-fail-under=${MIN_COVERAGE}" ; then
      pass "pytest, coverage >= ${MIN_COVERAGE}% on src/"
    else
      fail "pytest failed, or coverage on src/ is below ${MIN_COVERAGE}%"
    fi
  fi
fi

# ------------------------------------------------------------------- readme --
if ! skipped readme; then
  if [[ ! -f README.md ]]; then
    fail "no README.md"
  else
    # Headings may or may not be numbered; match on the section name only.
    declare -a SECTIONS=(
      'Problem'
      'TL;?DR'
      'Data'
      'Approach'
      'Results'
      'Error analysis'
      "What did ?n.?t work"
      'Limitations'
      'Reproduce'
    )
    missing=()
    for section in "${SECTIONS[@]}"; do
      if ! grep -qiE "^#{1,4} *([0-9]+\.)? *${section}" README.md; then
        missing+=("$section")
      fi
    done
    if (( ${#missing[@]} )); then
      fail "README.md missing required section(s): ${missing[*]}"
      note "see CLAUDE.md > Docs for the required order"
    else
      pass "README.md has all nine required sections"
    fi

    # "What didn't work" with nothing under it is the most common way this
    # section gets faked, so check it has real content.
    didnt=$(awk '
      tolower($0) ~ /^#{1,4} *([0-9]+\.)? *what did ?n.?.?t work/ { grab=1; next }
      grab && /^#{1,4} /                                          { grab=0 }
      grab                                                        { print }
    ' README.md | grep -cE '\S')
    if (( didnt < 3 )); then
      fail "\"What didn't work\" has ${didnt} non-empty line(s) — CLAUDE.md requires at least two real entries"
    fi
  fi
fi

# ------------------------------------------------------------- data in repo --
if ! skipped data; then
  data_hits=$(git ls-files \
    | grep -iE '\.(csv|tsv|parquet|feather|jsonl|ndjson|xlsx|xls|db|sqlite3?|pkl|pickle|h5|hdf5|npz|npy|zip|tar|tar\.gz|tgz|gz)$' \
    | grep -vE '^(tests/fixtures|tests/data)/' || true)
  if [[ -n "$data_hits" ]]; then
    fail "dataset-shaped files tracked in git (fetch scripts only):"
    printf '%s\n' "$data_hits" | sed 's/^/        /'
  else
    pass "no datasets tracked in git"
  fi

  big=$(git ls-files -z \
    | xargs -0 -I{} sh -c 'test -f "{}" && find "{}" -size +'"${MAX_FILE_KB}"'k -print' 2>/dev/null || true)
  if [[ -n "$big" ]]; then
    fail "tracked file(s) larger than ${MAX_FILE_KB}KB:"
    printf '%s\n' "$big" | sed 's/^/        /'
  fi
fi

# ------------------------------------------------------------------ logging --
if ! skipped logging; then
  prints=$(grep -rnE '^[^#]*\bprint\(' src 2>/dev/null | grep -vE '#\s*noqa: *print' || true)
  if [[ -n "$prints" ]]; then
    fail "print() in src/ — CLAUDE.md requires structured logging:"
    printf '%s\n' "$prints" | head -10 | sed 's/^/        /'
  else
    pass "no print() in src/"
  fi
fi

# ------------------------------------------------ metrics backed by results --
if ! skipped results; then
  # If the README claims numbers, results/ must contain the artifacts that
  # produced them. This is the mechanical half of "you may not write a number
  # you did not compute"; the honest half is on the agent.
  if [[ -f README.md ]] && grep -qE '^\|.*[0-9]+\.[0-9]+.*\|' README.md; then
    if [[ ! -d results ]] || [[ -z "$(ls -A results 2>/dev/null)" ]]; then
      fail "README.md contains a numeric table but results/ is missing or empty"
    else
      pass "numeric claims have artifacts in results/"
    fi
  fi
fi

# ----------------------------------------------------------------- denylist --
if ! skipped denylist; then
  # Employer, PHI, and secret markers. Anything matching stops the commit dead.
  PATTERNS=(
    'northwell'
    '\bPHI\b'
    '\bMRN\b'
    '[0-9]{3}-[0-9]{2}-[0-9]{4}'          # SSN-shaped
    'sk-ant-[A-Za-z0-9_-]{10,}'           # Anthropic key
    'ghp_[A-Za-z0-9]{20,}'                # GitHub PAT
    'github_pat_[A-Za-z0-9_]{20,}'
    'AKIA[0-9A-Z]{16}'                    # AWS key id
    'BEGIN [A-Z ]*PRIVATE KEY'
  )
  if [[ -f "$DENYLIST_FILE" ]]; then
    while IFS= read -r extra; do
      [[ -n "$extra" && "$extra" != \#* ]] && PATTERNS+=("$extra")
    done < "$DENYLIST_FILE"
  fi
  # The patterns use \b, which git grep only honours under PCRE — its default
  # ERE engine matches nothing and reports success, which would make this whole
  # check a no-op. Probe once and refuse to run silently degraded.
  git grep -qIP 'a' -- . >/dev/null 2>&1
  probe=$?           # 0 = matched, 1 = no match, >1 = -P unsupported
  pcre_ok=$(( probe <= 1 ))
  (( pcre_ok )) || fail "git was built without PCRE support; the denylist cannot run reliably"

  deny_found=0
  for pattern in "${PATTERNS[@]}"; do
    (( pcre_ok )) || break
    # Exclude the gate itself and the denylist file, which legitimately contain
    # these strings.
    # Exclude the files that legitimately *name* the forbidden things: the gate,
    # the denylist, the standards doc, and the agent prompts all say "PHI" on
    # purpose. Without this the gate fires on its own rulebook.
    hits=$(git grep -nIP "$pattern" -- . \
             ':(exclude)scripts/quality_gate.sh' \
             ':(exclude)CLAUDE.md' \
             ':(exclude).github/prompts/*' \
             ":(exclude)${DENYLIST_FILE}" 2>/dev/null || true)
    if [[ -n "$hits" ]]; then
      fail "denylisted pattern /${pattern}/ present:"
      printf '%s\n' "$hits" | head -5 | sed 's/^/        /'
      deny_found=1
    fi
  done
  if (( pcre_ok && ! deny_found )); then pass "no employer, PHI, or secret markers"; fi
fi

# ---------------------------------------------------------------- substance --
if ! skipped substance; then
  if git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
    read -r added removed < <(
      git diff --numstat "${BASE_REF}...HEAD" -- . \
        ':(exclude)*.lock' ':(exclude)uv.lock' ':(exclude)poetry.lock' \
        ':(exclude)results/*' \
      | awk '{a+=$1; r+=$2} END {print (a+0), (r+0)}'
    )
    net=$(( added - removed ))
    if (( added == 0 )); then
      fail "zero added lines against ${BASE_REF} — this is a filler commit"
    elif (( net < 30 && removed < 60 )); then
      warn "only ${net} net lines added (${added}/-${removed}); CLAUDE.md sizes a unit at 60-200"
    elif (( net > 400 )); then
      warn "${net} net lines added — larger than one work unit; consider splitting"
    else
      pass "change size: +${added}/-${removed} (net ${net})"
    fi
  else
    note "base ref ${BASE_REF} not found; skipping size check"
  fi
fi

# ------------------------------------------------------------------ verdict --
echo
if (( ${#WARNINGS[@]} )); then
  printf '%s%d warning(s)%s\n' "$YEL" "${#WARNINGS[@]}" "$OFF"
fi
if (( ${#FAILURES[@]} )); then
  printf '%s%d failure(s) — DO NOT COMMIT%s\n' "$RED" "${#FAILURES[@]}" "$OFF"
  for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
printf '%squality gate passed%s\n' "$GRN" "$OFF"
exit 0
