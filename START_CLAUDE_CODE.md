# Start building Velix with Claude Code

## 1. One-time setup on your Mac
- **Xcode 16+** from the App Store; open it once and install the iOS 17+ simulator.
- **Homebrew**, then `brew install xcodegen git gh` (and Docker Desktop for the region pack).
- **Claude Code**: install it and sign in (preferably your personal Claude account; see the note at the end).
- **GitHub**: `gh auth login` with your personal account.
- **iPhone**: Settings → Privacy & Security → Developer Mode on. In Xcode → Settings → Accounts, add your Apple ID (free Personal Team).

## 2. Open the project
Move or copy this `velix/` folder wherever you keep code (e.g. `~/Developer/velix`). Then:
```
cd ~/Developer/velix
claude
```
Claude Code reads `CLAUDE.md` automatically, and the skills in `.claude/skills/` are available in this project.

## 3. First prompt (paste it)
```
Read CLAUDE.md, docs/BRIEF.md, docs/BUILD_PLAN.md and design/README.md. Summarise in 10 lines what you will build and in which order, and list any conflicts or open questions. Then start M0 in plan mode: show me the plan before changing anything.
```
After M0 is merged:
```
Start M1 (tech spike) in plan mode. It's a go/no-go gate: report the measurements and your recommendation before we move on.
```
Then one milestone at a time: "Start M2 in plan mode", and so on.

## 4. Your role at each milestone
1. Read the plan, ask questions, approve.
2. Review the PR: screenshots next to the design, test results, tap count.
3. For device steps (signing, real rides) you do the physical part; Claude Code tells you exactly what to check.
4. Merge, then start the next milestone.

## 5. Updating the design later
Iterate in Claude Design, export a new handoff, replace `design/` (keep the folder name), and tell Claude Code: "The design handoff changed. Diff it against the code and propose the updates."

## Notes
- The `design/` folder is a read-only reference. Never ship the HTML.
- Keep company plugins (e.g. TomTom SDLC tooling) off for this repo. Velix is a personal project.
- Personal vs company account: building a personal open-source app with company tools and accounts may be covered by your employment terms. Using your personal Claude and GitHub accounts keeps it clean.
