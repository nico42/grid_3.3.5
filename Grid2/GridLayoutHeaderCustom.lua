--[[
	GridLayoutHeaderCustom.lua

	Generic per-header size, position, and orientation overrides for the
	Layout Editor (Grid2Options/modules/general/GridLayoutsEditor.lua ->
	"Custom size" / "Custom position" / "Orientation" fields). Works for ANY
	header in ANY layout (fixed or custom), not just raid pets - but the
	main use case is exactly that: making a raidpet/partypet header smaller,
	positioned, and oriented differently than the player group headers.

	Three independent, opt-in pieces of metadata read from a header's static
	definition (the same tables used by Grid2Layout:AddLayout / the Layout
	Editor):

		widthPct / heightPct (numbers, e.g. 0.5 = 50%)
			Resizes that header's unit buttons relative to the normal
			global frame size (Grid2Frame's frameWidth/frameHeight),
			instead of using the global size like every other header.
			This re-runs each button's own :Layout() method (temporarily
			swapping in the custom size) instead of just SetWidth/SetHeight,
			so the background texture, indicators, borders etc. all resize
			together instead of just the outer frame boundary.

		customAnchor = {
			relativeToIndex = N,  -- OR a table like {1, 3} / {[1]=true,[3]=true}
			                      -- 1-based index(es) of other header(s) in
			                      -- the SAME layout to anchor to. If more
			                      -- than one index is given, this header
			                      -- anchors to whichever of them is
			                      -- currently the WIDEST (re-evaluated every
			                      -- refresh) - matches the fixed "Sorted by
			                      -- Role" pet-row layouts' own behavior,
			                      -- so a pet row lines up with whichever
			                      -- player group actually takes up the most
			                      -- space instead of a single fixed one.
			point = "TOPLEFT",       -- point on THIS header
			relativePoint = "BOTTOMLEFT", -- point on the OTHER header
			xOffset = 0, yOffset = 0,
		}
			Re-anchors that header's frame relative to another header (or
			the widest of several) in the same layout, instead of
			Grid2Layout's automatic left-to-right/top-to-bottom chain
			(which is driven by the profile's global horizontal/groupAnchor
			settings and applies the same direction to every header).

		orientationOverride = "horizontal" | "vertical" | nil
			Overrides which direction THIS header's own members grow in
			(independent of the profile-wide Horizontal/Vertical groups
			setting, which normally applies to every header the same way).

	This intentionally does NOT touch the 4 fixed "Sorted by Role" layouts'
	own bespoke pet-row logic in GridLayoutRoleSort.lua (which additionally
	forces unitsPerColumn/maxColumns for a strict single row) - that's more
	specific behavior than what this generic mechanism provides. This file
	is for the Layout Editor.
]]

local Grid2Layout = Grid2Layout
local Grid2Frame = Grid2:GetModule("Grid2Frame", true)

local InCombatLockdown = InCombatLockdown

-- Maps a layout's array index -> live header frame, using the exact same
-- per-type index counting Grid2Layout:LoadLayout uses internally, so this
-- correctly matches even when a layout mixes "raid"/"party"/"raidpet"/
-- "partypet" headers in any order.
local function GetHeaderIndexMap(layout)
	local default_type = (layout.defaults and layout.defaults.type) or "raid"
	local typeIndex = {}
	local map = {}
	for i = 1, #layout do
		local h = layout[i]
		local htype = h.type or default_type
		typeIndex[htype] = (typeIndex[htype] or 0) + 1
		local pool = Grid2Layout.groups[htype]
		map[i] = pool and pool[typeIndex[htype]]
	end
	return map
end

--{{{ Custom size

-- Headers we've applied a custom size to during the current layout, so the
-- Grid2Frame:LayoutFrames hook and the roster-update event handler below
-- know what to keep re-applying (new buttons can be created at any time as
-- the roster changes, and Grid2 resets every frame's size back to global
-- defaults whenever frame settings - color/texture/border/... - change).
local sizedHeaders = {}
local activeCenterGrowthHeaders = {} -- set by RefreshCustomHeaders; unused elsewhere for now, kept for potential future hooks

-- Re-sizing a button correctly needs more than SetWidth/SetHeight: the
-- background texture ("container") and every indicator's position/size are
-- computed by the button's own :Layout() method, which unconditionally
-- reads the GLOBAL frame size from Grid2Frame.db.profile. So the trick is
-- to briefly swap in our custom size, let :Layout() do its normal (correct)
-- work with it, then restore the real global size - this is synchronous
-- Lua, nothing else can run in between.
local function ApplyCustomSize(header, h)
	if not Grid2Frame or InCombatLockdown() then
		return
	end
	if not (h.widthPct or h.heightPct) then
		return
	end
	local profile = Grid2Frame.db.profile
	local baseW, baseH = profile.frameWidth, profile.frameHeight
	local w = h.widthPct and (baseW * h.widthPct) or baseW
	local hh = h.heightPct and (baseH * h.heightPct) or baseH

	profile.frameWidth, profile.frameHeight = w, hh
	local i = 1
	local button = header:GetAttribute("child" .. i)
	while button do
		if button.Layout then
			button:Layout()
		end
		i = i + 1
		button = header:GetAttribute("child" .. i)
	end
	profile.frameWidth, profile.frameHeight = baseW, baseH
end

--}}}

-- Resolves a customAnchor's target header frame. `relativeToIndex` is
-- either a single 1-based index, or a table of indices (array-style {1,3}
-- or set-style {[1]=true,[3]=true}, both work) - in the multi-index case,
-- whichever of those headers is currently the WIDEST wins.
-- Scans every candidate in `rel` (a single index, or a table of indices -
-- array-style {1,3} or set-style {[1]=true,[3]=true}, both work) and
-- returns BOTH the widest one AND the lowest-on-screen one (smallest
-- GetBottom()) in a single pass, for the "besideWidest" anchor mode below.
local function GetWidestAndLowest(rel, map)
	local widest, widestWidth
	local lowest, lowestBottom
	local function Consider(idx)
		local g = idx and map[idx]
		if not g then
			return
		end
		local w = g:GetWidth()
		if not widestWidth or w > widestWidth then
			widest, widestWidth = g, w
		end
		local b = g:GetBottom()
		if b and (not lowestBottom or b < lowestBottom - 0.5) then
			lowest, lowestBottom = g, b
		end
	end
	if type(rel) == "table" then
		for key, value in pairs(rel) do
			Consider((value == true) and key or value)
		end
	else
		Consider(rel)
	end
	return widest, lowest
end

-- Resolves one candidate index to a live frame. Two special NEGATIVE
-- numeric sentinels are supported alongside the (1-based, positive)
-- numbered headers - kept as numbers rather than strings like "frame"/
-- "screen" specifically so the "Anchor to" multiselect's values table never
-- mixes key types (AceConfigDialog sorts/compares those keys internally,
-- and comparing a string key against a number key throws "attempt to
-- compare string with number"):
--   -2 - the whole Grid2Layout window ("frame"). Fixed relative to the
--        window itself, but the window's own size (and therefore this
--        anchor's absolute screen position) still follows the CURRENTLY
--        visible content - e.g. if the whole raid shrinks, the window
--        shrinks too, and anything anchored to this moves along with it.
--   -1 - UIParent ("screen"), i.e. the screen itself. A truly fixed screen
--        position that NEVER moves, regardless of how the window or any
--        header resizes (raid size changes, groups gaining/losing members,
--        pets appearing, ...). The X/Y offsets you set are then absolute
--        screen coordinates from whichever point you anchor from, rather
--        than relative to the window.
local function ResolveAnchorCandidate(idx, map)
	if idx == -2 then
		return Grid2Layout.frame
	end
	if idx == -1 then
		return UIParent
	end
	return map[idx]
end

local function GetCustomAnchorTarget(a, map)
	local rel = a.relativeToIndex
	if type(rel) == "table" then
		local widest, widestWidth
		for key, value in pairs(rel) do
			local idx = (value == true) and key or value
			local candidate = idx and ResolveAnchorCandidate(idx, map)
			if candidate then
				local w = candidate:GetWidth()
				if not widestWidth or w > widestWidth then
					widest, widestWidth = candidate, w
				end
			end
		end
		return widest
	end
	return ResolveAnchorCandidate(rel, map)
end

-- "besideWidest" mode: X position flush against the right edge of whichever
-- candidate header is WIDEST, Y position level with the TOP of whichever
-- candidate header is LOWEST on screen (smallest GetBottom()). These can be
-- two DIFFERENT headers - a single point/relativePoint anchor to one frame
-- can't express that (it always takes both X and Y from the same frame),
-- so this computes an absolute screen position (relative to UIParent's
-- bottom-left corner, which is what GetLeft/Right/Top/Bottom are already
-- measured from) instead of anchoring to either candidate directly.
local function ApplyCustomAnchorBesideWidest(header, a, map)
	local widest, lowest = GetWidestAndLowest(a.relativeToIndex, map)
	if not widest then
		return
	end
	lowest = lowest or widest
	local right = widest:GetRight()
	local top = lowest:GetTop()
	if not right or not top then
		return
	end
	header:ClearAllPoints()
	header:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right + (a.xOffset or 0), top + (a.yOffset or 0))
end

local function ApplyCustomAnchor(header, h, map)
	local a = h.customAnchor
	if not a then
		return
	end
	if a.besideWidest then
		ApplyCustomAnchorBesideWidest(header, a, map)
		return
	end
	local relHeader = GetCustomAnchorTarget(a, map)
	if not relHeader or relHeader == header then
		return
	end
	header:ClearAllPoints()
	header:SetPoint(a.point or "TOPLEFT", relHeader, a.relativePoint or "BOTTOMLEFT", a.xOffset or 0, a.yOffset or 0)
end

--{{{ Custom orientation / column-wrap direction

-- Mirrors Grid2Layout's own (private) anchor-point table, used internally
-- by GridLayoutHeaderClass.prototype:SetOrientation() (member growth
-- direction) and by GridLayout.lua's SetAllAttributes() (columnAnchorPoint,
-- i.e. which direction NEW COLUMNS wrap towards). Duplicated here since
-- that table isn't exposed outside GridLayout.lua.
local ORIENTATION_ANCHOR_POINTS = {
	[false] = {TOPLEFT = "TOP", TOPRIGHT = "TOP", BOTTOMLEFT = "BOTTOM", BOTTOMRIGHT = "BOTTOM"},
	[true] = {TOPLEFT = "LEFT", TOPRIGHT = "RIGHT", BOTTOMLEFT = "LEFT", BOTTOMRIGHT = "RIGHT"},
	TOP = -1,
	BOTTOM = 1,
	LEFT = 1,
	RIGHT = -1
}

-- Grid2 normally sets BOTH "point" (member growth direction) AND
-- "columnAnchorPoint" (column-wrap direction) from the SAME global
-- horizontal/groupAnchor settings, in lockstep (columnAnchorPoint always
-- uses the OPPOSITE direction table from "point", since columns need to
-- stack perpendicular to how members grow within a column). Overriding
-- only "point" and leaving "columnAnchorPoint" on its global value breaks
-- multi-column wrapping the moment the two disagree - so both are always
-- recomputed together here, from the same effective horizontal/groupAnchor
-- values (per-header override if set, global setting otherwise).
local function ApplyCustomOrientation(header, h)
	if not h.orientationOverride and not h.groupAnchorOverride then
		return
	end
	local p = Grid2Layout.db.profile
	local horizontal
	if h.orientationOverride then
		horizontal = h.orientationOverride == "horizontal"
	else
		horizontal = p.horizontal
	end
	local groupAnchor = h.groupAnchorOverride or p.groupAnchor

	local point = ORIENTATION_ANCHOR_POINTS[horizontal][groupAnchor]
	local direction = ORIENTATION_ANCHOR_POINTS[point]
	local padding = p.Padding or 0
	header:SetLayoutAttribute("xOffset", horizontal and padding * direction or 0)
	header:SetLayoutAttribute("yOffset", (not horizontal) and padding * direction or 0)
	header:SetLayoutAttribute("point", point)

	-- only meaningful when unitsPerColumn actually wraps into >1 column,
	-- but harmless to always keep in sync
	header:SetLayoutAttribute("columnAnchorPoint", ORIENTATION_ANCHOR_POINTS[not horizontal][groupAnchor])
end

--}}}

--{{{ Center growth: members grow symmetrically outward from the header's
-- own center, instead of Blizzard's normal "grow in one direction from a
-- starting corner" model. There is no native support for this in
-- SecureGroupHeaderTemplate at all - the header still creates/manages the
-- child unit buttons as usual (membership, visibility, unit assignment),
-- but we take over their on-screen POSITION entirely, recalculating it
-- from scratch every time the visible member count changes.

local function ApplyCenterGrowth(header, h)
	if not h.centerGrowth then
		return
	end
	local horizontal = h.centerGrowth == "horizontal"

	local unitW, unitH
	if Grid2Frame then
		unitW, unitH = Grid2Frame:GetFrameSize()
	end
	unitW, unitH = unitW or 48, unitH or 48
	if h.widthPct then
		unitW = unitW * h.widthPct
	end
	if h.heightPct then
		unitH = unitH * h.heightPct
	end
	local unitSize = horizontal and unitW or unitH
	local spacing = (Grid2Layout.db.profile.Padding or 0)

	local children = {}
	local i = 1
	local child = header:GetAttribute("child" .. i)
	while child do
		if child:IsShown() then
			children[#children + 1] = child
		end
		i = i + 1
		child = header:GetAttribute("child" .. i)
	end

	local n = #children
	if n == 0 then
		return
	end

	for idx = 1, n do
		local c = children[idx]
		-- centers the WHOLE row/column on the header's own center: with n
		-- members, offsets run symmetrically from -(n-1)/2 to +(n-1)/2
		-- steps of (unitSize+spacing), so an odd count has one member
		-- exactly centered and an even count straddles the center evenly
		local offset = (idx - (n + 1) / 2) * (unitSize + spacing)
		c:ClearAllPoints()
		if horizontal then
			c:SetPoint("CENTER", header, "CENTER", offset, 0)
		else
			c:SetPoint("CENTER", header, "CENTER", 0, -offset)
		end
	end
end

--}}}

local function RefreshCustomHeaders()
	local layout = Grid2Layout.layoutSettings[Grid2Layout.layoutName]
	for header in pairs(sizedHeaders) do
		sizedHeaders[header] = nil
	end
	if not layout then
		return
	end

	local map
	local centerGrowthHeaders = {}
	for i = 1, #layout do
		local h = layout[i]
		if h.widthPct or h.heightPct or h.customAnchor or h.orientationOverride or h.groupAnchorOverride or h.centerGrowth then
			map = map or GetHeaderIndexMap(layout)
			local header = map[i]
			if header then
				if h.widthPct or h.heightPct then
					ApplyCustomSize(header, h)
					sizedHeaders[header] = h
				end
				if h.customAnchor then
					ApplyCustomAnchor(header, h, map)
				end
				if h.orientationOverride or h.groupAnchorOverride then
					ApplyCustomOrientation(header, h)
				end
				if h.centerGrowth then
					ApplyCenterGrowth(header, h)
					centerGrowthHeaders[header] = h
				end
			end
		end
	end
	activeCenterGrowthHeaders = centerGrowthHeaders
end

--{{{ Overall frame size correction

-- Grid2Layout:UpdateSize() (called automatically after every LoadLayout)
-- computes the whole addon window's size by simply ADDING UP every header's
-- width/height, assuming they all sit in one simple horizontal-or-vertical
-- chain. A header we've repositioned with customAnchor (e.g. a pet row
-- placed BELOW the widest group instead of continuing the normal left-to-
-- right/top-to-bottom flow) still gets counted as if it were extending that
-- same chain - so the computed total size no longer matches what's actually
-- on screen, and can change from refresh to refresh (e.g. whenever a
-- different group becomes the widest one as the roster changes). Since the
-- window frame's own anchor point isn't necessarily its top-left corner,
-- resizing it to a wrong/fluctuating size makes the whole window visibly
-- drift on screen (most noticeably vertically) even though nothing the
-- person did should have moved it.
--
-- Fix: after Grid2Layout's own UpdateSize() runs, recompute the frame's
-- size from the ACTUAL on-screen bounding box of every visible header
-- instead - this is correct regardless of how headers are arranged,
-- handles custom-positioned ones automatically, and is a no-op (produces
-- the same result) for layouts that don't use any of this file's overrides.
-- NOTE: an earlier version of this function also tried to compensate for
-- the on-screen drift a "Center" (or similar) window anchor causes when the
-- window's size changes (see git history) - that was reverted after it
-- caused the whole window to end up positioned off-screen for some users,
-- most likely because repeatedly re-measuring/re-correcting the position on
-- every single roster update let small measurement errors accumulate over
-- time into a large one. Only the (safe, well-tested) size calculation
-- remains here for now. The Center-anchor drift issue itself is still real,
-- but needs a more careful fix - e.g. correcting only once right after a
-- genuine LoadLayout, not on every roster change - rather than reintroducing
-- the same risk.
local function RecomputeFrameSize()
	local frame = Grid2Layout.frame
	if not frame or InCombatLockdown() then
		return
	end

	-- Headers using our own customAnchor ("Custom position") are satellite
	-- elements positioned relative to the frame (or elsewhere) - they must
	-- be EXCLUDED from the frame's own bounding-box calculation below, or
	-- there's a circular dependency: the frame's size would depend on
	-- wherever the satellite header CURRENTLY is, while the satellite
	-- header's position depends on the frame's size. Once that gets seeded
	-- wrong (e.g. by a transient bug, or while mid-testing different anchor
	-- settings), every subsequent recalculation just reconfirms the same
	-- wrong state instead of correcting it, because the frame keeps
	-- stretching to "fit" the satellite wherever it ends up.
	local excluded = {}
	local layout = Grid2Layout.layoutSettings[Grid2Layout.layoutName]
	if layout then
		local map
		for i = 1, #layout do
			if layout[i].customAnchor then
				map = map or GetHeaderIndexMap(layout)
				local h = map[i]
				if h then
					excluded[h] = true
				end
			end
		end
	end

	-- An EMPTY header (no current members - e.g. an unused groupFilter slot,
	-- or a raid subgroup nobody is currently in) can still report
	-- IsShown() == true for the header frame itself, even though it has no
	-- visible content at all. Only count headers that actually have at
	-- least one visible child unit button, matching how the real upstream
	-- Grid2 does this same calculation (checking header[1]:IsVisible()).
	local function HasVisibleMember(header)
		local child = header:GetAttribute("child1")
		return child ~= nil and child:IsShown()
	end

	local minLeft, maxRight, minBottom, maxTop
	for _, pool in pairs(Grid2Layout.groups) do
		for _, header in pairs(pool) do
			if header and header:IsShown() and not excluded[header] and HasVisibleMember(header) then
				local l, r, b, t = header:GetLeft(), header:GetRight(), header:GetBottom(), header:GetTop()
				if l and r and b and t then
					minLeft = (minLeft and l < minLeft) and l or minLeft or l
					maxRight = (maxRight and r > maxRight) and r or maxRight or r
					minBottom = (minBottom and b < minBottom) and b or minBottom or b
					maxTop = (maxTop and t > maxTop) and t or maxTop or t
				end
			end
		end
	end
	if minLeft and maxRight and minBottom and maxTop then
		local w, h = maxRight - minLeft, maxTop - minBottom
		if w > 0 and h > 0 then
			frame:SetSize(w, h)
		end
	end
end

--}}}

-- NOTE: a deferred/debounced version of this (using Grid2:ScheduleTimer to
-- delay the recalculation by a fraction of a second, meant to fix a
-- "pet row is wrong until I click Refresh after /reload" timing issue) was
-- tried and reverted - it caused a WORSE regression (every raid frame
-- collapsing onto the same position after /reload). Back to plain
-- synchronous recalculation for now; the original timing issue still needs
-- a safer fix.
--
-- Recompute right after a (re)load of the layout - covers switching into a
-- layout that uses these overrides, and the Layout Editor's "Refresh" button.
hooksecurefunc(Grid2Layout, "LoadLayout", RefreshCustomHeaders)
hooksecurefunc(Grid2Layout, "UpdateSize", RecomputeFrameSize)

-- New buttons can be created at any time as the roster changes (a header is
-- only force-populated up to its configured column/unitsPerColumn count at
-- load time - additional members beyond that get their buttons created
-- later, lazily, by Blizzard's own secure header code). Re-apply the size
-- override AND the position (since "widest of several" can change as the
-- roster changes) on every roster change too.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function()
	RefreshCustomHeaders()
	RecomputeFrameSize()
end)

-- Whenever Grid2 re-applies frame settings (color, texture, border, size...)
-- it resets EVERY unit frame back to the global frame size, which would undo
-- any custom size set here. Re-apply it right after, for whichever headers
-- currently have one.
if Grid2Frame then
	hooksecurefunc(Grid2Frame, "LayoutFrames", function()
		for header, h in pairs(sizedHeaders) do
			ApplyCustomSize(header, h)
		end
	end)
end