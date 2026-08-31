local ADDON, NS = ...

-- Manual escape hatch for criteria the automapper can't resolve
-- (assetID = 0, non-quest criteria, or no quest line found on any map).
-- Shape: NS.Overrides[achievementID] = { [questID] = questLineID }
-- Find IDs with `/qg automap <achievementID>` output.
NS.Overrides = {
}
