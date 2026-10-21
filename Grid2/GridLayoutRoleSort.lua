--[[
	GridLayoutRoleSort.lua

	Adds custom Grid2 layouts that keep the normal 5-man raid subgroups
	(same visual grouping as "By Group 25/40"), but sort the members
	*within* each subgroup by role:

		Tank -> Damager (DPS) -> None (role not detected) -> Healer

	Role detection uses Grid2.GetUnitRole(), which:
		1) uses the LFD/Dungeon-Finder role if the unit queued with one
		2) falls back to a talent-based guess via LibGroupTalents-1.0
		   (melee/caster -> DAMAGER, healer -> HEALER, tank -> TANK)
		3) returns "NONE" if nothing could be determined (yet)

	Note: Blizzard's SecureGroupHeader in 3.3.5 does NOT support sorting
	by class-role out of the box (groupBy="ROLE" only recognizes
	MAINTANK/MAINASSIST raid target assignments), and its "nameList"
	sort method is ignored whenever "groupFilter" is also set. So this
	file manually computes one "nameList" per flagged header and keeps
	it updated.

	Any header (in ANY layout - one of the fixed ones below, or a header
	built in Grid2's Layout Editor) that has `roleSort = true` set on it
	gets this treatment automatically: the engine scans the *currently
	active* layout's header definitions every time it needs to refresh,
	rather than hardcoding a fixed list of layout names. This is what
	lets "Role" show up as a normal "Sort by" option for custom layouts
	too (see Grid2Options/modules/general/GridLayoutsEditor.lua) - not
	just in the 4 fixed layouts defined here.
]]

local Grid2Layout = Grid2Layout

--{{{ Layout definitions

-- Lower number = higher up in the group.
local RolePriority = {
	TANK    = 1,
	DAMAGER = 2,
	NONE    = 3,
	HEALER  = 4,
}

-- same pet class ordering used by Grid2's native "w/Pets" layouts
local DEFAULT_PET_ORDER = "HUNTER,WARLOCK,DEATHKNIGHT,PRIEST,MAGE,DRUID,SHAMAN,WARRIOR,ROGUE,PALADIN"

-- "extra" is an optional list of additional header configs appended after
-- the role-sorted player groups (e.g. a pet column). These must NOT inherit
-- sortMethod="NAMELIST"/nameList/roleSort from the player groups, or they'd
-- render empty, so those are set per player-group entry instead of in
-- "defaults". `groupFilter` here is NOT passed through to Blizzard live (the
-- runtime engine strips it at runtime, see UpdateHeaders below) - it's only
-- kept in the static table as metadata so the engine knows which raid
-- subgroup(s) each header should include.
local function MakeRoleSortLayout(name, meta, groupCount, extra)
	local layout = {
		meta = meta,
		defaults = {
			showPlayer         = true,
			showParty          = true,
			showRaid           = true,
			showSolo           = true,
			allowVehicleTarget = true,
			toggleForVehicle   = true,
		},
	}
	for i = 1, groupCount do
		layout[i] = {
			sortMethod  = "NAMELIST",
			nameList    = "",
			groupFilter = tostring(i),
			roleSort    = true,
		}
	end
	if extra then
		for i, entry in ipairs(extra) do
			layout[groupCount + i] = entry
		end
	end
	Grid2Layout:AddLayout(name, layout)
end

-- covers solo / party / 10-25 man raids (5 subgroups) + a pet column on the side
MakeRoleSortLayout(
	"By Group 25 - Sorted by Role",
	{raid25 = true, raid15 = true, raid10 = true, party = true, solo = true},
	5,
	{
		{
			type           = "raidpet",
			groupingOrder  = DEFAULT_PET_ORDER,
			unitsPerColumn = 25,
			maxColumns     = 1,
		},
	}
)

-- covers up to 40-man raids (8 subgroups)
MakeRoleSortLayout("By Group 40 - Sorted by Role", {raid40 = true}, 8)

-- party / solo (1 subgroup) + a pet row below it
MakeRoleSortLayout(
	"By Group 5 - Sorted by Role",
	{party = true, solo = true},
	1,
	{
		{
			type           = "partypet",
			groupingOrder  = DEFAULT_PET_ORDER,
			unitsPerColumn = 5,
			maxColumns     = 1,
		},
	}
)

-- 10-man raid (2 subgroups) + a pet row below it
MakeRoleSortLayout(
	"By Group 10 - Sorted by Role",
	{raid10 = true},
	2,
	{
		{
			type           = "raidpet",
			groupingOrder  = DEFAULT_PET_ORDER,
			unitsPerColumn = 10,
			maxColumns     = 1,
		},
	}
)

-- Layouts whose pet header should render as a single, full-width, flattened
-- row anchored below the player groups, instead of Grid2's normal
-- side-by-side column behaviour (used by "By Group 25 - Sorted by Role").
-- This part stays name-keyed on purpose: it's a bespoke visual layout for
-- these 2 specific fixed layouts, not something exposed in the Layout Editor.
local PET_ROW_LAYOUTS = {
	["By Group 5 - Sorted by Role"]  = {petType = "partypet", groupCount = 1},
	["By Group 10 - Sorted by Role"] = {petType = "raidpet",  groupCount = 2},
}
local PET_ROW_WIDTH_PCT  = 1.00 -- 100% of a normal unit frame's width
local PET_ROW_HEIGHT_PCT = 0.64 -- 64% of a normal unit frame's height

--}}}

--{{{ Runtime sorting logic

local GetUnitRole        = Grid2.GetUnitRole
local GetNumRaidMembers   = GetNumRaidMembers
local GetRaidRosterInfo   = GetRaidRosterInfo
local GetNumPartyMembers  = GetNumPartyMembers
local UnitExists          = UnitExists
local UnitName            = UnitName
local InCombatLockdown    = InCombatLockdown
local tsort               = table.sort
local tconcat             = table.concat

-- used to override the pet row's frame size; safe to fail silently if the
-- module isn't found for some reason (layout will just keep default sizes)
local Grid2Frame = Grid2:GetModule("Grid2Frame", true)

local groupMembers = {} -- groupMembers[subgroup] = { {name=,prio=}, ... }

local function ClearGroupMembers()
	for i = 1, 8 do
		local t = groupMembers[i]
		if t then
			for j = #t, 1, -1 do
				t[j] = nil
			end
		else
			t = {}
			groupMembers[i] = t
		end
	end
end

local function AddMember(subgroup, unit, name)
	local t = groupMembers[subgroup]
	if t and name then
		local role = GetUnitRole(unit)
		t[#t + 1] = {
			name = name,
			prio = RolePriority[role] or RolePriority.NONE,
			isPlayer = UnitIsUnit(unit, "player") and true or false,
		}
	end
end

local function BuildRoster()
	ClearGroupMembers()
	local count = GetNumRaidMembers()
	if count > 0 then
		for i = 1, count do
			local name, _, subgroup = GetRaidRosterInfo(i)
			if name then
				AddMember(subgroup, "raid" .. i, name)
			end
		end
	else
		if UnitExists("player") then
			AddMember(1, "player", UnitName("player"))
		end
		for i = 1, GetNumPartyMembers() do
			local unit = "party" .. i
			if UnitExists(unit) then
				AddMember(1, unit, UnitName(unit))
			end
		end
	end
end

-- "Player always last" option (Layout settings): the player is moved behind
-- everybody else in the group he is shown in, whatever his role is.
local playerLast = false

local function SortMembers(a, b)
	if playerLast and a.isPlayer ~= b.isPlayer then
		return b.isPlayer
	end
	if a.prio ~= b.prio then
		return a.prio < b.prio
	end
	return a.name < b.name
end

-- Parses a header's static `groupFilter` metadata ("1", "1,2,3", ...) into a
-- lookup set of subgroup numbers. Returns nil to mean "no restriction / all
-- subgroups", matching Blizzard's own fallback behavior for an unset filter.
local function GetGroupFilterSet(groupFilter)
	if not groupFilter then
		return nil
	end
	local set, any = {}, false
	for token in tostring(groupFilter):gmatch("[^,]+") do
		local n = tonumber(token)
		if n then
			set[n] = true
			any = true
		end
	end
	return any and set or nil
end

-- Builds a flat, role-sorted "name,name,..." list from every already-built
-- groupMembers[] subgroup that matches filterSet (or all of them if nil).
local mergedScratch = {}
local listScratch = {}
local function BuildNameListForFilter(filterSet)
	for i = #mergedScratch, 1, -1 do
		mergedScratch[i] = nil
	end
	for subgroup = 1, 8 do
		if not filterSet or filterSet[subgroup] then
			local members = groupMembers[subgroup]
			if members then
				for i = 1, #members do
					mergedScratch[#mergedScratch + 1] = members[i]
				end
			end
		end
	end
	tsort(mergedScratch, SortMembers)
	for i = #listScratch, 1, -1 do
		listScratch[i] = nil
	end
	for i = 1, #mergedScratch do
		listScratch[i] = mergedScratch[i].name
	end
	return tconcat(listScratch, ",")
end

local pendingUpdate = false

-- Scans the CURRENTLY ACTIVE layout's own header definitions (fixed layout
-- or one built in the Layout Editor - doesn't matter which) for any header
-- flagged `roleSort = true`, and (re)computes its nameList. Mirrors the same
-- per-type index counting Grid2Layout:LoadLayout uses internally, so this
-- correctly maps back to the right live header frame even when a layout
-- mixes "raid" and "party" type headers.
local function UpdateHeaders()
	local layout = Grid2Layout.layoutSettings[Grid2Layout.layoutName]
	if not layout then
		return
	end

	local hasRoleSort = false
	for i = 1, #layout do
		if layout[i].roleSort then
			hasRoleSort = true
			break
		end
	end
	if not hasRoleSort then
		return
	end

	if InCombatLockdown() then
		pendingUpdate = true
		return
	end
	pendingUpdate = false

	local db = Grid2Layout.db and Grid2Layout.db.profile
	playerLast = db and db.playerLast or false

	BuildRoster()

	local default_type = (layout.defaults and layout.defaults.type) or "raid"
	local typeIndex = {}
	for i = 1, #layout do
		local h = layout[i]
		local htype = h.type or default_type
		typeIndex[htype] = (typeIndex[htype] or 0) + 1
		if h.roleSort then
			local pool = Grid2Layout.groups[htype]
			local header = pool and pool[typeIndex[htype]]
			if header then
				local nameListStr = BuildNameListForFilter(GetGroupFilterSet(h.groupFilter))
				-- nameList is ignored by Blizzard's header code whenever a
				-- live groupFilter attribute is also present, so that has
				-- to be cleared here even though the static table above
				-- still has it (kept only as metadata for this scan).
				if header:GetAttribute("groupFilter") then
					header:SetAttribute("groupFilter", nil)
				end
				if header:GetAttribute("sortMethod") ~= "NAMELIST" then
					header:SetAttribute("sortMethod", "NAMELIST")
				end
				if header:GetAttribute("nameList") ~= nameListStr then
					header:SetAttribute("nameList", nameListStr)
				end
			end
		end
	end
end

--}}}

--{{{ Pet row (5/10-man layouts): full-width, flattened row below the groups

local function GetPetRowHeader(petType)
	local pool = petType and Grid2Layout.groups[petType]
	return pool and pool[1]
end

-- resizes every currently-existing pet button; "petType" nil/false = do
-- nothing, otherwise squish it to 100%/64% of the normal frame size
local function ResizePetRowButtons(petType)
	if not Grid2Frame or InCombatLockdown() then
		return
	end
	local header = GetPetRowHeader(petType)
	if not header then
		return
	end
	local baseW, baseH = Grid2Frame:GetFrameSize()
	local w = petType and (baseW * PET_ROW_WIDTH_PCT) or baseW
	local h = petType and (baseH * PET_ROW_HEIGHT_PCT) or baseH
	local i = 1
	local button = header:GetAttribute("child" .. i)
	while button do
		button:SetWidth(w)
		button:SetHeight(h)
		i = i + 1
		button = header:GetAttribute("child" .. i)
	end
end

-- Finds the widest of the groupCount player-group headers (by current pixel
-- width), so the pet row can line up with whichever group actually takes up
-- the most horizontal space - rather than always the last one, which can be
-- narrower than an earlier group whenever raid composition is uneven
-- (e.g. group orientation is horizontal and the last subgroup currently has
-- fewer members than another one).
-- Finds which player group(s) sit LOWEST on screen (smallest GetBottom()),
-- and among those (there's more than one only when groups are arranged
-- side-by-side at the same height), picks the WIDEST one. This handles
-- both common arrangements correctly:
--   - groups stacked vertically: only one group is actually the lowest,
--     so that one gets picked regardless of width (fixes the pet row
--     otherwise ending up anchored to a WIDER but higher-up group,
--     appearing in the middle of the frame instead of at the bottom)
--   - groups placed side-by-side: they all share the same bottom edge, so
--     "lowest" ties between all of them, and the widest of those wins -
--     which is what the original per-width fix was about (lining the pet
--     row's left edge up with whichever column actually extends furthest)
local function GetAnchorGroup(groupCount)
	local candidates = {}
	local minBottom
	for i = 1, groupCount do
		local group = Grid2Layout.groups.raid[i]
		if group then
			local bottom = group:GetBottom()
			if bottom then
				if not minBottom or bottom < minBottom - 0.5 then
					minBottom = bottom
					candidates = {group}
				elseif bottom <= minBottom + 0.5 then
					candidates[#candidates + 1] = group
				end
			end
		end
	end

	local widest, widestWidth
	for i = 1, #candidates do
		local group = candidates[i]
		local w = group:GetWidth()
		if not widestWidth or w > widestWidth then
			widest, widestWidth = group, w
		end
	end
	return widest
end

-- anchors the pet header below the lowest (and, if tied, widest) player
-- group, and forces its members into a single horizontal row, independent
-- of the general group orientation
local function RepositionPetRow(petType, groupCount)
	local header = GetPetRowHeader(petType)
	if not header then
		return
	end
	local anchorGroup = GetAnchorGroup(groupCount)
	if not anchorGroup then
		return
	end
	local p = Grid2Layout.db.profile

	header:ClearAllPoints()
	header:SetPoint("TOPLEFT", anchorGroup, "BOTTOMLEFT", 0, -(p.Spacing or 0))
	header:SetLayoutAttribute("point", "LEFT")
	header:SetLayoutAttribute("xOffset", p.Padding or 0)
	header:SetLayoutAttribute("yOffset", 0)
	header:SetLayoutAttribute("unitsPerColumn", 40)
	header:SetLayoutAttribute("maxColumns", 1)
end

-- currently active pet-row header type, if any (used by the LayoutFrames hook)
local activePetRowType

local function AdjustPetRow()
	local entry = PET_ROW_LAYOUTS[Grid2Layout.layoutName]
	local petType = entry and entry.petType
	activePetRowType = petType
	if entry then
		RepositionPetRow(entry.petType, entry.groupCount)
	end
	-- also clears the squish on any header left over from a previous
	-- pet-row layout when switching away from one
	ResizePetRowButtons(petType)
end

--}}}

local function RefreshAll()
	UpdateHeaders()
	AdjustPetRow()
	-- Grid2Layout:UpdateSize() recomputes the whole addon window's size;
	-- calling it here (rather than relying on it happening on its own)
	-- ensures GridLayoutHeaderCustom.lua's bounding-box size correction
	-- (hooked onto UpdateSize) re-runs after the pet row gets repositioned,
	-- so the whole window doesn't visibly drift as the widest group changes.
	if not InCombatLockdown() then
		Grid2Layout:UpdateSize()
	end
end

-- called by the options when "Player always last" is toggled
function Grid2Layout:RefreshRoleSort()
	RefreshAll()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if pendingUpdate then
			RefreshAll()
		end
	else
		RefreshAll()
	end
end)

-- Re-sort once talent-based role guesses come in for units we couldn't
-- identify yet (LibGroupTalents inspects group members asynchronously).
do
	local LibGroupTalents = LibStub("LibGroupTalents-1.0", true)
	if LibGroupTalents then
		LibGroupTalents.RegisterCallback(eventFrame, "LibGroupTalents_UpdateComplete", RefreshAll)
	end
end

-- Recompute right after a (re)load of the layout, e.g. when the player
-- switches into one of our role-sorted layouts, or group size changes.
hooksecurefunc(Grid2Layout, "LoadLayout", RefreshAll)

-- Whenever Grid2 re-applies frame settings (color, texture, border, size...)
-- it resets EVERY unit frame back to the global frame size, which would undo
-- our pet-row squish. Re-apply it right after, but only while a pet-row
-- layout is actually active.
if Grid2Frame then
	hooksecurefunc(Grid2Frame, "LayoutFrames", function()
		ResizePetRowButtons(activePetRowType)
	end)
end