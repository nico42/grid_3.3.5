--[[
	StatusHealsAoe.lua

	Generic combat-log based "AOE & Damage" tracker, backported from modern
	Grid2 (Classic branch: modules/StatusHealsAoe.lua).

	Unlike the positional Grid2AoeHeals addon (which predicts who WOULD be
	hit by an AoE heal based on unit map positions), this status reacts to
	the combat log: it flags a unit as "active" for a short time whenever
	one of the configured spells actually hits it with a matching event.

	Because it's driven by the combat log instead of positions, the exact
	same engine works for incoming/outgoing HEALS as well as DAMAGE (e.g.
	a boss AoE ability, a cleave, etc.) - just enable the "Damage" event
	instead of (or in addition to) "Heal" for a given tracker, and add the
	spell(s) you want to watch. Multiple independent trackers can be
	created (see Grid2Options -> Statuses -> AOE & Damage).

	WotLK 3.3.5 note: this client does not have CombatLogGetCurrentEventInfo()
	(added in a later expansion); the combat log payload is passed directly
	as the event handler's arguments instead, same as the rest of this
	addon's existing combat-log code (see Grid2AoeHeals/AoeHealsStatusOutgoing.lua).
]]

local Grid2 = Grid2
local next, pairs, wipe = next, pairs, wipe
local GetTime = GetTime
local GetSpellInfo = GetSpellInfo
local UnitGUID = UnitGUID

-- TEMPORARY debug switch: prints every relevant step to chat so we can see
-- exactly where the pipeline breaks. Set to false (or delete these prints)
-- once everything works.
local DEBUG = false
local function Debug(...)
	if DEBUG then
		print("|cFF33FF99AoeDebug|r:", ...)
	end
end

local playerGUID
local timer
local timerDelay = 2
local spells = {}           -- spells[spellName] = { [status] = true, ... }
local icons  = {}           -- icons[spellName]  = icon texture
local statuses_enabled = {} -- statuses_enabled[status] = true

-- default event set for the "aoe-heals" (preset) tracker type
local HEAL_EVENTS = {
	SPELL_HEAL = true,
	SPELL_PERIODIC_HEAL = true,
}

--{{{ shared combat log listener (one registration, no matter how many trackers exist)

local function TimerEvent()
	local count = 0
	local time = GetTime()
	for status in pairs(statuses_enabled) do
		local heal_cache = status.heal_cache
		local time_cache = status.time_cache
		for unit, expire in pairs(time_cache) do
			if time >= expire then
				heal_cache[unit] = nil
				time_cache[unit] = nil
				status:UpdateIndicators(unit)
			end
		end
		if next(time_cache) then
			count = count + 1
		end
	end
	if count == 0 and timer then
		-- Grid2:CancelTimer() (AceTimer-3.0) returns true/false, NOT nil!
		-- Assigning that return value back to `timer` left it set to `true`
		-- instead of nil, so the "if not timer then ... end" restart guard
		-- in CombatLogEvent below never fired again after the first time
		-- the timer self-canceled - meaning cached units were never expired
		-- again and stayed lit up forever. Must be set to nil explicitly.
		Grid2:CancelTimer(timer)
		timer = nil
	end
end

-- Registered via Grid2:RegisterEvent (AceEvent-3.0, embedded in Grid2 core),
-- NOT a raw CreateFrame:SetScript("OnEvent",...) - AceEvent dispatches
-- callbacks as (event, ...) with NO frame reference prepended, unlike plain
-- frame scripts which pass (self, event, ...). Mixing the two conventions
-- up shifts every argument by one position and silently breaks matching.
--
-- WotLK 3.3.5 combat log event args (SPELL_* sub-events):
-- event, timestamp, subEvent, srcGUID, srcName, srcFlags, dstGUID, dstName,
-- dstFlags, spellId, spellName, spellSchool, ...
-- (only SPELL_* sub-events are supported: SWING_DAMAGE/RANGE_DAMAGE have a
-- different payload without a spell name and are not tracked here)
local function CombatLogEvent(_, _, subEvent, srcGUID, _, _, dstGUID, _, _, _, spellName)
	if subEvent and subEvent:match("^SPELL") then
		Debug("combat log:", subEvent, spellName, "mine:", srcGUID == playerGUID)
	end
	local list = spellName and spells[spellName]
	if not list then
		return
	end
	Debug("spell is tracked by", (function() local n=0 for _ in pairs(list) do n=n+1 end return n end)(), "status(es)")
	for status in pairs(list) do
		if status.events[subEvent] then
			local mine = status.mine
			if mine == nil or mine == (srcGUID == playerGUID) then
				local unit = Grid2:GetUnitidByGUID(dstGUID)
				Debug("event matched, dstGUID:", dstGUID, "-> unit:", unit or "NOT FOUND IN ROSTER")
				if unit then
					local prev = status.heal_cache[unit]
					status.heal_cache[unit] = spellName
					status.time_cache[unit] = GetTime() + status.activeTime
					if prev ~= spellName then
						status:UpdateIndicators(unit)
						Debug("UpdateIndicators called for", unit)
						if not timer then
							timer = Grid2:ScheduleRepeatingTimer(TimerEvent, timerDelay)
						end
					end
				end
			else
				Debug("event matched spell/type but 'mine' filter rejected it")
			end
		end
	end
end

--}}}

--{{{ status methods (assigned per-instance in Create(), same convention as StatusRole.lua)

local function OnEnable(self)
	Debug("OnEnable called for status", self.name)
	if not next(statuses_enabled) then
		Grid2:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", CombatLogEvent)
		Debug("registered COMBAT_LOG_EVENT_UNFILTERED")
	end
	statuses_enabled[self] = true
	if self.dbx.spellList then
		for _, spell in next, self.dbx.spellList do
			local name, _, icon = GetSpellInfo(spell)
			if name then
				spells[name] = spells[name] or {}
				spells[name][self] = true
				icons[name] = icon
				Debug("registered spell:", spell, "->", name)
			else
				Debug("WARNING: spellList entry", spell, "did not resolve via GetSpellInfo!")
			end
		end
	else
		Debug("WARNING: self.dbx.spellList is nil, nothing to track")
	end
end

local function OnDisable(self)
	wipe(self.heal_cache)
	wipe(self.time_cache)
	statuses_enabled[self] = nil
	for key, list in pairs(spells) do
		if list[self] then
			list[self] = nil
			if not next(list) then
				spells[key] = nil
			end
		end
	end
	if not next(statuses_enabled) then
		Grid2:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
end

local function IsActive(self, unit)
	return self.heal_cache[unit] ~= nil
end

local function GetColor(self, unit)
	local c = self.dbx.color1
	return c.r, c.g, c.b, c.a
end

local function GetIcon(self, unit)
	local spell = self.heal_cache[unit]
	return spell and icons[spell]
end

local function GetText(self, unit)
	return self.heal_cache[unit]
end

local function UpdateDB(self)
	if self.enabled then
		OnDisable(self)
	end
	self.activeTime = self.dbx.activeTime or 2
	self.mine = self.dbx.mine -- true = only my casts, false = only others', nil = any
	self.events = self.dbx.events or HEAL_EVENTS
	timerDelay = math.max(0.1, math.min(timerDelay, self.activeTime / 4))
	Debug("UpdateDB for", self.name, "- enabled:", self.enabled and "YES" or "NO (not mapped to any indicator!)", "- events:", (function()
		local t = {}
		for e in pairs(self.events) do t[#t+1] = e end
		return table.concat(t, ",")
	end)())
	if self.enabled then
		OnEnable(self)
	end
end

--}}}

local function Create(baseKey, dbx)
	playerGUID = playerGUID or UnitGUID("player")
	local status = Grid2.statusPrototype:new(baseKey)
	status.heal_cache = {}
	status.time_cache = {}
	status.OnEnable = OnEnable
	status.OnDisable = OnDisable
	status.IsActive = IsActive
	status.GetColor = GetColor
	status.GetIcon = GetIcon
	status.GetText = GetText
	status.UpdateDB = UpdateDB
	Grid2:RegisterStatus(status, {"color", "icon", "text"}, baseKey, dbx)
	status:UpdateDB()
	return status
end

-- "aoe-heals"  : preset trackers with class-specific default heal spells (see Options)
-- "inc-spells" : fully custom tracker, any spell / any event (heal, damage, cast)
Grid2.setupFunc["aoe-heals"] = Create
Grid2.setupFunc["inc-spells"] = Create
