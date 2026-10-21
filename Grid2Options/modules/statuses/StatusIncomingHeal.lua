--[[
	StatusIncomingHeal.lua (Options)

	Options registration for the "incheal" status (see
	Grid2/modules/StatusIncomingHeal.lua). Two colors: the default color
	(color1) used whenever there's at least one pending heal, and the
	"mine lands first" color (color2) used when the player's own pending
	heal on that unit currently has the earliest expiration time.

	Deliberately uses plain literal strings instead of Grid2Options.L[...]
	for anything new here, to avoid depending on locale files this session
	doesn't have direct access to verify.
]]

local Grid2Options = Grid2Options

local function MakeIncomingHealOptions(self, status, options)
	options.desc = {
		type = "description",
		order = 1,
		name = "Shows how many heals are currently being cast on this unit (via LibHealComm-4.0, works group-wide for any healer running a compatible addon). HoTs are not counted, only direct/channeled casts."
	}
	options.color1 = {
		type = "color",
		order = 10,
		hasAlpha = true,
		name = "Default color",
		desc = "Color used when there is at least one pending heal.",
		get = function()
			local c = status.dbx.color1
			return c.r, c.g, c.b, c.a
		end,
		set = function(_, r, g, b, a)
			status.dbx.color1 = {r = r, g = g, b = b, a = a}
		end
	}
	options.color2 = {
		type = "color",
		order = 11,
		hasAlpha = true,
		name = "\"Mine lands first\" color",
		desc = "Color used when YOUR OWN pending heal on this unit currently has the earliest expiration time of all pending heals.",
		get = function()
			local c = status.dbx.color2
			return c.r, c.g, c.b, c.a
		end,
		set = function(_, r, g, b, a)
			status.dbx.color2 = {r = r, g = g, b = b, a = a}
		end
	}
end

Grid2Options:RegisterStatusCategory("incheal", {
	name = "Incoming Heal",
	title = "Incoming Heal Count",
	desc = "Shows a count of currently-casting heals targeting each unit, via LibHealComm-4.0.",
	icon = "Interface\\Icons\\Spell_holy_flashheal"
})

Grid2Options:RegisterStatusOptions("incheal", "incheal", MakeIncomingHealOptions, {
	title = "Incoming Heal Count"
})
