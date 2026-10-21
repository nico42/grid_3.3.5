local Grid2 = Grid2
local RangeAlt = Grid2.statusPrototype:new("rangealt")

local UnitIsUnit, UnitInRange = UnitIsUnit, UnitInRange
local UnitIsFriend, UnitIsDeadOrGhost = UnitIsFriend, UnitIsDeadOrGhost
local IsSpellInRange, IsItemInRange = IsSpellInRange, IsItemInRange
local CheckInteractDistance = CheckInteractDistance
local tostring = tostring

local cache = {}

local Ranges = {
	["10"] = function(unit)
		return CheckInteractDistance(unit, 3)
	end,
	["28"] = function(unit)
		return CheckInteractDistance(unit, 4)
	end,
	["30"] = function(unit)
		return IsItemInRange((UnitIsFriend(unit, "player") and 1180 or 835), unit) == 1
	end, --	1180 = Scroll of Stamina, 835 = Large Rope Net
	["38"] = UnitInRange,
	["40"] = function(unit)
		return IsItemInRange((UnitIsFriend(unit, "player") and 34471 or 28767), unit) == 1
	end, --	34471 = Vial of the Sunwell, 28767 = The Decapitator
	["60"] = function(unit)
		if IsItemInRange((UnitIsFriend(unit, "player") and 34471 or 28767), unit) ~= nil then
			if IsItemInRange((UnitIsFriend(unit, "player") and 34471 or 28767), unit) < 1 then
				return IsItemInRange((UnitIsFriend(unit, "player") and 32825 or 37887), unit) == 1
			end
		end
	end, --	32825 = Soul Cannon, 37887 = Seeds of Nature's Wrath
	["99"] = UnitIsVisible
}

local UnitRangeCheck
local UnitIsInRange

local _, myclass = UnitClass("player")
local rezSpell = ({DRUID = 20484, PRIEST = 2006, PALADIN = 7328, SHAMAN = 2008, DEATHKNIGHT = 61999, WARLOCK = 20707})[myclass]
if rezSpell then
	rezSpell = GetSpellInfo(rezSpell)
	UnitIsInRange = function(unit)
		local res = nil
		if UnitIsDeadOrGhost(unit) then
			res = UnitIsUnit(unit, "player") or IsSpellInRange(rezSpell, unit) == 1
		else
			res = UnitRangeCheck(unit)
		end
		Grid2:SendMessage("Grid_UnitInRange", unit, res)
		return res
	end
end

-- Roster ranges update function
local function Update(self)
	for unit in Grid2:IterateRosterUnits() do
		local value = UnitIsInRange(unit) and 1 or false
		if value ~= cache[unit] then
			cache[unit] = value
			RangeAlt:UpdateIndicators(unit)
		end
	end
	self:Play()
end

-- Range status
function RangeAlt:OnEnable()
	self:CreateTimer()
	self:UpdateDB()
	self:RegisterMessage("Grid_UnitUpdated")
	self:RegisterMessage("Grid_UnitLeft")
	self:RegisterMessage("Grid_GroupTypeChanged")
	self.timer:Play()
end

function RangeAlt:OnDisable()
	self:UnregisterMessage("Grid_UnitUpdated")
	self:UnregisterMessage("Grid_UnitLeft")
	self:UnregisterMessage("Grid_GroupTypeChanged")
	self.timer:Stop()
end

-- {{ Workaround for WoW 5.0.4 UnitInRange() bug (returns false for player&pet while solo)
local function UnitSoloInRange()
	return true
end

function RangeAlt:Grid_GroupTypeChanged(_, groupType)
	Ranges["38"] = groupType == "solo" and UnitSoloInRange or UnitInRange
	if (tostring(self.dbx.range) or "38") == "38" then
		self:UpdateDB()
	end
end
-- }}

function RangeAlt:Grid_UnitUpdated(_, unit)
	cache[unit] = UnitIsInRange(unit) and 1 or false
end

function RangeAlt:Grid_UnitLeft(_, unit)
	cache[unit] = nil
end

function RangeAlt:CreateTimer()
	local timer = CreateFrame("Frame", nil, Grid2LayoutFrame):CreateAnimationGroup()
	timer.animation = timer:CreateAnimation()
	timer.animation:SetOrder(1)
	timer:SetScript("OnFinished", Update)
	self.timer = timer
	self.CreateTimer = Grid2.Dummy
end

function RangeAlt:UpdateDB()
	UnitRangeCheck = Ranges[tostring(self.dbx.range) or "38"] or Ranges["38"]
	if not rezSpell then
		UnitIsInRange = UnitRangeCheck
	end
	self.defaultAlpha = self.dbx.default or 0.25
	if self.timer then
		self.timer.animation:SetDuration(self.dbx.elapsed or 0.25)
	end
end

function RangeAlt:GetPercent(unit)
	return cache[unit] or self.defaultAlpha
end

-- Only "active" (for icon/square/border-style indicators) when the unit is
-- actually in the configured range band AND alive. Dead units are always
-- excluded here, even for classes with a rez-range fallback (UnitIsInRange
-- above may report a dead unit as "in range" because they're in RESURRECT
-- range, which is a different thing entirely from "in range" for this
-- purpose) - GetPercent()/the bar use case is untouched and keeps its
-- original behavior for backwards compatibility.
function RangeAlt:IsActive(unit)
	return cache[unit] == 1 and not UnitIsDeadOrGhost(unit)
end

function RangeAlt:GetColor(unit)
	local c = self.dbx.color1
	return c.r, c.g, c.b, c.a
end

function RangeAlt:GetRanges()
	return Ranges
end

local function Create(baseKey, dbx)
	Grid2:RegisterStatus(RangeAlt, {"percent", "color"}, baseKey, dbx)
	return RangeAlt
end

Grid2.setupFunc["rangealt"] = Create
Grid2:DbSetStatusDefaultValue(
	"rangealt",
	{type = "rangealt", range = 38, default = 0.25, elapsed = 0.5, color1 = {r = 0, g = 1, b = 0, a = 1}}
)