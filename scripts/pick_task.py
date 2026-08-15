#!/usr/bin/env python3
"""Deterministic work-unit selection for the portfolio engine.

Reads ``BACKLOG.md`` and ``STATE.json`` from the repository root and prints the
single work unit the current run should attempt, as JSON on stdout.

The selection is a pure function of (backlog contents, ``cycle``, ``rotation``).
Given the same two files it always returns the same task, which is what makes a
run reproducible and a log entry auditable after the fact.

Usage
-----
    python scripts/pick_task.py
        Print today's task as JSON. Exit 0.

    python scripts/pick_task.py --complete CLE-01 --pr https://... --status shipped
        Mark a task done, bump the cycle and streak, and record the run in
        STATE.json. Called at the end of a successful run.

    python scripts/pick_task.py --record-skip CLE-01 --note "gate failed: mypy"
        Record an attempted-but-not-shipped run. Leaves the task pending, bumps
        the cycle so rotation advances, and resets the streak.

Exit codes
----------
    0   a task was selected (or a state mutation succeeded)
    2   the engine is paused, or the git identity is unconfigured
    3   no eligible task remains — the backlog is exhausted or fully blocked
    4   the backlog or state file could not be parsed
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Any, Final

ROOT: Final[Path] = Path(__file__).resolve().parent.parent
BACKLOG_PATH: Final[Path] = ROOT / "BACKLOG.md"
STATE_PATH: Final[Path] = ROOT / "STATE.json"

PENDING: Final[str] = " "
DONE: Final[str] = "x"
BLOCKED: Final[str] = "-"

TASK_RE: Final[re.Pattern[str]] = re.compile(
    r"^- \[(?P<status>[ x\-])\]\s+"
    r"(?P<id>[A-Z]{3}-\d+)\s*\|\s*"
    r"(?P<tier>[a-z]+)\s*\|\s*"
    r"(?P<repo>[\w.\-]+)\s*\|\s*"
    r"(?P<title>.*?)"
    r"(?:\s*\{(?P<opts>[^}]*)\})?\s*$"
)


class BacklogError(RuntimeError):
    """The backlog or state file is malformed in a way that must not be guessed past."""


@dataclass(frozen=True)
class Task:
    """One work unit as declared in ``BACKLOG.md``."""

    id: str
    tier: str
    repo: str
    title: str
    status: str
    line_no: int
    after: tuple[str, ...] = ()
    model: str | None = None

    @property
    def pending(self) -> bool:
        return self.status == PENDING


@dataclass
class Backlog:
    """Parsed view of ``BACKLOG.md``, retaining the raw lines for in-place edits."""

    lines: list[str]
    tasks: list[Task] = field(default_factory=list)

    def by_id(self, task_id: str) -> Task | None:
        return next((t for t in self.tasks if t.id == task_id), None)


def _parse_options(raw: str | None) -> tuple[tuple[str, ...], str | None]:
    """Parse a trailing ``{after=A;B, model=opus}`` block into (deps, model)."""
    if not raw:
        return (), None
    after: tuple[str, ...] = ()
    model: str | None = None
    for chunk in raw.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        if "=" not in chunk:
            raise BacklogError(f"malformed option {chunk!r} — expected key=value")
        key, _, value = chunk.partition("=")
        key, value = key.strip(), value.strip()
        if key == "after":
            after = tuple(dep.strip() for dep in value.split(";") if dep.strip())
        elif key == "model":
            model = value
        else:
            raise BacklogError(f"unknown option key {key!r}")
    return after, model


def load_backlog(path: Path = BACKLOG_PATH) -> Backlog:
    """Parse every task line in the backlog, rejecting duplicate ids."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise BacklogError(f"cannot read {path}: {exc}") from exc

    backlog = Backlog(lines=lines)
    seen: set[str] = set()
    in_fence = False
    for i, line in enumerate(lines):
        if line.lstrip().startswith("```"):
            # The file documents its own line format inside a code fence; that
            # example must not be mistaken for a real task.
            in_fence = not in_fence
            continue
        if in_fence or not line.startswith("- ["):
            continue
        match = TASK_RE.match(line)
        if match is None:
            # A checklist line that is not a task line is almost always a typo in a
            # task line, and silently ignoring it would silently drop work.
            raise BacklogError(f"{path.name}:{i + 1}: checklist line does not parse:\n  {line}")
        gd = match.groupdict()
        if gd["id"] in seen:
            raise BacklogError(f"{path.name}:{i + 1}: duplicate task id {gd['id']}")
        seen.add(gd["id"])
        after, model = _parse_options(gd["opts"])
        backlog.tasks.append(
            Task(
                id=gd["id"],
                tier=gd["tier"],
                repo=gd["repo"],
                title=gd["title"].strip(),
                status=gd["status"],
                line_no=i,
                after=after,
                model=model,
            )
        )

    unknown = {dep for t in backlog.tasks for dep in t.after} - seen
    if unknown:
        raise BacklogError(f"tasks depend on unknown ids: {sorted(unknown)}")
    return backlog


def load_state(path: Path = STATE_PATH) -> dict[str, Any]:
    try:
        state: dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BacklogError(f"cannot read {path}: {exc}") from exc
    return state


def save_state(state: dict[str, Any], path: Path = STATE_PATH) -> None:
    path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")


def is_eligible(task: Task, done_ids: frozenset[str]) -> bool:
    """A task is eligible when it is pending and every declared dependency is done."""
    return task.pending and all(dep in done_ids for dep in task.after)


def select(backlog: Backlog, state: dict[str, Any]) -> Task | None:
    """Pick the highest-priority eligible task for this cycle's tier.

    The rotation names a preferred tier per cycle. If that tier has nothing
    eligible — normally because its next items are blocked on dependencies — fall
    through to the remaining tiers in rotation order, then to any tier at all,
    rather than skipping the day. Within a tier, backlog order is priority order.
    """
    done_ids = frozenset(t.id for t in backlog.tasks if t.status == DONE)
    eligible = [t for t in backlog.tasks if is_eligible(t, done_ids)]
    if not eligible:
        return None

    rotation: list[str] = list(state.get("rotation") or ["flagship"])
    cycle = int(state.get("cycle", 0))
    preferred = rotation[cycle % len(rotation)]

    # Preferred tier first, then the rest of the rotation in order, then anything.
    tier_order = [preferred, *[t for t in rotation if t != preferred]]
    for tier in tier_order:
        for task in eligible:
            if task.tier == tier:
                return task
    return eligible[0]


def resolve_model(task: Task, state: dict[str, Any]) -> str:
    """Per-task override wins; otherwise the tier default; otherwise opus."""
    if task.model:
        return task.model
    by_tier: dict[str, str] = state.get("model_by_tier") or {}
    return by_tier.get(task.tier, "opus")


def _set_status(backlog: Backlog, task: Task, status: str) -> None:
    line = backlog.lines[task.line_no]
    backlog.lines[task.line_no] = line.replace(f"- [{task.status}]", f"- [{status}]", 1)


def cmd_select(args: argparse.Namespace) -> int:
    state = load_state()
    if state.get("paused"):
        print("engine is paused (STATE.json.paused = true)", file=sys.stderr)
        return 2

    identity = state.get("git_identity") or {}
    if "REPLACE_ME" in str(identity.get("email", "")):
        print(
            "git_identity.email in STATE.json is still the placeholder.\n"
            "Set it to <numeric-id>+vitejbari@users.noreply.github.com before any run, or\n"
            "commits will not be attributed and the run is wasted.",
            file=sys.stderr,
        )
        return 2

    backlog = load_backlog()
    task = select(backlog, state)
    if task is None:
        print(
            "no eligible task: the backlog is exhausted or every pending item is "
            "blocked on an unfinished dependency",
            file=sys.stderr,
        )
        return 3

    remaining = sum(1 for t in backlog.tasks if t.pending)
    payload = {
        "id": task.id,
        "tier": task.tier,
        "repo": task.repo,
        "repo_full": (state.get("repos") or {}).get(task.repo, task.repo),
        "title": task.title,
        "model": resolve_model(task, state),
        "cycle": int(state.get("cycle", 0)),
        "date": date.today().isoformat(),
        "pending_after_this": remaining - 1,
        # Drop the $-prefixed annotation keys; the agent consumes this as config.
        "git_identity": {k: v for k, v in identity.items() if not k.startswith("$")},
    }
    print(json.dumps(payload, indent=2))
    print(
        f"\n-> {task.id} [{task.tier}/{payload['model']}] {task.repo}: {task.title}"
        f"\n   {remaining} pending task(s) in backlog",
        file=sys.stderr,
    )
    return 0


def cmd_complete(args: argparse.Namespace) -> int:
    backlog = load_backlog()
    state = load_state()
    task = backlog.by_id(args.complete)
    if task is None:
        print(f"unknown task id {args.complete}", file=sys.stderr)
        return 4
    if not task.pending:
        print(f"{task.id} is already '{task.status}' — refusing to rewrite", file=sys.stderr)
        return 4

    _set_status(backlog, task, DONE)
    BACKLOG_PATH.write_text("\n".join(backlog.lines) + "\n", encoding="utf-8")

    state["cycle"] = int(state.get("cycle", 0)) + 1
    state["streak"] = int(state.get("streak", 0)) + 1
    state["last_run"] = {
        "date": date.today().isoformat(),
        "task_id": task.id,
        "status": args.status,
        "pr_url": args.pr,
        "note": args.note or "",
    }
    save_state(state)
    print(f"{task.id} marked done; cycle={state['cycle']} streak={state['streak']}")
    return 0


def cmd_record_skip(args: argparse.Namespace) -> int:
    """Record a run that attempted work but shipped nothing. The task stays pending."""
    state = load_state()
    backlog = load_backlog()
    if backlog.by_id(args.record_skip) is None:
        print(f"unknown task id {args.record_skip}", file=sys.stderr)
        return 4

    state["cycle"] = int(state.get("cycle", 0)) + 1
    state["streak"] = 0
    state["last_run"] = {
        "date": date.today().isoformat(),
        "task_id": args.record_skip,
        "status": "skipped",
        "pr_url": None,
        "note": args.note or "no reason recorded",
    }
    save_state(state)
    print(f"skip recorded for {args.record_skip}; cycle={state['cycle']} streak reset")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--complete", metavar="ID", help="mark ID done and advance the cycle")
    group.add_argument("--record-skip", metavar="ID", help="record an attempt that shipped nothing")
    parser.add_argument("--pr", help="PR url to record in STATE.json")
    parser.add_argument("--status", default="shipped", help="status string for STATE.json.last_run")
    parser.add_argument("--note", help="free-text note for STATE.json.last_run")
    args = parser.parse_args(argv)

    try:
        if args.complete:
            return cmd_complete(args)
        if args.record_skip:
            return cmd_record_skip(args)
        return cmd_select(args)
    except BacklogError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 4


if __name__ == "__main__":
    raise SystemExit(main())
