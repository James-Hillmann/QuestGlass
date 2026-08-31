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

## 🔶 P2 — Chains (built 2026-08-30, needs in-game testing)

- ✅ `Chains.lua`: chain state (done/active/upcoming per quest line)
- ✅ Auto-mapping on detail open: criteria `assetID` →
  `C_QuestLine.GetQuestLineInfo` → `questLineID`, cached in SavedVariables per
  build; `/qg automap <achID>` debug output; `Overrides.lua` escape hatch
- ✅ Detail view: ▶ marker on mapped criteria, "quest 3/11" column, storyline
  panel (progress, active objective, next quests) on click
- ✅ Click → TomTom waypoint (Blizzard map-pin fallback): giver if not
  started, `GetNextWaypoint` objective if in log; `/qg way` re-points
- ✅ Auto-advance on `QUEST_TURNED_IN` / `QUEST_WATCH_UPDATE`
- ✅ Name warming via `RequestLoadQuestByID` → re-render on
  `QUEST_DATA_LOAD_RESULT`

**P2 leftovers:**
- [x] Tested in-game 2026-08-30: automap resolves Harandar storylines,
  TomTom arrow works for the active quest
- [ ] Verify: auto-advance after a quest turn-in, and the unstarted-chain
  giver arrow (Bloomtown path)
- [ ] Faction-variant chains (e.g. 90546/90547): treat either variant
  completed as done
- [ ] Populate `Overrides.lua` for whatever automap misses

## 🔶 P3 — Tracker strip (built 2026-08-30, needs in-game testing)

- ✅ Compact pinned strip (1–3 achievements): name, bar, live chain line;
  left-click opens detail, right-click re-points arrow, drag to move,
  per-row unpin, auto-unpin (with grats) on earn, pins persist
- ✅ Pin button in the detail view + `/qg pin <achID>`
- ✅ Easy-close restored on the main window (ESC / UISpecialFrames) now
  that the strip carries the tracking (James's 2026-08-30 request)

- ✅ Tracked-storyline expansion: gold accent, per-quest bar, remaining
  quest list — tested in-game 2026-08-30 along with the strip

**P3 leftovers:**
- [ ] Saved scale option if wanted (`/qg scale`)
- [ ] Real scrollbar on lists (nice-to-have)
- Saved scale, name-cache warming, general polish (scrollbar for the list)

## ⬜ P4 — More data

- Automap remaining Sojourner achievements
- Consider non-storyline mappings (rares, treasures) with static coords
