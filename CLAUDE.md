# Standards

These standards govern every repo this orchestrator writes to: `clinical-llm-eval`,
`ml-lab`, `vitejbari` (profile README), and `portfolio-engine` itself.

## Audience

Every file is read by a hiring manager evaluating me for a Senior Data Scientist role.
Optimise for: "this person has shipped real systems and thinks clearly about tradeoffs."
Anti-optimise for: tutorial energy, toy datasets, unexplained notebooks, dead code.

## Code

- Python 3.12. `src/` layout, installable via `pyproject.toml` (uv).
- Type hints on every public function. `ruff check` and `ruff format` clean. `mypy --strict` on `src/`.
- `pytest` with real assertions on behaviour, not smoke tests. Coverage on core logic >= 80%.
- Every stochastic process takes an explicit seed. Every experiment writes a config to `results/`.
- Notebooks are outputs, not sources. If a notebook exists, the logic lives in `src/` and the
  notebook only calls it.
- Structured logging, not print. Config via pydantic-settings, not hardcoded constants.

## Experiments

- Baseline first, always. A model without a baseline it beats is not a result.
- Report a confidence interval or a variance across seeds. A single number is not a result.
- Correct validation for the data type: grouped/patient-level splits for clinical data,
  walk-forward with purging and embargo for time series. Leakage is the failure mode that
  disqualifies a candidate — check for it explicitly and write down how you checked.
- Calibration, not just discrimination. Report both.
- Slice metrics by subgroup where data permits, and say what you found.

## Docs — every project README must have, in this order

1. **Problem** — one paragraph, what real decision this would inform.
2. **TL;DR results** — a table. Metric, baseline, model, delta, CI.
3. **Data** — source, licence, size, how to fetch, known limitations.
4. **Approach** — the modelling and engineering decisions, with links to ADRs.
5. **Results** — figures from `results/`, read honestly.
6. **Error analysis** — where it fails, on what kind of input, and your hypothesis why.
7. **What didn't work** — at least two things. This section is the credibility test.
8. **Limitations & what I'd do with more time/data.**
9. **Reproduce** — three commands, max. They must actually work from a clean clone.

`scripts/quality_gate.sh` enforces the presence of these headings verbatim. Keep the
wording stable so the gate keeps working.

## Prohibited

- Employer data, PHI, or any reconstruction of internal work.
- Metrics not produced by committed, executed code.
- Filler commits: whitespace, version bumps, "update README" with no substance.
- Datasets committed to git. Fetch scripts only.

## Attribution

Commits must be authored as Vitej, not as a bot. Every run sets:

```
git config user.name  "Vitej Bari"
git config user.email "<numeric-id>+vitejbari@users.noreply.github.com"
```

The numeric id comes from `https://api.github.com/users/vitejbari` (the `id` field) and is
stored in `STATE.json` under `git_identity`. If it is still the placeholder, stop and open an
issue rather than committing with a wrong identity — GitHub will not count contributions
against an email it does not recognise, and the run is wasted.

## Work-unit sizing

A work unit is **60–200 lines of net new substance**. Tests count. Generated files,
lockfiles, and vendored data do not. If the backlog item is larger, split it: do the first
slice, push the remainder back onto `BACKLOG.md` as a new item with a `(split from <ID>)`
note, and record the split in the run log.

Under-shipping is fine. A day that produces one well-tested module and an honest ADR beats a
day that produces four half-finished ones.

## The negative-result rule

If an experiment disappoints, publish it as a negative result with the analysis. Do not
retune until the number looks good and then report only the last run. If you tuned, report
the search and the variance across it.
