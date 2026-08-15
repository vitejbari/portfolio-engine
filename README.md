# portfolio-engine

An agentic pipeline that maintains my public research repos on a schedule. It selects a work
unit from an ordered backlog, builds it in the target repository, refuses to commit if the
work fails a quality gate, opens a reviewable PR, and writes an honest log of what happened —
including the days it decides to ship nothing.

It is also, deliberately, the first thing worth reading here. The interesting artifact is not
the commit count it produces; it is the set of constraints that make an unattended agent's
output defensible.

## How it works

```
schedule ──> pick_task.py ──> agent builds in target repo ──> quality_gate.sh
                 │                                                  │
                 │                                          pass ───┴─── fail
                 │                                            │           │
                 │                                            v           v
                 │                                     PR + auto-merge   issue,
                 │                                            │        no commit
                 └────────────── STATE.json, logs/ <──────────┴───────────┘
```

| Piece | What it is |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | The standards the agent must obey. Code, experiments, docs, prohibitions. |
| [`BACKLOG.md`](BACKLOG.md) | Ordered, machine-parseable queue. Tiers, dependencies, per-task model. |
| [`STATE.json`](STATE.json) | Cycle counter, streak, rotation, git identity, pause switch. |
| [`scripts/pick_task.py`](scripts/pick_task.py) | Deterministic selection. Same inputs, same task, every time. |
| [`scripts/quality_gate.sh`](scripts/quality_gate.sh) | Eleven mechanical checks. Exit 1 means the commit does not happen. |
| [`.quality-gate.env`](.quality-gate.env) | Per-repo opt-outs. Targets ship without one, so they get every check. |
| [`.github/prompts/`](.github/prompts) | The daily-build and weekly-audit prompts. |
| [`logs/`](logs) | One dated entry per run. `logs/audits/` holds the Sunday self-review. |

## The constraints that matter

**You may not write a number you did not compute.** Any figure in a README must come from a
script in the repo, executed in that run, with its output committed under `results/`. The gate
enforces the mechanical half: a numeric table in the README with an empty `results/` fails.

**A skipped day is an acceptable outcome.** If the gate fails and the agent cannot fix it
within its turn budget, it opens an issue and stops. Nothing lands. The streak resets. This is
the feature, not the failure mode.

**The audit job proposes; it does not act.** The Sunday review runs with a read-only toolset
and no PAT. It can name problems and open issues. It cannot fix them — remediation goes
through the daily build with its own gate.

**Negative results get published.** A disappointing number with the analysis attached is worth
more in an interview than a clean one nobody can reproduce.

## Targets

| Repo | Role |
|---|---|
| `clinical-llm-eval` | Flagship. Evaluation harness for LLM structured extraction from clinical text. Synthetic corpora only. |
| `ml-lab` | Satellites. One directory per mini-project, rotating across finance, causal, MLOps, and stats. |
| `vitejbari` | Profile README — a curated index with one measured result per project. |

## Operating it

```bash
bash scripts/bootstrap.sh --check          # verify prerequisites, change nothing
python scripts/pick_task.py                # what would run right now
QG_BASE_REF=HEAD~1 bash scripts/quality_gate.sh   # run the gate locally in a target repo
```

Force a specific task, or select without building:

```bash
gh workflow run daily-build.yml -f task_id=CLE-03
gh workflow run daily-build.yml -f dry_run=true
```

**Kill switch.** Set `"paused": true` in `STATE.json` and push. The next run exits cleanly at
the selection step. Cheaper and more reversible than disabling the workflow, and it leaves a
record in git of when and why.

## Known limits

- Cron fires at 11:00 UTC, which is 07:00 ET only during EDT. GitHub cron has no timezone.
- The gate cannot tell a real test from a well-typed tautology. That is what the weekly audit
  is for, and the weekly audit is an LLM too. The last line of defence is that I read the
  merged PRs.
- Coverage thresholds measure lines, not thought.

## Credential renewal

`GH_PORTFOLIO_TOKEN` is a fine-grained PAT **expiring 2027-01-31** (read from
GitHub's own response header, not from when it was minted). The daily build
validates it live on every run and starts warning 21 days out — from
2027-01-10 — in both the job annotations and the run summary. The warning is
driven by the header, so it stays correct even if this paragraph drifts. To
renew: mint a replacement at
<https://github.com/settings/personal-access-tokens/new> — four repos,
Contents/Pull requests/Issues read-write — then

```bash
gh secret set GH_PORTFOLIO_TOKEN --repo vitejbari/portfolio-engine
```

Overwriting the existing secret is fine; there is no need to delete it first.
