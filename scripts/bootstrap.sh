#!/usr/bin/env bash
# One-time setup for the portfolio engine.
#
# This script is deliberately NOT idempotent-and-silent: it creates public
# repositories and stores secrets. Read it before running it. It prompts before
# every irreversible or outward-facing step.
#
#   bash scripts/bootstrap.sh --check    verify prerequisites only, change nothing
#   bash scripts/bootstrap.sh            run the guided setup

set -euo pipefail

GH_USER="vitejbari"
REPOS=(portfolio-engine clinical-llm-eval ml-lab "$GH_USER")
CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

say()  { printf '\n\033[1m== %s\033[0m\n' "$1"; }
ask()  { read -r -p "$1 [y/N] " reply; [[ "$reply" == [yY] ]]; }
die()  { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

say "Prerequisites"
command -v gh   >/dev/null || die "gh not installed — 'brew install gh', then 'gh auth login'"
command -v git  >/dev/null || die "git not installed"
command -v uv   >/dev/null || echo "  uv not installed (needed locally, not for CI) — https://docs.astral.sh/uv/"
gh auth status  >/dev/null 2>&1 || die "gh is not authenticated — run 'gh auth login'"
echo "  gh, git, and authentication OK"

say "Your GitHub numeric id"
NUMERIC_ID=$(gh api "users/${GH_USER}" --jq .id)
echo "  ${NUMERIC_ID}+${GH_USER}@users.noreply.github.com"
echo "  Put this in STATE.json > git_identity.email before the first run."

if (( CHECK_ONLY )); then
  say "Repo status"
  for repo in "${REPOS[@]}"; do
    if gh repo view "${GH_USER}/${repo}" >/dev/null 2>&1; then
      echo "  exists:  ${GH_USER}/${repo}"
    else
      echo "  missing: ${GH_USER}/${repo}"
    fi
  done
  say "Secrets on portfolio-engine"
  gh secret list --repo "${GH_USER}/portfolio-engine" 2>/dev/null || echo "  (repo not created yet)"
  echo
  echo "Check complete. Nothing was changed."
  exit 0
fi

# ---------------------------------------------------------------------------
say "Before anything else"
cat <<'EOF'
  Read your employment agreement's IP assignment and outside-work clauses.
  Health-system contracts frequently claim work in the employer's field, and
  this portfolio is squarely in that field. Personal hardware, personal GitHub,
  personal accounts, no employer data — and if the policy is ambiguous, get
  written clarification from HR first.

  This is the only step here that can actually hurt you.
EOF
ask "  Confirmed you have done this?" || die "stopping — do that first"

# ---------------------------------------------------------------------------
say "1. Create the four public repositories"
for repo in "${REPOS[@]}"; do
  if gh repo view "${GH_USER}/${repo}" >/dev/null 2>&1; then
    echo "  already exists: ${GH_USER}/${repo}"
    continue
  fi
  if ask "  Create PUBLIC repo ${GH_USER}/${repo}?"; then
    gh repo create "${GH_USER}/${repo}" --public
  fi
done

# ---------------------------------------------------------------------------
say "2. Claude Code GitHub App"
cat <<'EOF'
  Run this yourself from inside the portfolio-engine checkout:

      claude
      /install-github-app

  It installs the app and can set CLAUDE_CODE_OAUTH_TOKEN for you.
EOF

say "3. Subscription billing token (optional, skip if using an API key)"
cat <<'EOF'
      claude setup-token
      gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo vitejbari/portfolio-engine

  Check Anthropic's current terms on using a subscription token for unattended
  CI runs before relying on it for a daily cron.
EOF

say "4. Fine-grained PAT"
cat <<EOF
  Create at: https://github.com/settings/personal-access-tokens/new

    Resource owner : ${GH_USER}
    Repositories   : the four above, and nothing else
    Permissions    : Contents RW · Pull requests RW · Issues RW
    Expiry         : 90 days. Put the renewal in your calendar now — an expired
                     PAT fails the cron silently every morning until you notice.

  Then:
      gh secret set GH_PORTFOLIO_TOKEN --repo ${GH_USER}/portfolio-engine
EOF

# ---------------------------------------------------------------------------
say "5. Push this orchestrator to main"
cat <<EOF
  Scheduled workflows only fire from the default branch, so the cron does
  nothing until these files are on main.

      git init && git branch -M main
      git add . && git commit -m "feat: portfolio engine scaffold"
      git remote add origin https://github.com/${GH_USER}/portfolio-engine.git
      git push -u origin main
EOF

say "6. Dry run before letting the cron fire"
cat <<EOF
      gh workflow run daily-build.yml --repo ${GH_USER}/portfolio-engine -f dry_run=true
      gh run watch --repo ${GH_USER}/portfolio-engine

  dry_run selects the task and stops. When that looks right, run it again
  without the flag and read the resulting PR line by line. Only after a clean
  manual run should you leave the schedule enabled.
EOF

echo
echo "Guided setup finished. Steps 2-6 are yours to run."
