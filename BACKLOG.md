# Backlog

Ordered queue of work units. `scripts/pick_task.py` parses this file, so the line format is
load-bearing:

```
- [ ] ID | tier | repo | title                        {key=value, ...}
```

- **status** — `[ ]` pending · `[x]` done · `[-]` blocked or abandoned (give a reason in the
  indented note beneath it)
- **ID** — stable, never reused. `CLE-*` flagship, `LAB-*` satellite, `ENG-*` orchestrator,
  `PRO-*` profile.
- **tier** — `flagship` | `satellite` | `meta`. Drives rotation and model selection.
- **repo** — the target repository, bare name.
- **options** — optional trailing `{...}`. Supported keys: `model=opus|sonnet`,
  `after=ID1;ID2` (dependency — task is not eligible until those are `[x]`).

Order within a tier is priority order. The picker takes the first eligible task in the tier
the rotation calls for, so to reprioritise, move the line.

---

## Flagship — `clinical-llm-eval`

An open evaluation harness for LLM-based structured extraction from clinical text. Synthetic
corpora only (Synthea). Nothing here derives from employer systems or data.

- [ ] CLE-01 | flagship | clinical-llm-eval | Repo scaffold: pyproject/uv, src layout, ruff+mypy+pytest CI, ADR-001 on scope and non-goals
- [ ] CLE-02 | flagship | clinical-llm-eval | Synthea synthetic note corpus fetch script + extraction-target schema {after=CLE-01}
- [ ] CLE-03 | flagship | clinical-llm-eval | Pydantic output schemas + structured-output validation layer with retry/repair {after=CLE-02}
- [ ] CLE-04 | flagship | clinical-llm-eval | Baseline extractor: regex + rules. The floor everything is measured against {after=CLE-03}
- [ ] CLE-05 | flagship | clinical-llm-eval | LLM extractor behind a provider-agnostic interface {after=CLE-03}
- [ ] CLE-06 | flagship | clinical-llm-eval | Metric suite: exact/fuzzy field match, span-level F1, schema-validity rate {after=CLE-04}
- [ ] CLE-07 | flagship | clinical-llm-eval | Hallucination detection: attributable-to-source checking with span grounding {after=CLE-06}
- [ ] CLE-08 | flagship | clinical-llm-eval | Calibration study: does stated confidence mean anything? Reliability diagrams {after=CLE-06}
- [ ] CLE-09 | flagship | clinical-llm-eval | Cost/latency/quality Pareto frontier across model tiers {after=CLE-06}
- [ ] CLE-10 | flagship | clinical-llm-eval | Prompt-sensitivity study: variance across paraphrases, seeds, field orderings {after=CLE-06}
- [ ] CLE-11 | flagship | clinical-llm-eval | Failure taxonomy from manual review of 100 errors, with worked examples {after=CLE-07}
- [ ] CLE-12 | flagship | clinical-llm-eval | Serving: FastAPI + batch mode, containerised, load-tested {after=CLE-05}
- [ ] CLE-13 | flagship | clinical-llm-eval | Drift monitoring on input distribution and output schema-validity over time {after=CLE-12}
- [ ] CLE-14 | flagship | clinical-llm-eval | Model card, dataset card, and written retrospective {after=CLE-11}

## Satellites — `ml-lab`

One directory per mini-project, 3–6 work units each. Rotate domains deliberately; do not
finish all of one domain before starting the next.

- [ ] LAB-01 | satellite | ml-lab | `vol-forecast-backtest`: purged walk-forward CV, embargo, realistic cost model (finance)
- [ ] LAB-02 | satellite | ml-lab | `conformal-risk`: conformal prediction wrapper for tabular risk scores (healthcare/ML)
- [ ] LAB-03 | satellite | ml-lab | `uplift-cate`: CATE estimation with EconML on a public trial dataset (causal)
- [ ] LAB-04 | satellite | ml-lab | `drift-service`: feature + label drift detection service (MLOps)
- [ ] LAB-05 | satellite | ml-lab | `duckdb-dbt-layer`: dbt + DuckDB analytics layer, tested models, lineage (data eng)
- [ ] LAB-06 | satellite | ml-lab | `retrieval-eval`: chunking/embedding ablation, recall@k vs cost (LLM systems)
- [ ] LAB-07 | satellite | ml-lab | `competing-risks`: survival analysis on public registry data (healthcare stats)
- [ ] LAB-08 | satellite | ml-lab | `fairness-audit`: subgroup metrics + threshold policy tradeoffs (ethics/ML)
- [ ] LAB-09 | satellite | ml-lab | `tc-portfolio-opt`: transaction-cost-aware portfolio optimisation (finance)
- [ ] LAB-10 | satellite | ml-lab | `repro-harness`: experiment tracking + reproducibility harness (MLOps, meta)

## Meta — `portfolio-engine` and profile

- [ ] ENG-01 | meta | portfolio-engine | Self-test suite for `pick_task.py` and `quality_gate.sh` against fixture repos {model=sonnet}
- [ ] PRO-01 | meta | vitejbari | Profile README: curated index, one measured result line per project {after=CLE-06}

---

## Deferred / rejected

Nothing yet. When a task is dropped, move it here with the date and the reason. A backlog
that only ever grows is a backlog nobody is reading.
