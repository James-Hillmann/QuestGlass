# QuestGlass — in-game achievement browser & chain tracker (addon)

A better front end for achievements than the default UI or ATT: fast fuzzy search, clean progress view with live criteria, and — for mapped achievements — storyline awareness ("chain 3/11, here's what's next") with one-click TomTom arrows.

Pure in-game Lua. No external app, no scraping at runtime.

---

## 1. Product shape

Three views in one movable/resizable frame:

**A. Search (default view)**
- One text box, focused on open (`/qg` or keybind).
- Fuzzy match over achievement names AND criteria names ("paladin rescue" → Sojourner of Eversong Woods).
- Results ranked: incomplete before complete, then match quality. Row shows name, points, progress %.
- Index built once at `PLAYER_LOGIN` (async over a few frames to avoid a hitch), cached in SavedVariables with a build-version stamp.

**B. Achievement detail**
- Header: icon, name, description, big progress bar (done criteria / total).
- Criteria list, incomplete first, each with live counts ("Fallen Blades 2/6") via `GetAchievementCriteriaInfo`.
- Mapped criteria (auto-mapped, see §3) get: ▶ marker, chain position "quest 3/11", current quest objectives, upcoming quest names, and a click → TomTom waypoint to the correct place given actual progress (giver if not started, objective if in log).
- Unmapped criteria still render from the Blizzard API — no data entry required for the browser to be useful on every achievement.

**C. Tracker strip (optional pin)**
- Compact always-visible panel for 1–3 pinned achievements: name, bar, active chain line. Click-through to detail.

## 2. Core APIs (all client-side)

```lua
-- enumeration / search index
GetCategoryList(); GetCategoryNumAchievements(cat); GetAchievementInfo(cat, i)
GetAchievementNumCriteria(id); GetAchievementCriteriaInfo(id, i)  -- desc, done, qty, req
-- events: ACHIEVEMENT_EARNED, CRITERIA_UPDATE (debounce!)

-- chain awareness (mapped criteria)
GetAchievementCriteriaInfo(id, i)               -- 8th return assetID = questID for quest-typed criteria (the auto-map key)
C_QuestLine.GetQuestLineInfo(questID, mapID)    -- takes a QUEST id → questLineID, questLineName, pickup x/y
C_QuestLine.GetQuestLineQuests(questLineID)     -- ordered quest IDs for the whole chain
C_QuestLine.RequestQuestLinesForMap(mapID)      -- warm the data first; retry on QUESTLINE_UPDATE
C_QuestLog.IsQuestFlaggedCompleted(id); C_QuestLog.IsOnQuest(id)
C_QuestLog.GetTitleForQuestID(id)               -- may be nil until cached:
C_QuestLog.RequestLoadQuestByID(id)             -- then QUEST_DATA_LOAD_RESULT fires
C_QuestLog.GetQuestObjectives(id)               -- live objective text + progress
C_QuestLog.GetNextWaypointForMap(id, mapID)     -- objective routing (supertracker point)
QuestPOIGetIconInfo(id)                         -- fallback objective blob center
-- TomTom:AddWaypoint(mapID, x, y, {title=...})
```

### ChainState (the heart of it)
```lua
local function ChainState(ql)
  local quests = C_QuestLine.GetQuestLineQuests(ql)
  local s = { total = #quests, done = 0, active = nil, upcoming = {} }
  for i, q in ipairs(quests) do
    if C_QuestLog.IsQuestFlaggedCompleted(q) then s.done = s.done + 1
    elseif C_QuestLog.IsOnQuest(q) and not s.active then
      s.active = { index = i, id = q, name = C_QuestLog.GetTitleForQuestID(q),
                   objectives = C_QuestLog.GetQuestObjectives(q) }
    else table.insert(s.upcoming, { index = i, id = q, name = C_QuestLog.GetTitleForQuestID(q) }) end
  end
  return s
end
```

### Waypoint logic
- chain not started → `GetQuestLineInfo` across the achievement's `maps` list → giver
- active quest in log → `GetNextWaypointForMap` / `GetNextWaypoint` → objective; fallback `QuestPOIGetIconInfo`
- refresh arrow on `QUEST_TURNED_IN`, `QUEST_WATCH_UPDATE` (auto-advance)

## 3. Criterion → chain mapping (automatic, with a manual escape hatch)

The client can discover chains itself: quest-typed criteria carry a questID in `assetID`, and `GetQuestLineInfo(questID, mapID)` returns the `questLineID` that quest belongs to (works from any quest in the chain, first or last).

```lua
local function AutoMap(achID, mapID)
  C_QuestLine.RequestQuestLinesForMap(mapID)          -- warm data; may need retry on QUESTLINE_UPDATE
  local out = {}
  for i = 1, GetAchievementNumCriteria(achID) do
    local desc, ctype, _, _, _, _, _, assetID = GetAchievementCriteriaInfo(achID, i)
    if assetID and assetID > 0 then
      local info = C_QuestLine.GetQuestLineInfo(assetID, mapID)
      if info then out[i] = { name = desc, questLineID = info.questLineID } end
    end
  end
  return out   -- cache in QuestGlassDB.automap[achID], keyed by build version
end
```

- Run once per achievement (`/qg automap <id>` in P2 debug), cache results in SavedVariables.
- `Overrides.lua`: tiny manual table ONLY for criteria that don't self-resolve (assetID = 0, non-quest criteria types, or GetQuestLineInfo nil on every candidate map). Expected to be small or empty for storyline achievements.
- Candidate maps for the lookup: the achievement's zone maps (e.g. {2395, 2393}); try each until one resolves.
- Faction-variant chains (e.g. 90546/90547): treat either variant completed as done.

## 4. Files

```
QuestGlass/
  QuestGlass.toc      ## SavedVariables: QuestGlassDB
  Overrides.lua
  Search.lua          -- index build + fuzzy matcher
  Chains.lua          -- ChainState, waypoint logic
  UI.lua              -- frames (search, detail, tracker strip)
  Core.lua            -- events, slash commands, glue
```

Slash: `/qg` open search · `/qg way` arrow for active pin · `/qg pin <achID>`.

## 5. Phases

**P1 — search MVP (first session):** index + fuzzy search + plain detail view with live criteria. Already beats the default UI and `/att search`.
**P2 — chains:** `/qg automap 61957`, ChainState render, TomTom clicks, auto-advance; Overrides.lua only if automap leaves gaps.
**P3 — tracker strip + polish:** pinning, ESC handling, saved position/scale, name-cache warming via RequestLoadQuestByID.
**P4 — more data:** automap remaining Sojourners (should be free); consider non-storyline mappings (rares, treasures) with static coords.

## 6. Gotchas / verify early
- Index build cost with ~4k achievements — chunk over OnUpdate or C_Timer loop.
- `CRITERIA_UPDATE` fires constantly; debounce 0.5–1 s.
- Future quest names nil until `RequestLoadQuestByID` → re-render on `QUEST_DATA_LOAD_RESULT`; cache resolved names in SavedVariables.
- Frame strata/ESC: register in `UISpecialFrames` so ESC closes it.
- Check current TOC interface number: `/run print((select(4, GetBuildInfo())))`.
