-- Survivor UI: the damage meter.
--
-- The game's own meter, drawn again from the numbers it shares (its addon API,
-- AZS_GetMeter): one flat bar per source of damage, the most first, each in a
-- color of its own, a talent's or amulet's own damage tagged as a proc. Hover a line for its card: its damage, share and damage per second,
-- and its critical strikes and normal hits from the combat log.
--
-- Three views, picked from a menu by the title (the arrow beside it, or a
-- right click on the title): Damage, Healing (AZS_GetHealing) and Damage
-- taken (AZS_TAKEN, by the enemy that dealt it). Each keeps its own Reset;
-- the build's colors read the damage shares whichever view shows.
--
-- Reset starts the meter over from that moment and clears the crits. Its
-- size holds through a run: ten lines unless the grip in its bottom right corner
-- sets another size, fewer on a small screen. Each line wears its spell's icon. Hold Alt
-- and drag to move. The game's own meter is put away while this one is on;
-- /sui meter brings it back. Needs the API; without it nothing shows.

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local FONT = SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BUMP = SurvivorUI_FONT_BUMP or 0

local WIDTH = 228               -- the bars' width until the grip sets one
local WIDTH_MIN, WIDTH_MAX = 160, 420
local BAR_HEIGHT = 16
local BAR_GAP = 2
local ICON = BAR_HEIGHT + 2     -- the spell's icon left of its bar, and the gap after it
local LINES = 10                -- lines until the grip sets how many
local LINES_MIN, MAX_LINES = 3, 20

-- One color per source, handed out in the order they first show: twelve hues
-- spread around the wheel, each next one far from the last, so neighbours in
-- the meter never look alike. A proc gets one too; its tag says it is a proc.
local PALETTE = {
	{ 0.93, 0.70, 0.15 }, -- gold
	{ 0.85, 0.20, 0.25 }, -- crimson
	{ 0.25, 0.45, 0.95 }, -- royal blue
	{ 0.30, 0.75, 0.30 }, -- green
	{ 0.65, 0.35, 0.90 }, -- purple
	{ 0.95, 0.50, 0.10 }, -- orange
	{ 0.15, 0.70, 0.70 }, -- teal
	{ 0.95, 0.40, 0.70 }, -- pink
	{ 0.65, 0.85, 0.20 }, -- lime
	{ 0.60, 0.40, 0.25 }, -- brown
	{ 0.45, 0.75, 1.00 }, -- sky
	{ 0.55, 0.55, 0.70 }, -- slate
}
local function Settings()
	SurvivorUIDB = SurvivorUIDB or {}
	if SurvivorUIDB.meter == nil then
		SurvivorUIDB.meter = true
	end
	return SurvivorUIDB
end

local function Num(value)
	return tonumber(value) or 0
end

-- The size the grip in the corner sets: the width of a line, and how many
-- lines show.
local function MeterWidth()
	return math.max(WIDTH_MIN, math.min(WIDTH_MAX, tonumber(Settings().meterWidth) or WIDTH))
end

local function WantedLines()
	return math.max(LINES_MIN, math.min(MAX_LINES, tonumber(Settings().meterLines) or LINES))
end

-- 950, 1.2k, 3.4m
local function Short(value)
	if value >= 1000000 then
		return string.format("%.2fm", value / 1000000)
	elseif value >= 1000 then
		return string.format("%.1fk", value / 1000)
	end
	return math.floor(value + 0.5)
end

local function Running()
	if not (AZS_GetPhase and AZS_GetMeter) then
		return false
	end
	local phase = AZS_GetPhase()
	return phase and phase ~= "ready"
end

-- The meter's views. rate names the per second figure by the title.
local MODES = {
	{ key = "damage",  title = "Damage",       rate = "DPS" },
	{ key = "healing", title = "Healing",      rate = "HPS" },
	{ key = "taken",   title = "Damage taken", rate = "DTPS" },
}

local function Mode()
	local wanted = Settings().meterMode
	for index = 1, table.getn(MODES) do
		if MODES[index].key == wanted then
			return MODES[index]
		end
	end
	return MODES[1]
end

-- A view's lines as the game shares them ({ name, dmg, share, proc } each),
-- their total and that per second. Damage taken comes as { source, dmg }: its
-- shares and rate are worked out here, over the run so far.
local function GameLines(key)
	if key == "healing" then
		local lines, total, rate = {}, 0, 0
		if AZS_GetHealing then
			local game
			game, total, rate = AZS_GetHealing()
			for index = 1, table.getn(game or {}) do
				local line = game[index]
				table.insert(lines, { name = line.name, dmg = Num(line.dmg), dps = Num(line.dps), proc = line.proc })
			end
			total, rate = Num(total), Num(rate)
		end
		-- What shields absorbed (SurvivorUI.lua), each a line tagged as an
		-- absorb, unless the game's own healing already names that shield.
		local named = {}
		for index = 1, table.getn(lines) do
			named[lines[index].name or "?"] = true
		end
		local seconds = (AZS_GetRunTime and AZS_GetRunTime()) or 0
		for name, amount in pairs(SurvivorUI_AbsorbTotals and SurvivorUI_AbsorbTotals() or {}) do
			if amount > 0 and not named[name] then
				table.insert(lines, { name = name, dmg = amount, dps = seconds > 0 and amount / seconds or 0, absorb = true })
				total = total + amount
				rate = rate + (seconds > 0 and amount / seconds or 0)
			end
		end
		table.sort(lines, function(a, b) return a.dmg > b.dmg end)
		for index = 1, table.getn(lines) do
			lines[index].share = total > 0 and lines[index].dmg / total or 0
		end
		return lines, total, rate
	elseif key == "taken" then
		local list, total = {}, 0
		for index = 1, table.getn(AZS_TAKEN or {}) do
			local entry = AZS_TAKEN[index]
			local dmg = Num(entry.dmg or entry[2])
			if dmg > 0 then
				table.insert(list, { name = entry.source or entry[1] or "?", dmg = dmg })
				total = total + dmg
			end
		end
		table.sort(list, function(a, b) return a.dmg > b.dmg end)
		for index = 1, table.getn(list) do
			list[index].share = total > 0 and list[index].dmg / total or 0
		end
		local seconds = (AZS_GetRunTime and AZS_GetRunTime()) or 0
		return list, total, seconds > 0 and total / seconds or 0
	end
	if not AZS_GetMeter then
		return {}, 0, 0
	end
	local lines, total, dps = AZS_GetMeter()
	return lines or {}, Num(total), Num(dps)
end

-- An enemy has no spell icon: the lines of damage taken wear a skull.
local TAKEN_ICON = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"

-- On, and the game sharing its meter.
function SurvivorUI_MeterActive()
	return Settings().meter and AZS_GetMeter ~= nil
end

------------------------------------------------------------------------------
-- The frame: a title line, then room for every bar from the start, so its size
-- holds through a run. At the bottom of the right column.

local meter = CreateFrame("Frame", "SurvivorUIMeter", UIParent)
meter:SetWidth(WIDTH + 8)
meter:SetHeight(24 + LINES * (BAR_HEIGHT + BAR_GAP))
meter:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -12, 40)
meter:SetBackdrop({ bgFile = FLAT })
-- The right column's one shade, as the run timer and the build wear it.
meter:SetBackdropColor(0.04, 0.04, 0.07, 0.55)
meter:SetMovable(true)
meter:EnableMouse(true)
meter:RegisterForDrag("LeftButton")
meter:Hide()

local function SavePlace()
	local settings = Settings()
	settings.meterRight = math.floor(meter:GetRight() + 0.5)
	settings.meterBottom = math.floor(meter:GetBottom() + 0.5)
end

local shownLines = LINES

local function SetLines(count)
	if count ~= shownLines then
		shownLines = count
		meter:SetHeight(24 + count * (BAR_HEIGHT + BAR_GAP))
	end
end

-- The saved place, with the lines the grip set; else the right column, under
-- the build (or the run timer), with as many of those lines as fit above the
-- screen's bottom, three at least. A small screen gets a shorter meter rather
-- than an overlap.
-- The size follows the layout, never the numbers, so it holds through a run.
-- What the meter hangs from, last time: it is seated again only when that
-- changes, so a drag in progress is never pulled back.
local seatedOn
local sizing = false            -- the grip is being dragged: the layout keeps its hands off

local function Seat(key, point, relative, relativePoint, x, y)
	if seatedOn ~= key then
		seatedOn = key
		meter:ClearAllPoints()
		meter:SetPoint(point, relative, relativePoint, x, y)
	end
end

local function Fit()
	if sizing then
		return
	end
	local settings = Settings()
	if settings.meterRight then
		Seat("saved"..settings.meterRight..","..settings.meterBottom, "BOTTOMRIGHT", UIParent, "BOTTOMLEFT", settings.meterRight, settings.meterBottom)
		SetLines(WantedLines())
		return
	end
	local build, tracker = SurvivorUIBuild, SurvivorUITracker
	local above, shift = nil, 0
	if build and build:IsShown() and build:GetBottom() then
		above = build
	elseif tracker and tracker:GetBottom() then
		above, shift = tracker, 8
	end
	if not above then
		Seat("screen", "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -12, 40)
		SetLines(WantedLines())
		return
	end
	Seat(above:GetName(), "TOPRIGHT", above, "BOTTOMRIGHT", shift, -10)
	local room = above:GetBottom() - 10 - 8
	local fit = math.floor((room - 24) / (BAR_HEIGHT + BAR_GAP))
	SetLines(math.max(LINES_MIN, math.min(WantedLines(), fit)))
end

local function StartMove()
	if IsAltKeyDown() then
		meter:StartMoving()
	end
end

local function StopMove()
	meter:StopMovingOrSizing()
	SavePlace()
end

meter:SetScript("OnDragStart", StartMove)
meter:SetScript("OnDragStop", StopMove)

meter.title = meter:CreateFontString(nil, "OVERLAY")
meter.title:SetFont(FONT, 11 + FONT_BUMP, "OUTLINE")
meter.title:SetPoint("TOPLEFT", meter, "TOPLEFT", 5, -5)
meter.title:SetTextColor(1, 0.82, 0)
meter.title:SetText("Damage")

-- The title row is the meter's handle: grab it anywhere left of Reset and
-- drag, no Alt needed (the grid's snap applies). Its tooltip says what the
-- meter leaves to the game's: healing and boss damage.
local function TitleDragStart()
	meter:StartMoving()
end

local function TitleDragStop()
	meter:StopMovingOrSizing()
	if SurvivorUI_SnapToGrid then
		SurvivorUI_SnapToGrid(meter)
	end
	SavePlace()
end

local titleHover = CreateFrame("Frame", nil, meter)
titleHover:SetPoint("TOPLEFT", meter, "TOPLEFT", 0, 0)
titleHover:SetPoint("TOPRIGHT", meter, "TOPRIGHT", -48, 0)
titleHover:SetHeight(20)
titleHover:EnableMouse(true)

-- What each view's lines are, for the title's tooltip.
local MODE_TIPS = {
	damage = "The game's own numbers, for the whole run or since you last pressed Reset. Hover a line for its average cast and targets.",
	healing = "What your spells healed, for the whole run or since Reset. Hover a line for its average heal and whom it healed.",
	taken = "The damage you took, by the enemy that dealt it, for the whole run or since Reset. Hover a line for its average hit and what it hit you with.",
}

titleHover:SetScript("OnEnter", function()
	local mode = Mode()
	GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
	GameTooltip:SetText(mode.title, 1, 0.82, 0)
	GameTooltip:AddLine(MODE_TIPS[mode.key], 1, 1, 1, 1)
	GameTooltip:AddLine("Right-click the title, or click the arrow beside it, for Damage, Healing or Damage taken.", 0.7, 0.7, 0.7, 1)
	GameTooltip:AddLine("Drag this title to move the meter; the corner grip sizes it.", 0.7, 0.7, 0.7, 1)
	GameTooltip:Show()
end)
titleHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
titleHover:RegisterForDrag("LeftButton")
titleHover:SetScript("OnDragStart", TitleDragStart)
titleHover:SetScript("OnDragStop", TitleDragStop)

------------------------------------------------------------------------------
-- The views' menu: a flat list under the title, the view shown in gold. The
-- arrow beside the title opens it, and so does a right click on the title. It
-- closes on a pick, a second click, or once the mouse has been off it a
-- moment.

local MENU_ROW = 18
local MENU_WIDTH = 110
local MENU_LINGER = 0.6         -- seconds off the menu before it closes

local Draw
local scrollOffset = 0          -- lines scrolled past; Draw keeps it in range
local menu = CreateFrame("Frame", nil, meter)
menu:SetFrameStrata("DIALOG")
menu:SetWidth(MENU_WIDTH)
menu:SetHeight(table.getn(MODES) * MENU_ROW + 4)
menu:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
menu:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
menu:SetBackdropBorderColor(0.45, 0.45, 0.5, 1)
menu:EnableMouse(true)
menu:Hide()

local menuRows = {}

local function PaintMenu()
	local shown = Mode().key
	for index = 1, table.getn(menuRows) do
		local row = menuRows[index]
		if row.key == shown then
			row.text:SetTextColor(1, 0.82, 0)
		else
			row.text:SetTextColor(0.85, 0.85, 0.85)
		end
	end
end

for index = 1, table.getn(MODES) do
	local row = CreateFrame("Button", nil, menu)
	row.key = MODES[index].key
	row:SetHeight(MENU_ROW)
	row:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -2 - (index - 1) * MENU_ROW)
	row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -2, -2 - (index - 1) * MENU_ROW)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetTexture(FLAT)
	row.hover:SetAllPoints(row)
	row.hover:SetVertexColor(1, 1, 1, 0.08)
	row.text = row:CreateFontString(nil, "OVERLAY")
	row.text:SetFont(FONT, 10 + FONT_BUMP, "OUTLINE")
	row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.text:SetText(MODES[index].title)
	row:SetScript("OnClick", function()
		Settings().meterMode = this.key
		scrollOffset = 0
		menu:Hide()
		if SurvivorUI_CritCardHide then
			SurvivorUI_CritCardHide()
		end
		Draw()
	end)
	menuRows[index] = row
end

local function ToggleMenu()
	if menu:IsShown() then
		menu:Hide()
		return
	end
	PaintMenu()
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", meter.title, "BOTTOMLEFT", -3, -4)
	menu.away = 0
	menu:Show()
end

-- The arrow beside the title.
local arrow = CreateFrame("Button", nil, meter)
arrow:SetWidth(14)
arrow:SetHeight(14)
arrow:SetFrameLevel(titleHover:GetFrameLevel() + 2)
arrow:SetPoint("LEFT", meter.title, "RIGHT", 3, 0)
arrow.edge = arrow:CreateTexture(nil, "BACKGROUND")
arrow.edge:SetTexture(FLAT)
arrow.edge:SetVertexColor(0.45, 0.45, 0.5, 1)
arrow.edge:SetPoint("TOPLEFT", arrow, "TOPLEFT", -1, 1)
arrow.edge:SetPoint("BOTTOMRIGHT", arrow, "BOTTOMRIGHT", 1, -1)
arrow.fill = arrow:CreateTexture(nil, "BORDER")
arrow.fill:SetTexture(FLAT)
arrow.fill:SetVertexColor(0.08, 0.08, 0.11, 1)
arrow.fill:SetAllPoints(arrow)
arrow.icon = arrow:CreateTexture(nil, "ARTWORK")
arrow.icon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
arrow.icon:SetPoint("TOPLEFT", arrow, "TOPLEFT", -3, 3)
arrow.icon:SetPoint("BOTTOMRIGHT", arrow, "BOTTOMRIGHT", 3, -3)
arrow:SetScript("OnClick", ToggleMenu)
arrow:SetScript("OnEnter", function()
	this.edge:SetVertexColor(1, 0.82, 0, 1)
	GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
	GameTooltip:SetText("Damage, Healing or Damage taken", 1, 1, 1)
	GameTooltip:Show()
end)
arrow:SetScript("OnLeave", function()
	this.edge:SetVertexColor(0.45, 0.45, 0.5, 1)
	GameTooltip:Hide()
end)

titleHover:SetScript("OnMouseUp", function()
	if arg1 == "RightButton" then
		ToggleMenu()
	end
end)

menu:SetScript("OnUpdate", function()
	if MouseIsOver(menu) or MouseIsOver(arrow) then
		this.away = 0
		return
	end
	this.away = (this.away or 0) + arg1
	if this.away >= MENU_LINGER then
		this:Hide()
	end
end)

-- Damage per second alone, larger: "491 DPS".
meter.total = meter:CreateFontString(nil, "OVERLAY")
meter.total:SetFont(FONT, 13 + FONT_BUMP, "OUTLINE")
meter.total:SetPoint("TOPRIGHT", meter, "TOPRIGHT", -50, -4)
meter.total:SetTextColor(1, 1, 1)

-- Reset as a boxed button, as the build's fold buttons: a dark square with a
-- thin edge that turns gold on hover.
local reset = CreateFrame("Button", nil, meter)
reset:SetWidth(38)
reset:SetHeight(14)
reset:SetPoint("TOPRIGHT", meter, "TOPRIGHT", -5, -4)
reset.edge = reset:CreateTexture(nil, "BACKGROUND")
reset.edge:SetTexture(FLAT)
reset.edge:SetVertexColor(0.45, 0.45, 0.5, 1)
reset.edge:SetPoint("TOPLEFT", reset, "TOPLEFT", -1, 1)
reset.edge:SetPoint("BOTTOMRIGHT", reset, "BOTTOMRIGHT", 1, -1)
reset.fill = reset:CreateTexture(nil, "BORDER")
reset.fill:SetTexture(FLAT)
reset.fill:SetVertexColor(0.08, 0.08, 0.11, 1)
reset.fill:SetAllPoints(reset)
reset.text = reset:CreateFontString(nil, "OVERLAY")
reset.text:SetFont(FONT, 9 + FONT_BUMP, "OUTLINE")
reset.text:SetPoint("CENTER", reset, "CENTER", 0, 0)
reset.text:SetText("Reset")
reset.text:SetTextColor(0.75, 0.75, 0.75)
reset:SetScript("OnEnter", function()
	this.text:SetTextColor(1, 1, 1)
	this.edge:SetVertexColor(1, 0.82, 0, 1)
	GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
	GameTooltip:SetText("Starts the meter over from now.", 1, 1, 1)
	GameTooltip:AddLine("Damage, damage per second and shares count from here; the average cast and targets on each line's card start over too.", 0.7, 0.7, 0.7, 1)
	GameTooltip:Show()
end)
reset:SetScript("OnLeave", function()
	this.text:SetTextColor(0.75, 0.75, 0.75)
	this.edge:SetVertexColor(0.45, 0.45, 0.5, 1)
	GameTooltip:Hide()
end)
------------------------------------------------------------------------------
-- Reset: the game's numbers cover the whole run, so the meter keeps what each
-- source stood at when Reset was pressed, and shows what came after. That
-- and each line's color are kept in the run's memory (SurvivorUI_RunMemory),
-- so a reload in the middle of a run changes neither.

-- Each view's Reset point: { at = run second, total, sources = { [source] = amount } }.
local lastSeconds = {}          -- [view] = the run's clock last seen

local function Memory()
	local memory = SurvivorUI_RunMemory and SurvivorUI_RunMemory("meter") or {}
	memory.colors = memory.colors or {}
	memory.given = memory.given or 0
	memory.bases = memory.bases or {}
	-- The one Reset point from before the views came is the damage view's.
	if memory.base then
		memory.bases.damage = memory.bases.damage or memory.base
		memory.base = nil
	end
	return memory
end

local function RunSeconds()
	return (AZS_GetRunTime and AZS_GetRunTime()) or 0
end

local function TakeBase(key)
	local lines, total = GameLines(key)
	local base = { at = RunSeconds(), total = Num(total), sources = {} }
	for index = 1, table.getn(lines) do
		base.sources[lines[index].name or "?"] = Num(lines[index].dmg)
	end
	Memory().bases[key] = base
end

-- Reset starts the view shown over: its numbers and its cards' tally.
reset:SetScript("OnClick", function()
	local key = Mode().key
	TakeBase(key)
	if SurvivorUI_ResetRun then
		SurvivorUI_ResetRun(key)
	end
end)

------------------------------------------------------------------------------
-- The bars.

local bars = {}

-- The run's memory keeps each source's place in the palette.
local function ColorOf(name)
	local memory = Memory()
	if not memory.colors[name] then
		memory.given = memory.given + 1
		memory.colors[name] = math.mod(memory.given - 1, table.getn(PALETTE)) + 1
	end
	return PALETTE[memory.colors[name]] or PALETTE[1]
end

-- A spell's rank, from the game's list (AZS_SPELLS names it by key: "holy_wrath"
-- for "Holy Wrath"), as a Roman numeral: XII.
local SPELL_KEYS = {
	["shadow word: pain"] = "sw_pain", ["power word: shield"] = "pw_shield",
	["demoralizing shout"] = "demo_shout", ["hunter's mark"] = "hunters_mark",
}

local function RankOf(name)
	if not (name and AZS_SPELLS) then
		return nil
	end
	local lower = string.lower(name)
	local key = SPELL_KEYS[lower] or string.gsub(string.gsub(lower, "[^%a ]", ""), " ", "_")
	for index = 1, table.getn(AZS_SPELLS) do
		local entry = AZS_SPELLS[index]
		if (entry.key or entry[1]) == key then
			return tonumber(entry.rank or entry[3])
		end
	end
end

local ROMAN = { { 50, "L" }, { 40, "XL" }, { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" } }

local function Roman(number)
	local text = ""
	for index = 1, table.getn(ROMAN) do
		local value, letters = ROMAN[index][1], ROMAN[index][2]
		while number >= value do
			text = text..letters
			number = number - value
		end
	end
	return text
end

-- The same color for the same source anywhere in the interface (the build list).
function SurvivorUI_MeterColor(name)
	return ColorOf(name)
end

-- A source's share of the meter's damage as shown, 0 to 1, or nil. Looked up
-- whatever the case ("Hammer Of Justice" finds "Hammer of Justice").
local shares = {}               -- [lower case name] = share
function SurvivorUI_MeterShare(name)
	return name and shares[string.lower(name)]
end

-- A source's icon, the first found of: the spell's own from the spellbook; a
-- worn item's of that name (an amulet's own proc); a talent's own, from the
-- game's talent list (TalentIcons.lua), for a talent's proc (as Rampage);
-- else the icon of the build spell whose tooltip lists that talent; a
-- talent's from WoW's talent tree. Melee is a sword ("Attack" from the book
-- where it has one). Names are matched whatever the case. Found icons are kept until
-- the book or the talents change; a miss is tried again a few seconds later,
-- as the action bar is empty while the cards are up.
local MELEE_ICON = "Interface\\Icons\\INV_Sword_04"
local ICON_RETRY = 10
local icons = {}                -- [source] = texture
local iconMissed = {}           -- [source] = when it was last looked for in vain

-- A worn piece named as the source, or one name starting with the other
-- ("Amulet of the Inferno" for "Amulet of the Inferno: Consecration").
local function ItemIcon(wanted)
	for slot = 1, 19 do
		local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
		local _, _, item = string.find(link or "", "%[(.-)%]")
		if item then
			item = string.lower(item)
			if item == wanted or string.sub(item, 1, string.len(wanted)) == wanted
				or string.sub(wanted, 1, string.len(item)) == item then
				return GetInventoryItemTexture("player", slot)
			end
		end
	end
end

local function BookIcon(wanted)
	local book = BOOKTYPE_SPELL or "spell"
	local index = 1
	while true do
		local spell = GetSpellName(index, book)
		if not spell then
			return nil
		end
		if string.lower(spell) == wanted then
			return GetSpellTexture(index, book)
		end
		index = index + 1
	end
end

local function TalentIcon(wanted)
	if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then
		return nil
	end
	for tab = 1, GetNumTalentTabs() do
		for index = 1, GetNumTalents(tab) do
			local talent, texture = GetTalentInfo(tab, index)
			if talent and string.lower(talent) == wanted then
				return texture
			end
		end
	end
end

-- A talent's own icon, from the game's talent list (TalentIcons.lua), by name
-- whatever the case.
local talentIcons
local function OwnTalentIcon(wanted)
	if not talentIcons then
		talentIcons = {}
		for talent, texture in pairs(SurvivorUI_TALENT_ICONS or {}) do
			talentIcons[string.lower(talent)] = texture
		end
	end
	return talentIcons[wanted]
end

local function IconOf(name)
	if icons[name] then
		return icons[name]
	end
	if iconMissed[name] and GetTime() - iconMissed[name] < ICON_RETRY then
		return nil
	end
	local wanted = string.lower(name or "")
	local texture
	if name == "Melee" then
		texture = BookIcon("attack") or MELEE_ICON
	else
		texture = BookIcon(wanted) or ItemIcon(wanted) or OwnTalentIcon(wanted)
			or (SurvivorUI_TalentOwnerIcon and SurvivorUI_TalentOwnerIcon(name))
			or TalentIcon(wanted)
	end
	if texture then
		icons[name] = texture
		iconMissed[name] = nil
	else
		iconMissed[name] = GetTime()
	end
	return texture
end

local iconWatch = CreateFrame("Frame")
iconWatch:RegisterEvent("SPELLS_CHANGED")
iconWatch:RegisterEvent("CHARACTER_POINTS_CHANGED")
iconWatch:RegisterEvent("UNIT_INVENTORY_CHANGED")
iconWatch:SetScript("OnEvent", function()
	icons = {}
	iconMissed = {}
end)

-- The build's muting (BuildList.lua): a color dulled toward grey, and its fill.
local BAR_FILL = 0.6

local function Dull(color)
	return { color[1] * 0.65 + 0.08, color[2] * 0.65 + 0.08, color[3] * 0.65 + 0.08 }
end

-- Lines past the meter's size are reached with the mouse wheel anywhere over
-- it: the title, the bars or the space between (scrollOffset, by Draw).
local function MeterWheel()
	scrollOffset = scrollOffset - arg1
	Draw()
end

meter:EnableMouseWheel(true)
meter:SetScript("OnMouseWheel", MeterWheel)
titleHover:EnableMouseWheel(true)
titleHover:SetScript("OnMouseWheel", MeterWheel)

-- A thin marker down the right edge while lines are hidden: as tall against
-- the bars' room as the lines shown against all of them, where they stand.
local scrollMark = meter:CreateTexture(nil, "OVERLAY")
scrollMark:SetTexture(FLAT)
scrollMark:SetVertexColor(1, 0.82, 0, 0.6)
scrollMark:SetWidth(2)
scrollMark:Hide()

local function Bar(index)
	local bar = bars[index]
	if bar then
		return bar
	end
	bar = CreateFrame("StatusBar", nil, meter)
	bar:SetWidth(MeterWidth() - ICON)
	bar:SetHeight(BAR_HEIGHT)
	bar:SetStatusBarTexture(FLAT)
	bar:SetMinMaxValues(0, 1)

	bar.backing = bar:CreateTexture(nil, "BACKGROUND")
	bar.backing:SetTexture(FLAT)
	bar.backing:SetVertexColor(0.10, 0.10, 0.13, 0.9)
	bar.backing:SetAllPoints(bar)

	-- A thin black edge, as on the build's rows: a frame just under the bar,
	-- a pixel larger all round.
	bar.edge = CreateFrame("Frame", nil, meter)
	bar.edge:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
	bar.edge:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
	bar.edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
	bar.edge.fill = bar.edge:CreateTexture(nil, "BACKGROUND")
	bar.edge.fill:SetTexture(FLAT)
	bar.edge.fill:SetVertexColor(0, 0, 0, 1)
	bar.edge.fill:SetAllPoints(bar.edge)

	-- The icon, square, just left of the bar on a dark square of its own.
	bar.iconBack = bar:CreateTexture(nil, "BACKGROUND")
	bar.iconBack:SetTexture(FLAT)
	bar.iconBack:SetVertexColor(0.10, 0.10, 0.13, 0.9)
	bar.iconBack:SetWidth(BAR_HEIGHT)
	bar.iconBack:SetHeight(BAR_HEIGHT)
	bar.iconBack:SetPoint("RIGHT", bar, "LEFT", -(ICON - BAR_HEIGHT), 0)
	bar.icon = bar:CreateTexture(nil, "ARTWORK")
	bar.icon:SetAllPoints(bar.iconBack)
	bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	bar.name = bar:CreateFontString(nil, "OVERLAY")
	bar.name:SetFont(FONT, 9 + FONT_BUMP, "OUTLINE")
	bar.name:SetPoint("LEFT", bar, "LEFT", 4, 0)
	-- Room for the numbers on the right: damage and share.
	bar.name:SetWidth(MeterWidth() - ICON - 76)
	bar.name:SetHeight(12)
	bar.name:SetJustifyH("LEFT")
	bar.name:SetTextColor(1, 1, 1)

	-- "(proc)", smaller, right after the name.
	bar.tag = bar:CreateFontString(nil, "OVERLAY")
	bar.tag:SetFont(FONT, 7 + FONT_BUMP, "OUTLINE")
	bar.tag:SetTextColor(0.78, 0.91, 1)
	bar.tag:SetText("(proc)")
	bar.tag:Hide()

	bar.value = bar:CreateFontString(nil, "OVERLAY")
	bar.value:SetFont(FONT, 9 + FONT_BUMP, "OUTLINE")
	bar.value:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
	bar.value:SetTextColor(1, 1, 1)

	-- The crit card sits beside the whole meter, on its left, tops together.
	bar.cardFrame = meter
	bar:EnableMouse(true)
	bar:SetScript("OnEnter", function()
		if SurvivorUI_CritCardShow then
			SurvivorUI_CritCardShow(this)
		end
	end)
	bar:SetScript("OnLeave", function()
		if SurvivorUI_CritCardHide then
			SurvivorUI_CritCardHide()
		end
	end)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", StartMove)
	bar:SetScript("OnDragStop", StopMove)
	bar:EnableMouseWheel(true)
	bar:SetScript("OnMouseWheel", MeterWheel)

	bars[index] = bar
	return bar
end

-- A view's lines, or what came after its Reset: each source's amount less
-- what it had then, the most first, shares and the rate from there.
local function Lines(key)
	local lines, total, dps = GameLines(key)
	local seconds = RunSeconds()
	local memory = Memory()
	local base = memory.bases[key]
	-- The clock going back means a new run: the reset goes with the old one.
	if base and lastSeconds[key] and seconds + 3 < lastSeconds[key] then
		base = nil
		memory.bases[key] = nil
	end
	lastSeconds[key] = seconds
	-- Each line's own rate: the game's per second figure where it gives one,
	-- else its amount over the run so far.
	if not base then
		local shown = {}
		for index = 1, table.getn(lines) do
			local line = lines[index]
			local dmg = Num(line.dmg)
			local rate = Num(line.dps)
			if rate <= 0 and seconds > 0 then
				rate = dmg / seconds
			end
			table.insert(shown, { name = line.name or "?", dmg = dmg, share = Num(line.share), proc = Num(line.proc) == 1,
				absorb = line.absorb, rate = rate })
		end
		return shown, total, dps
	end

	local shown, sum = {}, 0
	for index = 1, table.getn(lines) do
		local line = lines[index]
		local name = line.name or "?"
		local dmg = Num(line.dmg) - (base.sources[name] or 0)
		if dmg > 0 then
			table.insert(shown, { name = name, dmg = dmg, proc = Num(line.proc) == 1, absorb = line.absorb })
			sum = sum + dmg
		end
	end
	table.sort(shown, function(a, b) return a.dmg > b.dmg end)
	-- Since Reset, each line's rate is its amount over the time since.
	local span = seconds - base.at
	for index = 1, table.getn(shown) do
		shown[index].share = sum > 0 and shown[index].dmg / sum or 0
		shown[index].rate = span > 0 and shown[index].dmg / span or 0
	end
	return shown, sum, span > 0 and sum / span or 0
end

Draw = function()
	local mode = Mode()
	local lines, total, dps = Lines(mode.key)
	-- The build's colors read the damage shares, whichever view shows.
	local damageLines = mode.key == "damage" and lines or Lines("damage")
	for name in pairs(shares) do
		shares[name] = nil
	end
	for index = 1, table.getn(damageLines) do
		shares[string.lower(damageLines[index].name or "?")] = damageLines[index].share
	end
	meter.title:SetText(mode.title)
	meter.total:SetText(Short(dps).." |cffb0b0b0"..mode.rate.."|r")

	-- The lines scrolled to, kept in range as lines come and go; the bars
	-- keep the top line's scale, and each its place in the whole list.
	local all = table.getn(lines)
	scrollOffset = math.max(0, math.min(scrollOffset, all - shownLines))
	local count = math.min(shownLines, all - scrollOffset)
	local top = all > 0 and lines[1].dmg or 0
	if all > shownLines then
		local room = shownLines * (BAR_HEIGHT + BAR_GAP) - BAR_GAP
		scrollMark:ClearAllPoints()
		scrollMark:SetHeight(math.max(6, room * shownLines / all))
		scrollMark:SetPoint("TOPRIGHT", meter, "TOPRIGHT", -1, -20 - room * scrollOffset / all)
		scrollMark:Show()
	else
		scrollMark:Hide()
	end
	for index = 1, count do
		local place = scrollOffset + index
		local line = lines[place]
		local name = line.name
		-- A talent's or amulet's own damage says "(proc)", a shield's soak "(absorb)".
		local proc = line.proc or line.absorb
		-- A spell of the build wears its rarity's color, as in the build; a
		-- proc or melee keeps a palette color of its own. With Distinguishing
		-- Colors on, every line takes a palette color of its own instead, each
		-- far from the next, so neighbours never look alike.
		local color
		if not Settings().meterDistinct and SurvivorUI_SpellColor then
			color = SurvivorUI_SpellColor(name)
		end
		color = color or ColorOf(name)
		local bar = Bar(index)
		bar.tag:SetText(line.absorb and "(absorb)" or "(proc)")

		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", meter, "TOPLEFT", 4 + ICON, -20 - (index - 1) * (BAR_HEIGHT + BAR_GAP))
		bar:SetValue(top > 0 and line.dmg / top or 0)
		-- Muted as the build's rows are: the color dulled toward grey, laid as
		-- lightly over the dark backing.
		local dull = Dull(color)
		bar:SetStatusBarColor(dull[1], dull[2], dull[3], BAR_FILL)
		bar.ability = name
		bar.color = color
		bar.damage, bar.share, bar.rate = line.dmg, line.share, line.rate
		bar.mode = mode.key
		if mode.key == "taken" then
			bar.icon:SetTexture(TAKEN_ICON)
		else
			bar.icon:SetTexture(IconOf(name))
		end

		-- A talent's or amulet's own damage says so, as the game's meter does.
		-- The spell's rank after its name, as a Roman numeral: "Holy Wrath XII".
		-- The numbers first: the name gets the room they leave, so a long name
		-- ends short of them however wide they grow ("89.38m 49%").
		bar.value:SetText(Short(line.dmg).."  |cffb0b0b0"..math.floor(line.share * 100 + 0.5).."%|r")
		local room = bar:GetWidth() - 4 - bar.value:GetStringWidth() - 12
		if proc then
			room = room - bar.tag:GetStringWidth() - 4
		end
		room = math.max(20, room)
		bar.name:SetWidth(room)
		local rank = mode.key ~= "taken" and RankOf(name)
		bar.name:SetText(place..". "..name..(rank and rank > 0 and "  |cffbdbdbd"..Roman(rank).."|r" or ""))
		if proc then
			bar.tag:ClearAllPoints()
			bar.tag:SetPoint("LEFT", bar, "LEFT", 4 + math.min(bar.name:GetStringWidth(), room) + 4, 0)
			bar.tag:Show()
		else
			bar.tag:Hide()
		end
		bar:Show()
		bar.edge:Show()
	end
	for index = count + 1, table.getn(bars) do
		bars[index]:Hide()
		bars[index].edge:Hide()
		bars[index].ability = nil
	end
end

------------------------------------------------------------------------------
-- /sui icons: for each line of the meter, which way to its icon finds one,
-- and the worn jewelry's names, so a line without an icon can be told apart.

function SurvivorUI_DebugIcons()
	local say = function(text) DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Survivor UI icons:|r "..text) end
	local lines = Lines("damage")
	if table.getn(lines) == 0 then
		say("the meter has no lines yet.")
	end
	local function Mark(found)
		return found and "|cff40ff40yes|r" or "|cffff6060no|r"
	end
	for index = 1, math.min(MAX_LINES, table.getn(lines)) do
		local name = lines[index].name or "?"
		local wanted = string.lower(name)
		say("["..name.."]  book "..Mark(BookIcon(wanted))
			.."  item "..Mark(ItemIcon(wanted))
			.."  talent's spell "..Mark(SurvivorUI_TalentOwnerIcon and SurvivorUI_TalentOwnerIcon(name))
			.."  talent tree "..Mark(TalentIcon(wanted)))
	end
	for _, slot in pairs({ 2, 11, 12, 13, 14 }) do
		local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
		local _, _, item = string.find(link or "", "%[(.-)%]")
		say("worn slot "..slot..": ["..(item or "nothing").."]")
	end
	if SurvivorUI_DebugTalentLines then
		SurvivorUI_DebugTalentLines(say)
	end
	-- Which meter lines the combat log names: a line it never names has no blows
	-- to build its card (average cast, targets) from.
	if SurvivorUI_LogNames then
		local seen = SurvivorUI_LogNames()
		for index = 1, math.min(MAX_LINES, table.getn(lines)) do
			local name = lines[index].name or "?"
			say("log ["..name.."]: "..(seen[name] and ("|cff40ff40"..seen[name].." blows|r") or "|cffff6060never named|r"))
		end
		local others = {}
		for name, count in pairs(seen) do
			local onMeter = false
			for index = 1, table.getn(lines) do
				if lines[index].name == name then
					onMeter = true
				end
			end
			if not onMeter then
				table.insert(others, name.." ("..count..")")
			end
		end
		if table.getn(others) > 0 then
			say("log names not on the meter: "..table.concat(others, ", "))
		end
	end
end

------------------------------------------------------------------------------
-- The grip in the bottom right corner: drag it to size the meter. Sideways
-- sets the lines' width, up and down how many lines show, a whole line at a
-- time. While it is dragged the top left corner holds still, so the grip stays
-- under the mouse; let go, the meter keeps that place and size.

local function ApplyWidth()
	local width = MeterWidth()
	meter:SetWidth(width + 8)
	for index = 1, table.getn(bars) do
		bars[index]:SetWidth(width - ICON)
		bars[index].name:SetWidth(width - ICON - 76)
	end
end

local grip = CreateFrame("Button", nil, meter)
grip:SetWidth(12)
grip:SetHeight(12)
grip:SetPoint("BOTTOMRIGHT", meter, "BOTTOMRIGHT", -1, 1)
grip:SetFrameLevel(meter:GetFrameLevel() + 5)
grip.dots = {}
-- Six dots in a corner triangle, as a window's resize corner.
for _, spot in pairs({ { 0, 0 }, { 4, 0 }, { 8, 0 }, { 0, 4 }, { 4, 4 }, { 0, 8 } }) do
	local dot = grip:CreateTexture(nil, "OVERLAY")
	dot:SetTexture(FLAT)
	dot:SetWidth(2)
	dot:SetHeight(2)
	dot:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -spot[1], spot[2])
	dot:SetVertexColor(0.6, 0.6, 0.6, 0.9)
	table.insert(grip.dots, dot)
end

local function TintGrip(r, g, b)
	for index = 1, table.getn(grip.dots) do
		grip.dots[index]:SetVertexColor(r, g, b, 0.9)
	end
end

local function Cursor()
	local scale = meter:GetEffectiveScale()
	local x, y = GetCursorPosition()
	return x / scale, y / scale
end

grip:SetScript("OnEnter", function()
	TintGrip(1, 0.82, 0)
	GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
	GameTooltip:SetText("Drag to size the meter", 1, 1, 1)
	GameTooltip:AddLine("Sideways: wider or thinner. Up and down: fewer or more lines.", 0.7, 0.7, 0.7, 1)
	GameTooltip:Show()
end)
grip:SetScript("OnLeave", function()
	if not sizing then
		TintGrip(0.6, 0.6, 0.6)
	end
	GameTooltip:Hide()
end)
grip:SetScript("OnMouseDown", function()
	local left, top = meter:GetLeft(), meter:GetTop()
	if not left then
		return
	end
	sizing = true
	GameTooltip:Hide()
	meter:ClearAllPoints()
	meter:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	local x, y = Cursor()
	this.from = { x = x, y = y, width = MeterWidth(), lines = shownLines }
end)
grip:SetScript("OnUpdate", function()
	if not (sizing and this.from) then
		return
	end
	local x, y = Cursor()
	local settings = Settings()
	settings.meterWidth = math.max(WIDTH_MIN, math.min(WIDTH_MAX, math.floor(this.from.width + x - this.from.x + 0.5)))
	settings.meterLines = math.max(LINES_MIN, math.min(MAX_LINES,
		this.from.lines + math.floor((this.from.y - y) / (BAR_HEIGHT + BAR_GAP) + 0.5)))
	ApplyWidth()
	SetLines(WantedLines())
end)
grip:SetScript("OnMouseUp", function()
	if not sizing then
		return
	end
	sizing = false
	this.from = nil
	TintGrip(0.6, 0.6, 0.6)
	SavePlace()
	seatedOn = nil
end)

local elapsed = 0
local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function()
	elapsed = elapsed + arg1
	if elapsed < 0.25 then
		return
	end
	elapsed = 0
	Fit()
	-- In preview (before the first step, or with Alt held) it shows anyway, so
	-- it can be placed and sized.
	if Settings().meter and (Running() or (SurvivorUI_Preview and SurvivorUI_Preview())) then
		Draw()
		if not meter:IsShown() then
			meter:Show()
		end
	elseif meter:IsShown() then
		meter:Hide()
	end
end)

------------------------------------------------------------------------------
-- The game's own meter: away while this one is on. The setting is the game's
-- and is saved, so the addon remembers that it was the one to turn it off.

local function ApplyGameHud()
	if not (AZS_SetHudShown and AZS_IsHudShown) then
		return
	end
	local settings = Settings()
	if settings.meter then
		if AZS_IsHudShown("meter") then
			AZS_SetHudShown("meter", false)
			settings.hidGameMeter = true
		end
	elseif settings.hidGameMeter then
		AZS_SetHudShown("meter", true)
		settings.hidGameMeter = nil
	end
end

function SurvivorUI_ToggleMeter()
	local settings = Settings()
	settings.meter = not settings.meter
	ApplyGameHud()
	DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: "..(settings.meter
		and "damage meter on; the game's own meter is put away."
		or "damage meter off; the game's own is back, with its healing and boss damage."))
end

if SurvivorUI_RegisterOption then
	SurvivorUI_RegisterOption({
		section = "General",
		label = "Distinguishing Colors",
		parent = "Damage meter",
		tip = "Every line in a color of its own, picked so neighbours never look alike, instead of its spell's rarity color from the build. Muted either way.",
		get = function() return Settings().meterDistinct == true end,
		toggle = function()
			local settings = Settings()
			settings.meterDistinct = not settings.meterDistinct
		end,
	})
	SurvivorUI_RegisterOption({
		section = "General",
		label = "Damage meter",
		tip = "The addon's damage meter, with the crits on hover, in place of the game's own. Off, the game's meter is back, with its healing and boss damage.",
		command = "/sui meter",
		get = function() return Settings().meter end,
		toggle = SurvivorUI_ToggleMeter,
	})
end

-- The game's tooltip for units and the world: it opens at an anchor of its own
-- that Alt can move. Left where it is, the anchor sits beside the meter, on its
-- left, bottoms together (the tooltip's stock corner is where the meter is), or
-- in that corner when the meter is off.
local tipAnchor = CreateFrame("Frame", "SurvivorUITooltipAnchor", UIParent)
tipAnchor:SetWidth(200)
tipAnchor:SetHeight(80)
tipAnchor:SetMovable(true)
if tipAnchor.SetClampedToScreen then
	tipAnchor:SetClampedToScreen(true)
end

local function PlaceTipAnchor()
	local settings = Settings()
	tipAnchor:ClearAllPoints()
	if settings.tipRight then
		tipAnchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", settings.tipRight, settings.tipBottom)
	elseif meter:IsVisible() then
		tipAnchor:SetPoint("BOTTOMRIGHT", meter, "BOTTOMLEFT", -6, 0)
	else
		tipAnchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -13, 64)
	end
end

local function SaveTipAnchor()
	local settings = Settings()
	settings.tipRight = math.floor(tipAnchor:GetRight() + 0.5)
	settings.tipBottom = math.floor(tipAnchor:GetBottom() + 0.5)
end

local stockDefaultAnchor = GameTooltip_SetDefaultAnchor
if stockDefaultAnchor then
	GameTooltip_SetDefaultAnchor = function(tooltip, parent)
		stockDefaultAnchor(tooltip, parent)
		if tooltip then
			PlaceTipAnchor()
			tooltip:ClearAllPoints()
			tooltip:SetPoint("BOTTOMRIGHT", tipAnchor, "BOTTOMRIGHT", 0, 0)
		end
	end
end

if SurvivorUI_RegisterMover then
	SurvivorUI_RegisterMover(tipAnchor, "Tooltip", SaveTipAnchor, nil, PlaceTipAnchor)
end
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function()
	seatedOn = nil
	ApplyWidth()
	Fit()
	ApplyGameHud()
end)

if SurvivorUI_RegisterMover then
	SurvivorUI_RegisterMover(meter, "Damage meter", SavePlace, nil, function()
		seatedOn = nil
		Fit()
	end)
end
