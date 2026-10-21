--[[
	StatusIncomingHeal.lua

	Shows the number of currently-casting/channeling heals targeting each
	raid/party member, using LibHealComm-4.0 (already bundled in
	Grid2/Libs/LibHealComm-4.0). Unlike a purely local UnitCastingInfo-based
	approach (which can only see who YOU have targeted/moused-over), this
	works group-wide for any healer running a LibHealComm-compatible addon
	(Grid2, VuhDo, Healbot, CLCRet, etc.) - including mouseover-cast heals,
	since LibHealComm has each healer's own copy broadcast their outgoing
	cast to the group via addon message, rather than relying on target-unit
	introspection of other players (which isn't possible at all via the
	WoW API - no addon can ever see what another player has targeted).

	HoTs (Rejuvenation, Renew, etc.) are deliberately excluded - only direct
	casts and channeled heals count, matching "how many heals are currently
	being CAST on this person" rather than "how many HoTs are ticking".

	Text status: shows the count (as a string - Grid2's own text-formatting
	utilities assume string values and will error on a raw number). Also
	tracks whether the LOCAL PLAYER's own pending heal on that unit
	currently has the earliest expiration time (i.e. will land first) -
	GetColor uses this to pick a distinct color.
]]

local Grid2 = Grid2
local IncHeal = Grid2.statusPrototype:new("incheal")

local LibHealComm = LibStub("LibHealComm-4.0", true)
local UnitGUID = UnitGUID
local select, pairs, wipe, tostring = select, pairs, wipe, tostring

local pending = {}   -- pending[destGUID] = { [casterGUID] = expirationTime, ... }
local count = {}     -- count[unit] = number of pending heals, or nil
local mineFirst = {} -- mineFirst[unit] = true if the player's own heal expires earliest
local playerGUID

local function Recompute(guid)
	local unit = Grid2:GetUnitidByGUID(guid)
	if not unit then
		return
	end
	local entries = pending[guid]
	local n, minExpire, isMine = 0, nil, nil
	if entries then
		for casterGUID, expirationTime in pairs(entries) do
			n = n + 1
			if not minExpire or expirationTime < minExpire then
				minExpire = expirationTime
				isMine = (casterGUID == playerGUID)
			end
		end
	end
	count[unit] = n > 0 and n or nil
	mineFirst[unit] = isMine or false
	IncHeal:UpdateIndicators(unit)
end

local function AddPending(casterGUID, expirationTime, ...)
	for i = 1, select("#", ...) do
		local destGUID = select(i, ...)
		if destGUID then
			pending[destGUID] = pending[destGUID] or {}
			pending[destGUID][casterGUID] = expirationTime
			Recompute(destGUID)
		end
	end
end

local function RemovePending(casterGUID, ...)
	for i = 1, select("#", ...) do
		local destGUID = select(i, ...)
		local entries = destGUID and pending[destGUID]
		if entries and entries[casterGUID] then
			entries[casterGUID] = nil
			Recompute(destGUID)
		end
	end
end

-- (event, casterGUID, spellID, healType, endTime, ...destGUIDs)
local function OnHealStarted(_, casterGUID, spellID, healType, endTime, ...)
	if healType == LibHealComm.HOT_HEALS then
		return -- HoTs don't count towards "currently being cast"
	end
	AddPending(casterGUID, endTime, ...)
end

local function OnHealUpdated(_, casterGUID, spellID, healType, endTime, ...)
	if healType == LibHealComm.HOT_HEALS then
		return
	end
	AddPending(casterGUID, endTime, ...)
end

local function OnHealDelayed(_, casterGUID, spellID, healType, endTime, ...)
	if healType == LibHealComm.HOT_HEALS then
		return
	end
	AddPending(casterGUID, endTime, ...)
end

-- (event, casterGUID, spellID, healType, ...destGUIDs) - no endTime, cast ended
local function OnHealStopped(_, casterGUID, spellID, healType, ...)
	RemovePending(casterGUID, ...)
end

function IncHeal:OnEnable()
	if not LibHealComm then
		return
	end
	playerGUID = playerGUID or UnitGUID("player")
	LibHealComm.RegisterCallback(self, "HealComm_HealStarted", OnHealStarted)
	LibHealComm.RegisterCallback(self, "HealComm_HealUpdated", OnHealUpdated)
	LibHealComm.RegisterCallback(self, "HealComm_HealDelayed", OnHealDelayed)
	LibHealComm.RegisterCallback(self, "HealComm_HealStopped", OnHealStopped)
end

function IncHeal:OnDisable()
	if not LibHealComm then
		return
	end
	LibHealComm.UnregisterAllCallbacks(self)
	wipe(pending)
	wipe(count)
	wipe(mineFirst)
end

function IncHeal:IsActive(unit)
	return count[unit] ~= nil
end

function IncHeal:GetText(unit)
	local n = count[unit]
	return n and tostring(n) or nil
end

function IncHeal:GetColor(unit)
	local c = mineFirst[unit] and self.dbx.color2 or self.dbx.color1
	return c.r, c.g, c.b, c.a
end

local function Create(baseKey, dbx)
	Grid2:RegisterStatus(IncHeal, {"text", "color"}, baseKey, dbx)
	return IncHeal
end

Grid2.setupFunc["incheal"] = Create
Grid2:DbSetStatusDefaultValue("incheal", {
	type = "incheal",
	color1 = {r = 1, g = 1, b = 1, a = 1}, -- default color (not the earliest pending heal)
	color2 = {r = 0, g = 1, b = 0, a = 1}  -- "my heal lands first" color: green
})