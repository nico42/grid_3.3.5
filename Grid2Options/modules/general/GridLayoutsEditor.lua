--[[ Layouts Editor ]]--
local Grid2 = Grid2
local Grid2Options = Grid2Options

local L = Grid2Options.L
local LG = Grid2Options.LG

local Grid2Layout = Grid2:GetModule("Grid2Layout")

local DEFAULT_GROUP_ORDER = "WARRIOR,DEATHKNIGHT,ROGUE,PALADIN,DRUID,SHAMAN,PRIEST,MAGE,WARLOCK,HUNTER"
local DEFAULT_PET_ORDER = "HUNTER,WARLOCK,DEATHKNIGHT,PRIEST,MAGE,DRUID,SHAMAN,WARRIOR,ROGUE,PALADIN"

local TYPE_VALUES = {
	party = L["party"],
	raid = L["raid"],
	partypet = L["partypet"],
	raidpet = L["raidpet"]
}
local COLUMN_VALUES = {
	["1"] = "1",
	["2"] = "2",
	["3"] = "3",
	["4"] = "4",
	["5"] = "5",
	["6"] = "6",
	["7"] = "7",
	["8"] = "8"
}
local UPC_VALUES = {
	["all"] = L["all"],
	["01"] = "01",
	["02"] = "02",
	["03"] = "03",
	["04"] = "04",
	["05"] = "05",
	["10"] = "10",
	["15"] = "15",
	["20"] = "20",
	["25"] = "25"
}
local GROUP_VALUES = {
	["1"] = "1",
	["2"] = "2",
	["3"] = "3",
	["4"] = "4",
	["5"] = "5",
	["6"] = "6",
	["7"] = "7",
	["8"] = "8",
	["all"] = L["all"]
}
local GROUPBY_VALUES = {
	["CLASS"] = L["Class"],
	["GROUP"] = L["Group"],
	["ROLE"] = L["Role"],
	["NONE"] = L["None"]
}
local SORTBY_VALUES = {
	["NAME"] = L["Name"],
	["INDEX"] = L["Index"],
	["ROLE"] = L["Role"]
}
local ORIENTATION_VALUES = {
	[""] = L["Default"],
	["horizontal"] = L["Horizontal"],
	["vertical"] = L["Vertical"]
}
local GROUP_ANCHOR_VALUES = {
	[""] = L["Default"],
	["TOPLEFT"] = L["TOPLEFT"],
	["TOPRIGHT"] = L["TOPRIGHT"],
	["BOTTOMLEFT"] = L["BOTTOMLEFT"],
	["BOTTOMRIGHT"] = L["BOTTOMRIGHT"]
}
local CENTER_GROWTH_VALUES = {
	[""] = "Off",
	["horizontal"] = "Horizontal (left-right from center)",
	["vertical"] = "Vertical (up-down from center)"
}

local ACTION1_VALUES = {
	add = string.format("|T%s:0|t%s", READY_CHECK_READY_TEXTURE, L["Insert"]),
	copy = string.format("|T%s:0|t%s", READY_CHECK_READY_TEXTURE, L["Copy"]),
	del = string.format("|T%s:0|t%s", READY_CHECK_NOT_READY_TEXTURE, L["Delete"])
}
local ACTION2_VALUES = {
	add = string.format("|T%s:0|t%s", READY_CHECK_READY_TEXTURE, L["Insert"]),
	copy = string.format("|T%s:0|t%s", READY_CHECK_READY_TEXTURE, L["Copy"])
}

local ANCHOR_POINT_VALUES = {
	TOPLEFT     = "TOPLEFT",
	TOP         = "TOP",
	TOPRIGHT    = "TOPRIGHT",
	LEFT        = "LEFT",
	CENTER      = "CENTER",
	RIGHT       = "RIGHT",
	BOTTOMLEFT  = "BOTTOMLEFT",
	BOTTOM      = "BOTTOM",
	BOTTOMRIGHT = "BOTTOMRIGHT"
}

-- Every OTHER header in the same layout, for the "Anchor to" dropdown.
local function GetAnchorHeaderValues(layout, selfIndex)
	local values = {}
	values[-1] = "Screen (absolute, never moves)"
	values[-2] = "Whole Frame (follows window size)"
	for i = 1, #layout do
		if i ~= selfIndex then
			values[i] = string.format("%s %d", L["Header"], i)
		end
	end
	return values
end

local options
local layoutName
local LoadLayout

local function GetAvailableLayouts(info)
	local result = {}
	local layouts = Grid2Layout.layoutSettings
	local custom = Grid2Layout.db.global.customLayouts or {}
	for name in pairs(layouts) do
		result[name] = custom[name] and LG[name] .. " *" or LG[name]
	end
	return result
end

local function GetCustomLayout(name)
	if name then
		local layouts = Grid2Layout.db.global.customLayouts
		return layouts and layouts[name]
	end
end

local function GetHeaderOption(layout, header, option, default)
	return header[option] or (layout.defaults and layout.defaults[option]) or default
end

local function CreateNewGroupHeader(copyFrom)
	if copyFrom then
		local header = {}
		for k, v in pairs(copyFrom) do
			header[k] = v
		end
		return header
	else
		return {type = "raid", sortMethod = "INDEX", unitsPerColumn = 5, maxColumns = 1}
	end
end

local function LoadLayoutHeader(layoutName, layout, index, header)
	local order = index * 20
	local args = options.groups.args
	local disabled = not GetCustomLayout(layoutName)

	args["header" .. index] = {
		type = "header",
		order = order,
		name = string.format("%s %d", L["Header"], index)
	}
	args["type" .. index] = {
		type = "select",
		order = order + 5,
		width = "half",
		name = L["Type"],
		desc = L["Type of units to display"],
		get = function()
			return header.type or "raid"
		end,
		set = function(_, v)
			header.type = v
		end,
		values = TYPE_VALUES,
		disabled = disabled
	}
	args["columns" .. index] = {
		type = "select",
		order = order + 6,
		width = "half",
		name = L["Columns"],
		desc = L["Maximum number of columns to display"],
		get = function()
			return tostring(GetHeaderOption(layout, header, "maxColumns", 1))
		end,
		set = function(_, v)
			header.maxColumns = tonumber(v)
		end,
		values = COLUMN_VALUES,
		disabled = disabled
	}
	args["upc" .. index] = {
		type = "select",
		order = order + 7,
		width = "half",
		name = L["Units/Column"],
		desc = L["Maximum number of units per column to display"],
		get = function()
			local v = tostring(GetHeaderOption(layout, header, "unitsPerColumn", "all"))
			return strlen(v) > 1 and v or "0" .. v
		end,
		set = function(_, v)
			header.unitsPerColumn = tonumber(v)
		end,
		values = UPC_VALUES,
		disabled = disabled
	}
	args["group1" .. index] = {
		type = "select",
		order = order + 8,
		width = "half",
		name = L["First group"],
		desc = L["First group to display"],
		get = function()
			return header.groupFilter and strsub(header.groupFilter, 1, 1) or "all"
		end,
		set = function(_, v)
			v = tonumber(v)
			if v then
				local w = tonumber(header.groupFilter and strsub(header.groupFilter, -1)) or v
				local t = {}
				for i = v, math.max(v, w) do
					t[#t + 1] = tostring(i)
				end
				header.groupFilter = table.concat(t, ",")
			else
				header.groupFilter = nil
			end
		end,
		values = GROUP_VALUES,
		disabled = disabled
	}
	args["group2" .. index] = {
		type = "select",
		order = order + 9,
		width = "half",
		name = L["Last Group"],
		desc = L["Last group to display"],
		get = function()
			return header.groupFilter and strsub(header.groupFilter, -1) or "all"
		end,
		set = function(_, v)
			v = tonumber(v)
			if v then
				local w = tonumber(header.groupFilter and strsub(header.groupFilter, 1, 1)) or v
				local t = {}
				for i = w, math.max(v, w) do
					t[#t + 1] = tostring(i)
				end
				header.groupFilter = table.concat(t, ",")
			else
				header.groupFilter = nil
			end
		end,
		values = GROUP_VALUES,
		disabled = disabled
	}
	args["groupby" .. index] = {
		type = "select",
		order = order + 10,
		width = "half",
		name = L["Group by"],
		desc = L["Group by"],
		get = function()
			return GetHeaderOption(layout, header, "groupBy", "NONE")
		end,
		set = function(_, v)
			if v == "CLASS" then
				header.groupingOrder =
					(header.type == "raid" or header.type == "party") and DEFAULT_GROUP_ORDER or DEFAULT_PET_ORDER
			elseif v == "GROUP" then
				header.groupingOrder = header.groupFilter or "1,2,3,4,5,6,7,8"
			elseif v == "ROLE" then
				header.groupingOrder = "MAINTANK,MAINASSIST"
			else
				header.groupingOrder, v = nil, nil
			end
			header.groupBy = v
		end,
		values = GROUPBY_VALUES,
		disabled = disabled
	}
	args["orientation" .. index] = {
		type = "select",
		order = order + 10.5,
		width = "half",
		name = L["Orientation"],
		desc = L["Override the general Horizontal/Vertical groups setting for this header only. Leave on 'Default' to use the global setting."],
		get = function()
			return header.orientationOverride or ""
		end,
		set = function(_, v)
			header.orientationOverride = (v ~= "" and v) or nil
		end,
		values = ORIENTATION_VALUES,
		disabled = disabled
	}
	args["groupanchoroverride" .. index] = {
		type = "select",
		order = order + 10.6,
		width = "half",
		name = L["Group Anchor"],
		desc = L["Override the general Group Anchor setting for this header only (controls which corner new columns wrap towards). Leave on 'Default' to use the global setting."],
		get = function()
			return header.groupAnchorOverride or ""
		end,
		set = function(_, v)
			header.groupAnchorOverride = (v ~= "" and v) or nil
		end,
		values = GROUP_ANCHOR_VALUES,
		disabled = disabled
	}
	args["centergrowth" .. index] = {
		type = "select",
		order = order + 10.7,
		width = "full",
		name = "Center Growth",
		desc = "Instead of growing members in one direction from a starting corner, centers them symmetrically around the header's own center point. Overrides the normal growth direction entirely while enabled.",
		get = function()
			return header.centerGrowth or ""
		end,
		set = function(_, v)
			header.centerGrowth = (v ~= "" and v) or nil
		end,
		values = CENTER_GROWTH_VALUES,
		disabled = disabled
	}
	args["sortby" .. index] = {
		type = "select",
		order = order + 10,
		width = "half",
		name = L["Sort by"],
		desc = L["Sort by"] .. "\n" .. L["'Role' sorts group members Tank -> Damage -> Unknown -> Healer, instead of alphabetically or by raid index."],
		get = function()
			if header.roleSort then
				return "ROLE"
			end
			return GetHeaderOption(layout, header, "sortMethod", "INDEX")
		end,
		set = function(_, v)
			if v == "ROLE" then
				header.roleSort = true
				header.sortMethod = "NAMELIST"
				header.nameList = header.nameList or ""
			else
				header.roleSort = nil
				header.sortMethod = v
			end
		end,
		values = SORTBY_VALUES,
		disabled = disabled
	}
	args["customsizeheader" .. index] = {
		type = "toggle",
		order = order + 13,
		name = L["Custom size"],
		desc = L["Override this header's frame size instead of using the global frame size. Useful for making raid pets (or any other header) smaller/larger than the rest."],
		get = function()
			return header.widthPct ~= nil or header.heightPct ~= nil
		end,
		set = function(_, v)
			if v then
				header.widthPct = header.widthPct or 1
				header.heightPct = header.heightPct or 1
			else
				header.widthPct = nil
				header.heightPct = nil
			end
		end,
		disabled = disabled
	}
	args["customwidth" .. index] = {
		type = "range",
		order = order + 13.1,
		width = "half",
		name = L["Width %"],
		min = 0.1,
		max = 3,
		step = 0.01,
		isPercent = true,
		get = function()
			return header.widthPct or 1
		end,
		set = function(_, v)
			header.widthPct = v
		end,
		disabled = function()
			return disabled or header.widthPct == nil
		end
	}
	args["customheight" .. index] = {
		type = "range",
		order = order + 13.2,
		width = "half",
		name = L["Height %"],
		min = 0.1,
		max = 3,
		step = 0.01,
		isPercent = true,
		get = function()
			return header.heightPct or 1
		end,
		set = function(_, v)
			header.heightPct = v
		end,
		disabled = function()
			return disabled or header.heightPct == nil
		end
	}
	args["customposheader" .. index] = {
		type = "toggle",
		order = order + 14,
		name = L["Custom position"],
		desc = L["Anchor this header relative to another header in this layout, instead of the automatic flow. Useful for e.g. placing raid pets in their own row below the rest."],
		get = function()
			return header.customAnchor ~= nil
		end,
		set = function(_, v)
			if v then
				header.customAnchor = header.customAnchor or {
					relativeToIndex = (index > 1 and index - 1) or (#layout > 1 and index + 1) or nil,
					point = "TOPLEFT",
					relativePoint = "BOTTOMLEFT",
					xOffset = 0,
					yOffset = 0
				}
			else
				header.customAnchor = nil
			end
		end,
		disabled = disabled
	}
	args["anchorto" .. index] = {
		type = "multiselect",
		order = order + 14.1,
		width = "full",
		name = L["Anchor to"],
		desc = L["Which other header(s) to anchor this one to. Select more than one to anchor to whichever of them is currently the widest - useful e.g. for a pet row that should line up with whichever player group is widest."],
		get = function(_, key)
			local rel = header.customAnchor and header.customAnchor.relativeToIndex
			if type(rel) == "table" then
				return rel[key] == true
			end
			return rel == key
		end,
		set = function(_, key, val)
			local a = header.customAnchor
			if not a then
				return
			end
			local rel = a.relativeToIndex
			local relTable
			if type(rel) == "table" then
				relTable = rel
			else
				relTable = {}
				if rel then
					relTable[rel] = true
				end
			end
			relTable[key] = val or nil
			a.relativeToIndex = relTable
		end,
		values = function()
			return GetAnchorHeaderValues(layout, index)
		end,
		disabled = function()
			return disabled or header.customAnchor == nil
		end
	}
	args["anchorpoint" .. index] = {
		type = "select",
		order = order + 14.2,
		width = "double",
		name = L["My Point"],
		desc = L["The point on THIS header that gets anchored."],
		get = function()
			return header.customAnchor and header.customAnchor.point or "TOPLEFT"
		end,
		set = function(_, v)
			header.customAnchor.point = v
		end,
		values = ANCHOR_POINT_VALUES,
		disabled = function()
			return disabled or header.customAnchor == nil
		end
	}
	args["relativepoint" .. index] = {
		type = "select",
		order = order + 14.3,
		width = "double",
		name = L["Relative Point"],
		desc = L["The point on the OTHER header this one anchors to."],
		get = function()
			return header.customAnchor and header.customAnchor.relativePoint or "BOTTOMLEFT"
		end,
		set = function(_, v)
			header.customAnchor.relativePoint = v
		end,
		values = ANCHOR_POINT_VALUES,
		disabled = function()
			return disabled or header.customAnchor == nil
		end
	}
	args["xoffset" .. index] = {
		type = "range",
		order = order + 14.4,
		width = "half",
		name = L["X Offset"],
		min = -200,
		max = 200,
		step = 1,
		get = function()
			return header.customAnchor and header.customAnchor.xOffset or 0
		end,
		set = function(_, v)
			header.customAnchor.xOffset = v
		end,
		disabled = function()
			return disabled or header.customAnchor == nil
		end
	}
	args["yoffset" .. index] = {
		type = "range",
		order = order + 14.5,
		width = "half",
		name = L["Y Offset"],
		min = -200,
		max = 200,
		step = 1,
		get = function()
			return header.customAnchor and header.customAnchor.yOffset or 0
		end,
		set = function(_, v)
			header.customAnchor.yOffset = v
		end,
		disabled = function()
			return disabled or header.customAnchor == nil
		end
	}
	if not disabled then
		args["action" .. index] = {
			type = "select",
			order = order + 12,
			width = "half",
			name = string.format("|cFF00ff00%s|r", L["Action"]),
			get = function()
			end,
			set = function(_, v)
				if v == "del" then
					if #layout > 1 then
						table.remove(layout, index)
						LoadLayout(layoutName)
					end
				else
					table.insert(layout, index + 1, CreateNewGroupHeader(v == "copy" and layout[index]))
					LoadLayout(layoutName)
				end
			end,
			values = #layout > 1 and ACTION1_VALUES or ACTION2_VALUES
		}
	end
end

local function LoadLayoutGeneralOptions(name)
	local args = options.groups.args
	local layout = Grid2Layout.layoutSettings[name]
	local isCustom = GetCustomLayout(name)
	args.separator1 = {
		type = "header",
		order = 1,
		name = L["General"]
	}
	args.scale = {
		type = "range",
		name = L["Scale"],
		desc = L["Adjust Grid scale."],
		order = 2,
		softMin = 0.5,
		softMax = 2.0,
		step = 0.05,
		isPercent = true,
		get = function()
			return Grid2Layout.db.profile.layoutScales[name] or 1
		end,
		set = function(_, v)
			Grid2Layout.db.profile.layoutScales[name] = (v ~= 1) and v or nil
			Grid2Layout:Scale()
		end
	}
	if isCustom then
		args.vehicle = {
			type = "toggle",
			name = L["Toggle for vehicle"],
			desc = L["When the player is in a vehicle replace the player frame with the vehicle frame."],
			order = 3,
			get = function()
				return layout.defaults.toggleForVehicle
			end,
			set = function()
				layout.defaults.toggleForVehicle = not layout.defaults.toggleForVehicle
			end
		}
	end
end

LoadLayout = function(name)
	wipe(options.groups.args)
	local layout = name and Grid2Layout.layoutSettings[name]
	if layout then
		LoadLayoutGeneralOptions(name)
		for i, h in ipairs(layout) do
			LoadLayoutHeader(name, layout, i, h)
		end
		return name
	end
end

local function CreateLayout(name)
	if Grid2Layout.layoutSettings[name] then
		return
	end
	local layouts = Grid2Layout.db.global.customLayouts
	if not layouts then
		layouts = {}
		Grid2Layout.db.global.customLayouts = layouts
	end
	layouts[name] = {
		meta = {raid40 = true, raid25 = true, raid20 = true, raid15 = true, raid10 = true, party = true, pvp = true, arena = true, solo = true},
		defaults = {toggleForVehicle = true, showPlayer = true, showParty = true, showRaid = true, showSolo = true},
		[1] = CreateNewGroupHeader()
	}
	Grid2Layout:AddLayout(name, layouts[name])
	options.selectLayout.values = GetAvailableLayouts()
	return LoadLayout(name)
end

function Grid2Options:RefreshCustomLayoutsOptions()
	layoutName = nil
	options.selectLayout.values = GetAvailableLayouts()
	LoadLayout(nil)
end

function Grid2Options:MakeLayoutsEditorOptions()
	layoutName = nil
	options = {
		selectLayout = {
			type = "select",
			order = 1,
			name = L["Select Layout"],
			desc = L["Select Layout"],
			values = GetAvailableLayouts,
			get = function()
				return layoutName
			end,
			set = function(_, v)
				layoutName = LoadLayout(v)
			end
		},
		newLayout = {
			type = "input",
			order = 2,
			name = L["New Layout Name"],
			desc = L["New Layout Name"],
			get = function()
			end,
			set = function(_, v)
				layoutName = CreateLayout(v)
			end
		},
		delete = {
			type = "execute",
			width = "half",
			order = 3,
			name = L["Delete"],
			desc = L["Delete selected layout"],
			func = function(info)
				Grid2Layout.db.global.customLayouts[layoutName] = nil
				Grid2Layout.layoutSettings[layoutName] = nil
				LoadLayout(nil)
				options.selectLayout.values = GetAvailableLayouts()
			end,
			hidden = function()
				return not GetCustomLayout(layoutName)
			end
		},
		refresh = {
			type = "execute",
			width = "half",
			order = 4,
			name = L["Refresh"],
			desc = L["Refresh the Layout"],
			func = function(info)
				if Grid2Layout.layoutName == layoutName then
					Grid2Layout:LoadLayout(layoutName)
				end
			end,
			hidden = function()
				return Grid2Layout.layoutName ~= layoutName or InCombatLockdown()
			end
		},
		groups = {
			type = "group",
			inline = true,
			name = "",
			order = 5,
			args = {}
		}
	}
	return options
end