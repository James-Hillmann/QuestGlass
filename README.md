# QuestGlass

In-game achievement browser for WoW Retail: fast fuzzy search over achievement
names **and** criteria, a clean detail view with live progress — and (coming in
P2) storyline-chain awareness with one-click TomTom arrows.

Pure in-game Lua. No external app, no scraping at runtime.

**Status: P1 (search MVP).** See [ROADMAP.md](ROADMAP.md) for what's next.

## Install (Windows, via git)

Clone the repo directly into your AddOns folder — the repo root *is* the addon
folder:

```
git clone https://github.com/James-Hillmann/QuestGlass.git "E:\Battlenet\World of Warcraft\_retail_\Interface\AddOns\QuestGlass"
```

(Adjust the path if WoW is installed elsewhere — check the Battle.net app →
WoW → gear icon → Show in Explorer.)

To update later, double-click `Update-QuestGlass.bat` in the addon folder
(make a Desktop shortcut to it), or run:

```
git -C "E:\Battlenet\World of Warcraft\_retail_\Interface\AddOns\QuestGlass" pull
```

If WoW is running, `/reload` picks up the new files. Fully restart the client
only if you changed the `.toc`.

## Usage

| Command | Effect |
|---|---|
| `/qg` | Toggle the window (search box auto-focused) |
| `/qg <text>` | Open with a search already run, e.g. `/qg sojourner` |
| `/qg pin <achID>` | Pin/unpin an achievement (easier: the Pin button in the detail view) |
| `/qg way` | Re-point the arrow at the tracked storyline |
| `/qg automap <achID>` | Debug: show quest→questline mapping for an achievement |
| `/qg options` | Open the options panel (scales, strip lock, combat hide) |
| `/qg rebuild` | Force a full index rebuild (normally automatic per patch) |

- With an empty search box, the window shows your "closest to completion"
  list — every in-progress achievement, best first.
- Results rank incomplete achievements first, then by match quality.
- Matches criteria names too: searching a quest name finds the meta-achievement
  that requires it.
- Click a result for the detail view: progress bar + live criteria, incomplete
  first. Enter in the search box opens the top result.
- Criteria marked ▶ are mapped storylines: click one to track it — a summary
  panel shows chain progress, the active quest's objective, and what's next,
  and the arrow (TomTom if installed, otherwise Blizzard's map pin) points at
  the right spot for your progress. It advances automatically as you turn
  quests in.
- **Pin** up to 3 achievements (button in the detail view) to a compact
  tracker strip that stays on screen: name, progress bar, and the live
  storyline step. Left-click a row to open it, right-click to re-point the
  arrow, drag to move; the X on a row unpins. Earned achievements unpin
  themselves. Pins persist across sessions.
- ESC closes the window (first ESC unfocuses the search box if you're
  typing) — the strip keeps your place. Drag anywhere to move; position is
  saved.
- **Other ways in**: bind a key under Options → Keybindings → AddOns; click
  QuestGlass in the addon compartment (minimap dropdown); or **Ctrl+click an
  achievement in Blizzard's achievement UI** to open it in QuestGlass.
- **Shift-click** a search result to link the achievement in chat.
- `/qg options`: window & strip scale sliders, lock the strip, hide the strip
  in combat.

## Troubleshooting

- **Addon shows "out of date"**: the interface number in `QuestGlass.toc` is
  behind the client. Get the current one in-game with
  `/run print((select(4, GetBuildInfo())))` and update the `## Interface:` line.
- **First login after install/patch**: the index builds in the background over
  a few seconds ("Indexing achievements…" in the window). It's cached in
  SavedVariables afterwards, so later logins are instant.
