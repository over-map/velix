# Prompt for a fresh Claude Code session

Open a terminal, `cd /Users/imbe/Developer/personal/velix`, run `claude` (or open that folder in the Claude desktop app's Code tab), and paste the prompt below. Keep it updated alongside `docs/HANDOVER.md`.

```text
You're taking over Velix, my personal open-source iPhone bike-navigation app (SwiftUI, MapLibre, on-device Valhalla). A previous Claude Code session built M0–M10 PR 2 with me. You have no memory of it, so the repo is your memory.

1. Read, in this order: CLAUDE.md, CLAUDE.local.md, docs/HANDOVER.md (the state of the project and what's next), docs/BUILD_PLAN.md, the top 30 rows of docs/DECISIONS.md, and every .claude/skills/*/SKILL.md. Skim design/README.md and design/HANDOFF.md.
2. Check the handover still matches reality, without changing anything:
   - git status and git log -5 on main (expected head: 759b4a9 or a later merge of the handover PR);
   - gh auth status (the active account must be over-map);
   - gh pr list;
   - xcrun devicectl list devices (my iPhone 11 "iFil");
   - the signing profile expiry, read with the command in the velix-phone skill.
3. Reply in at most 15 lines:
   - what Velix is;
   - where it stands;
   - the next 3 steps;
   - anything in the handover that doesn't match what you found;
   - anything you need from me, especially the signing renewal before 13 Nov, which needs my Apple ID in Xcode.
4. Then start M10 PR 3 (the severe-weather notice, MeteoAlarm) in plan mode, following docs/HANDOVER.md §2.2. Show me the plan and wait for my approval before changing any file.

Rules that matter most:
- plan mode first;
- one PR per part;
- merge only when I say "check CI and merge #N" and CI is green;
- never poll CI yourself;
- log decisions in docs/DECISIONS.md, newest first;
- ask before visual or map-style changes;
- no SF Symbols, no API keys, no paid services;
- personal accounts only, no company plugins.
```
