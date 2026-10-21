--[[
	StatusHealsAoe.lua (Options)

	Options panel for the generic combat-log based "AOE & Damage" tracker
	(see Grid2/modules/StatusHealsAoe.lua). Backported from modern Grid2
	(Classic branch: Options/modules/statuses/StatusHealsAoe.lua), adapted
	for WotLK 3.3.5:
	  - GetSpellInfo() in 3.3.5 does not return a spellId (that was added in
	    a later expansion), so spell-name -> id lookups rely purely on
	    scanning + caching instead of select(7, GetSpellInfo(name)).
	  - No Grid2.API wrapper / no C_Spell in 3.3.5, plain GetSpellInfo is used.
	  - Uses this fork's actual delete-status convention (MakeStatusDeleteOptions)
	    instead of the newer isDeletable/displayPrefix optionParams flags,
	    which this Grid2Options version does not implement.
]]

local Grid2 = Grid2
local Grid2Options = Grid2Options
local L = Grid2Options.L

local select, next, pairs, wipe = select, next, pairs, wipe
local strtrim, strsplit, tonumber = strtrim, strsplit, tonumber
local GetSpellInfo = GetSpellInfo

-- Default AoE-heal presets, tuned for WotLK 3.3.5 (rank doesn't matter: the
-- combat log identifies spells by name, so any valid rank id works here)
local classHeals = {
	SHAMAN = {1064},        -- Chain Heal
	PRIEST = {596, 34861},  -- Prayer of Healing, Circle of Healing
	DRUID  = {740, 48438},  -- Tranquility, Wild Growth
}

-- SWING_DAMAGE/RANGE_DAMAGE/SPELL_BUILDING_DAMAGE are intentionally excluded:
-- their combat log payload doesn't include a spell name, so they can't be
-- matched by this (name-based) tracker - see Grid2/modules/StatusHealsAoe.lua.
local dmgEvents = {
	SPELL_DAMAGE = true,
	SPELL_PERIODIC_DAMAGE = true,
}

local spells_cache = {}

-- Misc util functions

local function InitCache()
	for _, spells in next, classHeals do
		for _, id in next, spells do
			local name = GetSpellInfo(id)
			if name then
				spells_cache[name] = id
			end
		end
	end
end

local function FindCache(name)
	if not spells_cache[name] and not spells_cache[-1] then
		-- one-time full scan to resolve spell names typed by the user into ids
		-- (WotLK 3.3.5 client spell ids top out well below 90000)
		for i = 90000, 1, -1 do
			local n = GetSpellInfo(i)
			if n then
				spells_cache[n] = i
			end
		end
		spells_cache[-1] = true
	end
	return spells_cache[name] or 0
end

local function GetSpellID(name)
	return tonumber(name) or FindCache(name)
end

local function SetSpellsByCategory(typ, tab)
	if typ then
		for className, spells in pairs(classHeals) do
			if typ == className or typ == "" then
				for _, spellID in pairs(spells) do
					table.insert(tab, spellID)
				end
			end
		end
	end
end

local function GetSpellsByCategory(flag)
	local list = {}
	for class in pairs(classHeals) do
		list[class] = LOCALIZED_CLASS_NAMES_MALE[class] or class
	end
	list[""] = L["All Classes"]
	list["~"] = flag and L["None"] or nil
	return list
end

-- MakeStatusOutgoingOptions()
local function MakeStatusOutgoingOptions(self, status, options)
	self:MakeStatusColorOptions(status, options)
	options.showIfMine = {
		type = "toggle",
		order = 30,
		name = L["Show if mine"],
		desc = L["Show my spells only."],
		get = function() return status.dbx.mine == true end,
		set = function(_, v)
			status.dbx.mine = v or nil
			status:UpdateDB()
		end
	}
	options.showIfNotMine = {
		type = "toggle",
		order = 35,
		name = L["Show if not mine"],
		desc = L["Show others spells only."],
		get = function() return status.dbx.mine == false end,
		set = function(_, v)
			if v then
				status.dbx.mine = false
			else
				status.dbx.mine = nil
			end
			status:UpdateDB()
		end
	}
	options.spacer1 = {type = "header", order = 39, name = ""}
	options.activeTime = {
		name = L["Active time"],
		desc = L["Show the status for the specified number of seconds."],
		order = 40,
		type = "range",
		min = 0.2,
		max = 5,
		step = 0.1,
		get = function() return status.dbx.activeTime or 2 end,
		set = function(_, v)
			status.dbx.activeTime = v
			status:UpdateDB()
		end
	}
	options.auras = {
		type = "input",
		order = 50,
		width = "full",
		name = L["Spells"],
		desc = L["You can type spell IDs or spell names."],
		multiline = 10,
		get = function()
			local auras = {}
			for _, spell in pairs(status.dbx.spellList) do
				local name = GetSpellInfo(spell)
				if name then
					spells_cache[name] = spell
					auras[#auras + 1] = name
				end
			end
			return table.concat(auras, "\n")
		end,
		set = function(_, v)
			wipe(status.dbx.spellList)
			local auras = {strsplit("\n,", v)}
			for _, a in pairs(auras) do
				local aura = strtrim(a)
				if #aura > 0 then
					local spellID = tonumber(aura)
					if spellID then
						spellID = GetSpellInfo(spellID) and spellID or 0
					else
						spellID = GetSpellID(aura)
					end
					if spellID > 0 then
						table.insert(status.dbx.spellList, spellID)
					end
				end
			end
			status:UpdateDB()
		end
	}
	options.eventsSpacer = {type = "header", order = 45, name = L["Activation conditions"]}
	if status.dbx.type == "aoe-heals" then
		options.addSpells = {
			type = "select",
			order = 44,
			name = L["Add heal spells"],
			desc = "",
			get = function() end,
			set = function(_, v)
				SetSpellsByCategory(v, status.dbx.spellList)
				status:UpdateDB()
			end,
			values = GetSpellsByCategory
		}
		options.eventsHeal = {
			type = "toggle",
			order = 46,
			width = 0.62,
			name = L["Direct Heal"],
			desc = L["Enable the status when a spell is healing a player."],
			get = function() return status.dbx.events == nil or status.dbx.events.SPELL_HEAL end,
			set = function(_, v)
				local dbx = status.dbx
				dbx.events = dbx.events or {SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true}
				dbx.events.SPELL_HEAL = v or nil
				if not next(dbx.events) then
					dbx.events.SPELL_PERIODIC_HEAL = true
				elseif dbx.events.SPELL_HEAL and dbx.events.SPELL_PERIODIC_HEAL then
					dbx.events = nil
				end
				status:UpdateDB()
			end
		}
		options.eventsHealPeriodic = {
			type = "toggle",
			order = 46.5,
			width = 0.62,
			name = L["Periodic Heal"],
			desc = L["Enable the status when a spell is healing a player."],
			get = function() return status.dbx.events == nil or status.dbx.events.SPELL_PERIODIC_HEAL end,
			set = function(_, v)
				local dbx = status.dbx
				dbx.events = dbx.events or {SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true}
				dbx.events.SPELL_PERIODIC_HEAL = v or nil
				if not next(dbx.events) then
					dbx.events.SPELL_HEAL = true
				elseif dbx.events.SPELL_HEAL and dbx.events.SPELL_PERIODIC_HEAL then
					dbx.events = nil
				end
				status:UpdateDB()
			end
		}
	else
		status.dbx.events = status.dbx.events or {}
		options.eventsHeal = {
			type = "toggle",
			order = 46,
			width = 0.62,
			name = L["Direct Heal"],
			desc = L["Enable the status when a spell is healing a player."],
			get = function() return status.dbx.events.SPELL_HEAL end,
			set = function(_, v)
				status.dbx.events.SPELL_HEAL = v or nil
				status:UpdateDB()
			end
		}
		options.eventsHealPeriodic = {
			type = "toggle",
			order = 46.5,
			width = 0.62,
			name = L["Periodic Heal"],
			desc = L["Enable the status when a spell is healing a player."],
			get = function() return status.dbx.events.SPELL_PERIODIC_HEAL end,
			set = function(_, v)
				status.dbx.events.SPELL_PERIODIC_HEAL = v or nil
				status:UpdateDB()
			end
		}
		options.eventsDamage = {
			type = "toggle",
			order = 47,
			width = 0.62,
			name = L["Damage"],
			desc = L["Enable the status when a spell is causing damage to a player."],
			get = function() return status.dbx.events.SPELL_DAMAGE end,
			set = function(_, v)
				v = v or nil
				for event in pairs(dmgEvents) do
					status.dbx.events[event] = v
				end
				status:UpdateDB()
			end
		}
		options.eventsCastSuccess = {
			type = "toggle",
			order = 49,
			width = 0.62,
			name = L["Cast Success"],
			desc = L["Enable the status when a spell cast finish or on instant spells."],
			get = function() return status.dbx.events.SPELL_CAST_SUCCESS end,
			set = function(_, v)
				status.dbx.events.SPELL_CAST_SUCCESS = v or nil
				status:UpdateDB()
			end
		}
	end
	self:MakeStatusDeleteOptions(status, options)
end

-- MakeCategoryOptions()
local function MakeCategoryOptions()
	InitCache()
	local NewStatusName, NewClassHeals, NewSpellType
	return {
		newOutgoingStatusName = {
			type = "input",
			order = 50,
			width = "double",
			name = L["Type New Status Name"],
			desc = L["You can type any descriptive text to identify the new status."],
			get = function() return NewStatusName end,
			set = function(_, v)
				NewStatusName = strtrim(v)
			end,
			validate = function(_, v)
				v = strtrim(v)
				return (v == "" or Grid2:DbGetValue("statuses", "aoe-" .. v) or Grid2:DbGetValue("statuses", "spells-" .. v)) and
					L["Invalid status name or already in use."] or true
			end
		},
		newline = {type = "description", order = 51, name = "\n"},
		spellsType = {
			type = "select",
			order = 52,
			name = L["Spells type"],
			desc = L["Select what type of incoming spells to track."],
			get = function() return NewSpellType or 1 end,
			set = function(_, v)
				NewSpellType = v
				NewClassHeals = nil
			end,
			values = {L["AOE Heal"], L["Any Spell"]}
		},
		spellsCategory = {
			type = "select",
			order = 53,
			name = L["Spells group"],
			desc = "",
			get = function() return NewClassHeals or "~" end,
			set = function(_, v)
				NewClassHeals = v
			end,
			values = GetSpellsByCategory,
			disabled = function() return NewSpellType == 2 end
		},
		separator2 = {type = "header", order = 54, name = ""},
		createOutgoingStatus = {
			type = "execute",
			order = 55,
			width = "half",
			name = L["Create"],
			func = function()
				local sPrefix = NewSpellType ~= 2 and "aoe-" or "spells-"
				local sType = NewSpellType ~= 2 and "aoe-heals" or "inc-spells"
				local sEvents = NewSpellType == 2 and Grid2.CopyTable(dmgEvents) or nil
				local baseKey = sPrefix .. NewStatusName
				if not Grid2:DbGetValue("statuses", baseKey) then
					local dbx = {type = sType, spellList = {}, activeTime = 2, color1 = {r = 0, g = 0.8, b = 1, a = 1}, events = sEvents}
					SetSpellsByCategory(NewSpellType ~= 2 and NewClassHeals, dbx.spellList)
					Grid2:DbSetValue("statuses", baseKey, dbx)
					local status = Grid2.setupFunc[dbx.type](baseKey, dbx)
					Grid2Options:MakeStatusOptions(status)
					Grid2Options:SelectGroup("statuses", Grid2Options:GetStatusCategory(status), status.name)
				end
				NewStatusName, NewSpellType, NewClassHeals = nil, nil, nil
			end,
			disabled = function() return NewStatusName == nil or NewStatusName == "" end
		}
	}
end

Grid2Options:RegisterStatusCategory("incoming-spells", {
	name = L["AOE & Dmg"],
	title = L["New AOE/DMG tracker"],
	desc = L["Incoming heal or damage spells"],
	icon = "Interface\\Icons\\Spell_holy_holynova",
	options = MakeCategoryOptions()
})

Grid2Options:RegisterStatusOptions("aoe-heals", "incoming-spells", MakeStatusOutgoingOptions, {
	title = L["Incoming AOE Heals"],
	titleIcon = "Interface\\Icons\\Spell_holy_holybolt",
	groupOrder = 50
})
Grid2Options:RegisterStatusOptions("inc-spells", "incoming-spells", MakeStatusOutgoingOptions, {
	title = L["Incoming Spells"],
	titleIcon = "Interface\\Icons\\inv_wand_01",
	groupOrder = 51
})
