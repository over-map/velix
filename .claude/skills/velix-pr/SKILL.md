---
name: velix-pr
description: The Velix branch → commit → PR → CI → merge protocol, including what a PR description contains and when merging is allowed. Use whenever you commit, push, open a PR, are asked to "check CI and merge #N", start a new milestone part, or write a DECISIONS row.
---

# Velix PRs and merging

## The protocol (Filippo's rules, never bend them)
1. **Each milestone starts in plan mode.** Show the plan and wait for approval. A milestone ships as **one PR per part** (for example M10 PR 1 accessibility, PR 2 performance, PR 4 demo).
2. Branch from an up-to-date `main` with a short kebab name (`m10-performance`).
3. Small commits with clear messages. Every commit message ends with the attribution trailer your harness gives. In the original sessions that was `Co-Authored-By: Claude <model> <noreply@anthropic.com>`.
4. Push with `git push -u origin <branch>`. The remote is `git@github.com-personal:over-map/velix.git`, an SSH host alias for Filippo's personal GitHub account. `gh` has two accounts logged in, and **`over-map` must be the active one** (`gh auth status`). Never use the TomTom account for this repo.
5. `gh pr create`. The PR body ends with the line your harness gives (originally `🤖 Generated with [Claude Code](https://claude.com/claude-code)`).
6. **Merge only when Filippo says "check CI and merge #N" (or "go ahead" right after a PR), and only when CI is green.**
   - `gh pr checks N`: if anything is pending, say so and stop. Don't wait, poll or schedule checks; Filippo asks again.
   - When green: `gh pr merge N --merge --delete-branch`. It's a merge commit, never squash. Then `git checkout main && git pull --ff-only` and delete the local branch.
   - Auto-merge is blocked by the permission classifier. Don't try it.
   - A CI failure from GitHub infrastructure (504, "could not connect" while downloading packages) gets a rerun: `gh run rerun <id> --failed`. Ask Filippo first if he hasn't already said "rerun".
7. CI (`.github/workflows/ci.yml`, `macos-26`, about 14–16 min) runs:
   - the design-system guards: TokenGen, icons and styles up to date, no `systemName:` (SF Symbols), no colour literals outside `Generated/`;
   - the ride-report unit tests;
   - the build, unit tests and snapshots, and golden tests with the latest Lombardy pack.

## PR description
Write it in plain, short sentences. Include:
- what BUILD_PLAN asks;
- what was measured or seen, with numbers;
- what changed, grouped;
- what was dropped and why;
- the tests;
- anything pending.

If the PR promises something "before merge", either deliver it or edit the body (`gh pr edit N --body-file …`) before merging. Visual changes get phone screenshots or simulator side-by-sides with the design.

## DECISIONS.md
`docs/DECISIONS.md` is a table `| Date | Decision | Reason | Who |`, **newest first**. Add new rows directly under the header separator. Put the decision in bold, then the detail. Who is `Filippo` when he chose it and `Claude` when it was a technical call you made. Log every product or technical decision and every deviation from the design.
If a merge from main conflicts in DECISIONS, keep both sets of rows, newest first.

## Approval needed before
- any map-style or visual change (show it on the phone or as screenshots first);
- new copy not in the design files;
- anything that grows a region pack past the 320 MB budget;
- new dependencies (they need an OSI licence and a THIRD_PARTY.md entry).
