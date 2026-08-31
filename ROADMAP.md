# QuestGlass roadmap

Full product spec lives in [project_description.md](project_description.md).

## ✅ P1 — Search MVP (done, needs in-game testing)

- Async index build at login (chunked coroutine, criteria text cached in
  SavedVariables per client build)
- Fuzzy search over achievement names + criteria names
- Detail view: icon, description, progress bar, live criteria (incomplete first)
- Debounced `CRITERIA_UPDATE` refresh, ESC close, saved window position
- Slash commands: `/qg`, `/qg <query>`, `/qg rebuild`

**Verify in-game (gotchas from spec §6):**
- [ ] Index build doesn't hitch on first login (~4k achievements)
- [ ] `CRITERIA_UPDATE` debounce holds up in combat/questing
- [ ] Interface number still current (`/run print((select(4, GetBuildInfo())))`)

## ⬜ P2 — Chains (NEXT UP)

- `Chains.lua`: `ChainState` (done/active/upcoming per quest line)
- Auto-mapping: criteria `assetID` → `C_QuestLine.GetQuestLineInfo` →
  `questLineID`, cached via `/qg automap <achID>`; `Overrides.lua` escape hatch
- Detail view chain rendering: "quest 3/11", active objectives, upcoming names
- Click → **TomTom** waypoint (user has TomTom installed): giver if chain not
  started, objective via `GetNextWaypointForMap` if quest in log
- Auto-advance arrow on `QUEST_TURNED_IN` / `QUEST_WATCH_UPDATE`
- Warm quest names via `RequestLoadQuestByID` → re-render on
  `QUEST_DATA_LOAD_RESULT`
- Faction-variant chains: either variant completed counts

## ⬜ P3 — Tracker strip + polish

- Compact pinned panel (1–3 achievements): name, bar, active chain line
- `/qg pin <achID>`, `/qg way`
- Once pinning exists, restore easy-close on the main window (ESC /
  UISpecialFrames): the pinned strip carries the tracking, so the big
  window no longer needs to stay open. (James, 2026-08-30 — current
  sticky-window behavior is a stopgap because the main window is the
  only tracker.)
- Saved scale, name-cache warming, general polish (scrollbar for the list)

## ⬜ P4 — More data

- Automap remaining Sojourner achievements
- Consider non-storyline mappings (rares, treasures) with static coords
