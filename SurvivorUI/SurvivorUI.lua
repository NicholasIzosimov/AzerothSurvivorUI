-- Survivor UI: unit frames and an action bar for Azeroth Survivors, in the
-- flat, dark manner of EllesmereUI. Everything sits in one centered row at the
-- bottom of the screen:
--
--   [portrait][ player ]  [1][2][3][4][5][6][=]  [ target ][portrait]
--
--   Unit frames: a health bar in the class color (red for an enemy) on a dark
--   backing with a thin black border, the name on the left, the health on the
--   right ("439K | 100%"), a slim power bar underneath and the portrait on the
--   outer end. The target's debuffs line up above its frame. They replace the
--   stock player and target frames. Each frame moves on its own in edit mode
--   (/sui layout puts both back beside the buttons); /sui opt sizes them.
--
--   Action bar: the game only uses the first bar. Buttons 1 to 6 and the last
--   button (the = key) make the middle of the row; the rest of the bar and its
--   art are put away. The experience bar becomes a thin strip under the row.
--
--   Also: the hero's buffs and debuffs above the player frame with time left
--   and stacks, cooldown numbers on the buttons, a square minimap, a flat
--   chat panel scrolled with the mouse wheel, and the micro buttons in the
--   bottom right corner, shown when the mouse reaches them.
--
--   Friz Quadrata on every piece of interface text, a flat tooltip, and small
--   quick damage numbers in place of the engine's (/sui combattext switches
--   back). /sui opt opens a window with every switch the addon has.
--
-- The row sits a little under the hero, who stands in the middle of the screen.
--
-- Left click a frame to target it, right click for its menu.

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
-- The interface's face, shared with the addon's other files: Friz Quadrata, the
-- game's own, unless a face is dropped in: Expressway in SurvivorUI\Fonts, or
-- Barlow Condensed in SurvivorUI\Media (neither is shipped).
-- A face that does not load leaves a font string without one, so each is tried
-- on a probe first, and Friz Quadrata, the game's own, is the last resort.
local FACES = {
	{ path = "Interface\\AddOns\\SurvivorUI\\Fonts\\Expressway.ttf", mark = "expressway" },
	{ path = "Interface\\AddOns\\SurvivorUI\\Media\\BarlowCondensed-Medium.ttf", mark = "barlow", bump = 1 },
}

local function FaceLoads(face)
	local probe = UIParent:CreateFontString(nil, "OVERLAY")
	probe:SetFont(face.path, 12)
	local got = probe:GetFont()
	return got and string.find(string.lower(got), face.mark, 1, true) ~= nil
end

SurvivorUI_FONT = "Fonts\\FRIZQT__.TTF"
SurvivorUI_FONT_BUMP = 0
for index = 1, table.getn(FACES) do
	if FaceLoads(FACES[index]) then
		SurvivorUI_FONT = FACES[index].path
		-- Barlow Condensed reads small at the same size: one point up.
		SurvivorUI_FONT_BUMP = FACES[index].bump or 0
		break
	end
end
local FONT = SurvivorUI_FONT
local FONT_BUMP = SurvivorUI_FONT_BUMP

local BAR_BUTTONS = { 1, 2, 3, 4, 5, 6, 12 }     -- 12 is the = key
local BUTTON_SIZE = 36
local BUTTON_GAP = 2
local ROW_BELOW_CENTER = 150                    -- the row sits this far under the hero, who stands mid-screen
local SECTION_GAP = 6                           -- between a unit frame and the buttons

local FRAME_WIDTH = 150                         -- the bar part of a unit frame
local POWER_HEIGHT = 3
local HEALTH_HEIGHT = BUTTON_SIZE - POWER_HEIGHT - 1

local ENEMY = { 0.80, 0.22, 0.22 }

local CHAT_SIZE = 12                            -- default; /sui chat N changes it

-- Saved between sessions; the /sui command at the end of the file changes them.
local function Settings()
	SurvivorUIDB = SurvivorUIDB or {}
	if SurvivorUIDB.damageText == nil then
		SurvivorUIDB.damageText = true
	end
	if SurvivorUIDB.auraSweep == nil then
		SurvivorUIDB.auraSweep = true
	end
	SurvivorUIDB.chatSize = SurvivorUIDB.chatSize or CHAT_SIZE
	return SurvivorUIDB
end

-- The options window's switches (Options.lua, /sui opt). Every file adds its
-- own, so a new switch shows there by itself:
--   section  the heading it goes under
--   label    its name in the window
--   tip      what it does, on hover
--   command  its /sui command, shown in the tip
--   get      returns whether it is on
--   toggle   flips it, as its /sui command does
SurvivorUI_OPTIONS = {}

function SurvivorUI_RegisterOption(option)
	table.insert(SurvivorUI_OPTIONS, option)
end

-- Preview: every piece shows, data or not, so the layout can be set before a
-- run gets going. True while the game waits for the hero's first step ("Move
-- to begin.") and, anywhere, in edit mode (a tap of Alt). A piece the
-- player switched off stays off.
function SurvivorUI_Preview()
	if SurvivorUI_EditMode() then
		return true
	end
	return AZS_GetPhase ~= nil and AZS_GetPhase() == "ready"
end

-- Edit mode: a quick tap of Alt (let go within ALT_TAP seconds) turns it on,
-- another turns it off. While on, every movable piece shows its handle (drag
-- to move it, click for its options) and every piece shows, data or not. A
-- longer hold, as for Alt and a click or Alt and Tab, changes nothing.
local ALT_TAP = 0.5
local editMode = false
local altDownAt

function SurvivorUI_EditMode()
	return editMode
end

function SurvivorUI_SetEditMode(on)
	if on == editMode then
		return
	end
	editMode = on
	-- Leaving it closes any piece's options box still open.
	if not on and SurvivorUI_CloseElementOptions then
		SurvivorUI_CloseElementOptions()
	end
	DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: "..(on
		and "edit mode on. Drag a piece to move it, click it for its options; tap Alt again to leave."
		or "edit mode off."))
end

local altWatch = CreateFrame("Frame")
altWatch:SetScript("OnUpdate", function()
	if IsAltKeyDown() then
		altDownAt = altDownAt or GetTime()
	elseif altDownAt then
		local held = GetTime() - altDownAt
		altDownAt = nil
		if held <= ALT_TAP then
			SurvivorUI_SetEditMode(not editMode)
		end
	end
end)

-- Run memory: what the panels learn as a run goes (when each boss came and
-- fell, the meter's casts and colors, the loot) is kept in the saved
-- variables, so a reload in the middle of a run picks up where it left off
-- instead of starting blind. Each panel keeps a part of its own
-- (SurvivorUI_RunMemory("tracker")). It belongs to one run: the clock gone
-- back, another zone, or more run time gone than real time allows since it
-- was last written (a run that is not this one) lets it go, and so does the
-- next run waiting to begin.
local memoryChecked = false     -- the remembered run was checked against this one, this session

-- The run's clock, while one is on; waiting is true between runs.
local function RunClock()
	if not (AZS_GetPhase and AZS_RUN) then
		return nil
	end
	local phase = AZS_GetPhase()
	if not phase then
		return nil
	end
	if phase == "ready" then
		return nil, true
	end
	return (AZS_GetRunTime and AZS_GetRunTime()) or tonumber(AZS_RUN.t) or 0
end

function SurvivorUI_RunMemory(part)
	local settings = Settings()
	local memory = settings.runMemory
	local seconds, waiting = RunClock()
	local now = GetTime()
	local zone = (GetRealZoneText and GetRealZoneText()) or ""
	local fresh = not (memory and memory.parts)
	if not fresh and waiting then
		-- Between runs: the one remembered is over.
		fresh = memory.seconds ~= nil
	elseif not fresh and seconds and memory.seconds then
		if seconds + 3 < memory.seconds then
			fresh = true
		elseif not memoryChecked then
			fresh = memory.zone ~= zone or not memory.wall or now < memory.wall
				or seconds - memory.seconds > now - memory.wall + 3
		end
	end
	if seconds then
		memoryChecked = true
	end
	if fresh then
		memory = { parts = {} }
		settings.runMemory = memory
	end
	if seconds then
		memory.seconds, memory.wall, memory.zone = seconds, now, zone
	end
	memory.parts[part] = memory.parts[part] or {}
	return memory.parts[part]
end

-- A quick fade between two looks, for hover effects: frame.fade runs from 0
-- (at rest) to 1 (hovered) in FADE_TIME, and paint(frame, fade) draws each
-- step, eased. SurvivorUI_Fade(frame, 1, paint) on enter, (frame, 0) on leave.
local FADE_TIME = 0.15
local fading = {}
local fader = CreateFrame("Frame")
fader:Hide()
fader:SetScript("OnUpdate", function()
	local step = arg1 / FADE_TIME
	local any = false
	for frame in pairs(fading) do
		local fade, target = frame.fade or 0, frame.fadeTarget or 0
		if fade < target then
			fade = math.min(target, fade + step)
		else
			fade = math.max(target, fade - step)
		end
		frame.fade = fade
		frame.fadePaint(frame, fade * fade * (3 - 2 * fade))
		if fade == target then
			fading[frame] = nil
		else
			any = true
		end
	end
	if not any then
		this:Hide()
	end
end)

function SurvivorUI_Fade(frame, target, paint)
	frame.fadeTarget = target
	frame.fadePaint = paint or frame.fadePaint
	if frame.fadePaint and (frame.fade or 0) ~= target then
		fading[frame] = true
		fader:Show()
	end
end

-- A whole number as a Roman numeral, as the game writes ranks: 12 is XII.
local ROMAN = {
	{ 100, "C" }, { 90, "XC" }, { 50, "L" }, { 40, "XL" }, { 10, "X" }, { 9, "IX" },
	{ 5, "V" }, { 4, "IV" }, { 1, "I" },
}

function SurvivorUI_Roman(number)
	local text = ""
	number = math.floor(number or 0)
	for index = 1, table.getn(ROMAN) do
		local value, letters = ROMAN[index][1], ROMAN[index][2]
		while number >= value do
			text = text..letters
			number = number - value
		end
	end
	return text
end

-- The + and - of a fold button, drawn as two flat bars rather than typed: a
-- typed + sits off the middle of its box by a pixel or two, drawn bars on
-- the exact middle. SurvivorUI_PlusMinus(button, 8) makes them,
-- SurvivorUI_SetPlus(button, true) shows a +, false a -.
function SurvivorUI_PlusMinus(button, length)
	length = length or 8
	button.plusAcross = button:CreateTexture(nil, "OVERLAY")
	button.plusAcross:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	button.plusAcross:SetWidth(length)
	button.plusAcross:SetHeight(2)
	button.plusAcross:SetPoint("CENTER", button, "CENTER", 0, 0)
	button.plusDown = button:CreateTexture(nil, "OVERLAY")
	button.plusDown:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	button.plusDown:SetWidth(2)
	button.plusDown:SetHeight(length)
	button.plusDown:SetPoint("CENTER", button, "CENTER", 0, 0)
end

function SurvivorUI_SetPlus(button, plus)
	if plus then
		button.plusDown:Show()
	else
		button.plusDown:Hide()
	end
end

function SurvivorUI_TintPlus(button, r, g, b)
	button.plusAcross:SetVertexColor(r, g, b, 1)
	button.plusDown:SetVertexColor(r, g, b, 1)
end

-- A change that shows fully only after a reload asks for one: Reload now, or
-- Later.
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["SURVIVORUI_RELOAD"] = {
	text = "Survivor UI: %s\n\nReload the interface now?",
	button1 = "Reload",
	button2 = "Later",
	OnAccept = function() ReloadUI() end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

function SurvivorUI_AskReload(reason)
	if not StaticPopup_Show then
		return
	end
	local popup = StaticPopup_Show("SURVIVORUI_RELOAD", reason)
	-- Above the options window, which stands in the same stratum.
	if popup and popup.SetFrameStrata then
		popup:SetFrameStrata("FULLSCREEN_DIALOG")
	end
end

-- 1.12 paints shamans in the paladin's pink; they wear their modern blue here.
local CLASS_OVERRIDES = {
	SHAMAN = { r = 0.00, g = 0.44, b = 0.87 },
}

local POWER_COLORS = {
	[0] = { 0.25, 0.50, 1.00 },   -- mana
	[1] = { 0.85, 0.20, 0.20 },   -- rage
	[2] = { 1.00, 0.55, 0.15 },   -- focus
	[3] = { 1.00, 0.90, 0.25 },   -- energy
}

------------------------------------------------------------------------------
-- Pieces

-- A thin black border: a flat texture one pixel larger than the frame.
local function AddBorder(frame)
	local border = frame:CreateTexture(nil, "BACKGROUND")
	border:SetTexture(FLAT)
	border:SetVertexColor(0, 0, 0, 1)
	border:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
	return border
end

local function AddBacking(frame, layer)
	local backing = frame:CreateTexture(nil, layer or "BORDER")
	backing:SetTexture(FLAT)
	backing:SetVertexColor(0.09, 0.09, 0.11, 1)
	backing:SetAllPoints(frame)
	return backing
end

local function FlatBar(parent, width, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetWidth(width)
	bar:SetHeight(height)
	bar:SetStatusBarTexture(FLAT)
	bar:SetMinMaxValues(0, 1)
	AddBorder(bar)
	AddBacking(bar)
	return bar
end

local function Text(parent, size, point, x, y)
	local text = parent:CreateFontString(nil, "OVERLAY")
	text:SetFont(FONT, size + FONT_BUMP, "OUTLINE")
	text:SetPoint(point, parent, point, x, y)
	return text
end

local function Hide(name)
	local object = getglobal(name)
	if object then
		object:Hide()
	end
end

-- 439K, 1.2M
local function Short(value)
	if value >= 1000000 then
		return string.format("%.1fM", value / 1000000)
	elseif value >= 10000 then
		return math.floor(value / 1000 + 0.5).."K"
	end
	return value
end

-- The player frame's health: with Short health numbers on, in thousands (or
-- millions) to a tenth from 1000 up: 1250 is 1.2k, 1260 is 1.3k, a tenth
-- going up only from its sixtieth part. Off, as Short above.
local function HealthText(value)
	if not Settings().unitShortHealth or value < 1000 then
		return Short(value)
	end
	local unit, suffix = 1000, "k"
	if value >= 1000000 then
		unit, suffix = 1000000, "m"
	end
	local tenths = math.floor(value / (unit / 10) + 0.4)
	local text = string.format("%.1f", tenths / 10)
	return (string.gsub(text, "%.0$", ""))..suffix
end

------------------------------------------------------------------------------
-- The row: the buttons' holder is the anchor everything else hangs from.

local row = CreateFrame("Frame", "SurvivorUIRow", UIParent)
row:SetWidth(table.getn(BAR_BUTTONS) * (BUTTON_SIZE + BUTTON_GAP) - BUTTON_GAP)
row:SetHeight(BUTTON_SIZE)
row:SetPoint("CENTER", UIParent, "CENTER", 0, -ROW_BELOW_CENTER)
row:SetMovable(true)
row:SetFrameStrata("LOW")

-- The buttons can run over several rows (Max abilities per row, /sui opt):
-- the row frame is the first row, which the unit frames line up with; the
-- rest hang under it, each centered. The block spans them all, so what sits
-- under the bar (the experience bar, the kills and gold box) sits under the
-- last row.
local block = CreateFrame("Frame", "SurvivorUIRowBlock", UIParent)
block:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
block:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
block:SetHeight(BUTTON_SIZE)

-- The buttons the bar shows, in order: all of BAR_BUTTONS, less the racial's
-- when Display Racial is off (BuildList.lua finds which button holds it).
-- Worked out again in SizeRows.
local shownButtons = BAR_BUTTONS

local function ShownButtons()
	local racial = Settings().showRacial == false and SurvivorUI_RacialSlot and SurvivorUI_RacialSlot()
	local shown = {}
	for position = 1, table.getn(BAR_BUTTONS) do
		if BAR_BUTTONS[position] ~= racial then
			table.insert(shown, BAR_BUTTONS[position])
		end
	end
	return shown
end

local function BarPerRow()
	local count = table.getn(shownButtons)
	return math.max(1, math.min(count, tonumber(Settings().barPerRow) or count))
end

-- A button's place by its position in the bar: its offset from the row's top
-- middle, row after row, each row centered.
local function SlotOffset(position)
	local count, perRow = table.getn(shownButtons), BarPerRow()
	local line = math.floor((position - 1) / perRow)
	local column = math.mod(position - 1, perRow)
	local inLine = math.min(perRow, count - line * perRow)
	local width = inLine * (BUTTON_SIZE + BUTTON_GAP) - BUTTON_GAP
	return -width / 2 + column * (BUTTON_SIZE + BUTTON_GAP), -line * (BUTTON_SIZE + BUTTON_GAP)
end

-- A dark, bordered slot behind every button, so an empty one still reads as a
-- slot. These are frames of the row, not textures of the buttons: a texture
-- added to a button's own background layer draws over its icon.
local slots = {}
for position = 1, table.getn(BAR_BUTTONS) do
	local slot = CreateFrame("Frame", nil, row)
	slot:SetWidth(BUTTON_SIZE)
	slot:SetHeight(BUTTON_SIZE)
	AddBorder(slot)
	AddBacking(slot)
	slots[position] = slot
end

-- The row as wide as its first line, the block as tall as all of them, and
-- the slots in their places (the buttons follow in LayoutBar).
local function SizeRows()
	shownButtons = ShownButtons()
	local count, perRow = table.getn(shownButtons), BarPerRow()
	local lines = math.ceil(count / perRow)
	row:SetWidth(math.min(perRow, count) * (BUTTON_SIZE + BUTTON_GAP) - BUTTON_GAP)
	block:SetHeight(lines * (BUTTON_SIZE + BUTTON_GAP) - BUTTON_GAP)
	for position = 1, table.getn(BAR_BUTTONS) do
		if position <= count then
			local x, y = SlotOffset(position)
			slots[position]:ClearAllPoints()
			slots[position]:SetPoint("TOPLEFT", row, "TOP", x, y)
			slots[position]:Show()
		else
			slots[position]:Hide()
		end
	end
end
SizeRows()

------------------------------------------------------------------------------
-- Unit frames

local function HealthColor(unit)
	-- Players wear their class color; everything else on the field is an enemy.
	if UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		local color = class and (CLASS_OVERRIDES[class] or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
		if color then
			return color.r, color.g, color.b
		end
		return 0.6, 0.6, 0.6
	end
	return ENEMY[1], ENEMY[2], ENEMY[3]
end

-- Each unit frame's place: an anchor of its own, which the addon's frame and the
-- stock one (whichever style is on) both sit centered on. It is as large as the
-- frame showing, so its edit-mode handle covers it. Until moved, it sits beside the
-- buttons and follows the row; once moved, its center is kept.
local function UnitAnchor(name, side, xKey, yKey)
	local anchor = CreateFrame("Frame", name, UIParent)
	anchor:SetWidth(FRAME_WIDTH + 1 + BUTTON_SIZE)
	anchor:SetHeight(BUTTON_SIZE)
	anchor:SetMovable(true)
	if anchor.SetClampedToScreen then
		anchor:SetClampedToScreen(true)
	end
	anchor.side, anchor.xKey, anchor.yKey = side, xKey, yKey
	return anchor
end

local function RestoreAnchor(anchor)
	local settings = Settings()
	anchor:ClearAllPoints()
	if settings[anchor.xKey] then
		anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", settings[anchor.xKey], settings[anchor.yKey])
	elseif anchor.side == "LEFT" then
		anchor:SetPoint("RIGHT", row, "LEFT", -SECTION_GAP, 0)
	else
		anchor:SetPoint("LEFT", row, "RIGHT", SECTION_GAP, 0)
	end
end

local function SaveAnchor(anchor)
	local x, y = anchor:GetCenter()
	if not x then
		return
	end
	local settings = Settings()
	settings[anchor.xKey] = math.floor(x + 0.5)
	settings[anchor.yKey] = math.floor(y + 0.5)
	RestoreAnchor(anchor)
end

local playerAnchor = UnitAnchor("SurvivorUIPlayerAnchor", "LEFT", "playerX", "playerY")
local targetAnchor = UnitAnchor("SurvivorUITargetAnchor", "RIGHT", "targetX", "targetY")
RestoreAnchor(playerAnchor)
RestoreAnchor(targetAnchor)

-- side: "LEFT" is the player's frame, its portrait on the far left; "RIGHT"
-- mirrors it.
local function UnitFrame(unit, name, anchor, side, dropdown)
	local left = side == "LEFT"

	local frame = CreateFrame("Button", name, UIParent)
	frame:SetWidth(FRAME_WIDTH + 1 + BUTTON_SIZE)
	frame:SetHeight(BUTTON_SIZE)
	frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
	frame.unit = unit

	frame.portrait = CreateFrame("Frame", nil, frame)
	frame.portrait:SetWidth(BUTTON_SIZE)
	frame.portrait:SetHeight(BUTTON_SIZE)
	frame.portrait:SetPoint(left and "LEFT" or "RIGHT", frame, left and "LEFT" or "RIGHT", 0, 0)
	AddBorder(frame.portrait)
	AddBacking(frame.portrait)
	frame.portrait.texture = frame.portrait:CreateTexture(nil, "ARTWORK")
	frame.portrait.texture:SetAllPoints(frame.portrait)
	-- The stock portrait is a disc; cropped in, it fills the square.
	frame.portrait.texture:SetTexCoord(0.15, 0.85, 0.15, 0.85)

	frame.health = FlatBar(frame, FRAME_WIDTH, HEALTH_HEIGHT)
	frame.health:SetPoint(left and "TOPRIGHT" or "TOPLEFT", frame, left and "TOPRIGHT" or "TOPLEFT", 0, 0)

	frame.power = FlatBar(frame, FRAME_WIDTH, POWER_HEIGHT)
	frame.power:SetPoint("TOP", frame.health, "BOTTOM", 0, -1)

	frame.name = Text(frame.health, 10, "LEFT", 5, 0)
	-- The player's health reads "524 | 100%", a target's only "67%": the target's
	-- name gets the room the numbers leave.
	frame.nameRoom = unit == "player" and FRAME_WIDTH - 82 or FRAME_WIDTH - 44
	frame.name:SetWidth(frame.nameRoom)
	frame.name:SetHeight(12)
	frame.name:SetJustifyH("LEFT")
	frame.name:SetTextColor(1, 1, 1)

	frame.value = Text(frame.health, 10, "RIGHT", -5, 0)
	frame.value:SetTextColor(1, 1, 1)

	-- Left click targets, right click opens the stock menu. Edit mode shows the
	-- frame's own handle over it, to move it.
	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	frame:SetScript("OnClick", function()
		if arg1 == "RightButton" and dropdown and getglobal(dropdown) then
			ToggleDropDownMenu(1, nil, getglobal(dropdown), "cursor")
		else
			TargetUnit(this.unit)
		end
	end)
	return frame
end

local function UpdatePortrait(frame)
	if UnitExists(frame.unit) then
		SetPortraitTexture(frame.portrait.texture, frame.unit)
	end
end

local function UpdateUnitFrame(frame)
	local unit = frame.unit
	if not UnitExists(unit) then
		-- In preview an empty target frame stands in, to be placed.
		if SurvivorUI_Preview() then
			frame.shownName = nil
			frame.name:SetText("Target")
			frame.value:SetText("")
			frame.health:SetValue(1)
			frame.health:SetStatusBarColor(ENEMY[1], ENEMY[2], ENEMY[3], 1)
			frame.power:SetValue(0)
			frame.portrait.texture:SetTexture(nil)
			frame:Show()
			return
		end
		frame:Hide()
		return
	end
	frame:Show()

	local health, healthMax = UnitHealth(unit), UnitHealthMax(unit)
	local share = healthMax > 0 and health / healthMax or 0
	local percent = math.floor(share * 100 + 0.5)
	local r, g, b = HealthColor(unit)
	frame.health:SetValue(share)
	frame.health:SetStatusBarColor(r, g, b, 1)
	-- A name too long for its room goes by its first word, not cut short.
	local name = UnitName(unit) or ""
	if name ~= frame.shownName then
		frame.shownName = name
		frame.name:SetWidth(0)
		frame.name:SetText(name)
		if frame.name:GetStringWidth() > frame.nameRoom then
			local _, _, first = string.find(name, "^(%S+)")
			frame.name:SetText(first or name)
		end
		frame.name:SetWidth(frame.nameRoom)
	end

	-- The health on the bar's right, as the two switches under Unit frames
	-- have it: the value, the percentage, both ("524 | 100%") or neither.
	local showValue = Settings().unitHealthValue ~= false
	local showPercent = Settings().unitHealthPercent ~= false
	if UnitIsDead(unit) or UnitIsGhost(unit) then
		frame.value:SetText("Dead")
	elseif unit ~= "player" then
		-- An enemy's frame keeps to the percentage; its nameplate has the numbers.
		frame.value:SetText(showPercent and percent.."%" or "")
	elseif showValue and showPercent then
		frame.value:SetText(HealthText(health).." | "..percent.."%")
	elseif showValue then
		frame.value:SetText(HealthText(health))
	elseif showPercent then
		frame.value:SetText(percent.."%")
	else
		frame.value:SetText("")
	end

	local power, powerMax = UnitMana(unit), UnitManaMax(unit)
	if powerMax > 0 then
		local color = POWER_COLORS[UnitPowerType(unit)] or POWER_COLORS[0]
		frame.power:SetValue(power / powerMax)
		frame.power:SetStatusBarColor(color[1], color[2], color[3], 1)
	else
		frame.power:SetValue(0)
	end
end

local player = UnitFrame("player", "SurvivorUIPlayer", playerAnchor, "LEFT", "PlayerFrameDropDown")
local target = UnitFrame("target", "SurvivorUITarget", targetAnchor, "RIGHT", "TargetFrameDropDown")

-- The target's debuffs, in a row above its frame. Hover one for the game's
-- own tooltip of it: what it does, a damage over time's damage and ticks.
local DEBUFFS = 8
local debuffs = {}

local function DebuffEnter()
	GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:SetUnitDebuff("target", this.index)
	GameTooltip:Show()
end

for index = 1, DEBUFFS do
	local icon = CreateFrame("Frame", nil, target)
	icon.index = index
	icon:EnableMouse(true)
	icon:SetScript("OnEnter", DebuffEnter)
	icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	icon:SetWidth(18)
	icon:SetHeight(18)
	icon:SetPoint("BOTTOMLEFT", target, "TOPLEFT", (index - 1) * 21, 4)
	AddBorder(icon)

	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetAllPoints(icon)
	icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	icon.count = Text(icon, 9, "BOTTOMRIGHT", -1, 1)
	icon:Hide()
	debuffs[index] = icon
end

local function UpdateDebuffs()
	for index = 1, DEBUFFS do
		local texture, count = UnitDebuff("target", index)
		local icon = debuffs[index]
		if texture then
			icon.texture:SetTexture(texture)
			icon.count:SetText(count and count > 1 and count or "")
			icon:Show()
		else
			icon:Hide()
		end
	end
end

-- The addon's own unit frames (on), or the game's stock ones in their places
-- (off): /sui opt, "Unit frames".
local function Styled()
	return Settings().unitStyle ~= false
end

local elapsed = 0
local unitUpdater = CreateFrame("Frame")
unitUpdater:SetScript("OnUpdate", function()
	elapsed = elapsed + arg1
	if elapsed < 0.05 then
		return
	end
	elapsed = 0
	if not Styled() then
		return
	end
	UpdateUnitFrame(player)
	UpdateUnitFrame(target)
	if UnitExists("target") then
		UpdateDebuffs()
	end
end)

-- The stock player and target frames are put away by hanging them from a
-- hidden frame: out of sight, yet left to run as the stock code expects, so
-- they come back current. Switched back, they hang from the interface again,
-- fully shown, centered on the same places the addon's frames use.
local stockAway = CreateFrame("Frame")
stockAway:Hide()

local STOCK = {
	{ custom = player, anchor = playerAnchor, name = "PlayerFrame" },
	{ custom = target, anchor = targetAnchor, name = "TargetFrame" },
}

local function ApplyUnitStyle()
	local styled = Styled()
	for _, entry in pairs(STOCK) do
		local stock = getglobal(entry.name)
		if styled then
			if stock then
				stock:SetParent(stockAway)
			end
		else
			entry.custom:Hide()
			if stock then
				stock:SetParent(UIParent)
				stock:SetAlpha(1)
				stock:ClearAllPoints()
				stock:SetPoint("CENTER", entry.anchor, "CENTER", 0, 0)
				-- The player's is always up; the target's with a target, as the
				-- stock code would have it.
				if entry.name == "PlayerFrame" or UnitExists("target") then
					stock:Show()
				else
					stock:Hide()
				end
			end
		end
	end
end

-- The unit frames' size, as a share of their own (100 is as drawn). The target's
-- debuffs and the player's buffs follow them; each anchor is resized to the
-- scaled frame, so its edit-mode handle covers it.
local UNIT_SCALE = 100
local UNIT_SCALE_MIN, UNIT_SCALE_MAX = 50, 200

local function UnitScale()
	local scale = tonumber(Settings().unitScale) or UNIT_SCALE
	return math.max(UNIT_SCALE_MIN, math.min(UNIT_SCALE_MAX, scale))
end

-- The size applies to whichever frames show, the addon's or the stock ones;
-- each anchor takes the shown frame's scaled size, for its edit-mode handle.
local function ApplyUnitScale()
	local scale = UnitScale() / 100
	local styled = Styled()
	for _, entry in pairs(STOCK) do
		local frame = entry.custom
		frame:SetScale(scale)
		local shown = frame
		local stock = getglobal(entry.name)
		if stock then
			stock:SetScale(scale)
			if not styled then
				shown = stock
			end
		end
		entry.anchor:SetWidth(shown:GetWidth() * scale)
		entry.anchor:SetHeight(shown:GetHeight() * scale)
	end
end

-- The unit frames' shape, before the scale: the width of the bars and the
-- height of the whole frame. The portrait stays square at the frame's height;
-- the health bar takes the height the power bar leaves.
local UNIT_WIDTH_MIN, UNIT_WIDTH_MAX = 100, 300
local UNIT_HEIGHT_MIN, UNIT_HEIGHT_MAX = 20, 60

local function UnitWidth()
	return math.max(UNIT_WIDTH_MIN, math.min(UNIT_WIDTH_MAX, tonumber(Settings().unitWidth) or FRAME_WIDTH))
end

local function UnitHeight()
	return math.max(UNIT_HEIGHT_MIN, math.min(UNIT_HEIGHT_MAX, tonumber(Settings().unitHeight) or BUTTON_SIZE))
end

local function ApplyUnitSize()
	local width, height = UnitWidth(), UnitHeight()
	for _, frame in pairs({ player, target }) do
		frame:SetWidth(width + 1 + height)
		frame:SetHeight(height)
		frame.portrait:SetWidth(height)
		frame.portrait:SetHeight(height)
		frame.health:SetWidth(width)
		frame.health:SetHeight(height - POWER_HEIGHT - 1)
		frame.power:SetWidth(width)
		-- The player's name leaves room for "524 | 100%", a target's for "67%".
		frame.nameRoom = frame.unit == "player" and width - 82 or width - 44
		frame.name:SetWidth(frame.nameRoom)
		frame.shownName = nil
	end
	ApplyUnitScale()
end

function SurvivorUI_ToggleUnitStyle()
	local settings = Settings()
	settings.unitStyle = not Styled()
	ApplyUnitStyle()
	ApplyUnitSize()
	DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: "..(settings.unitStyle
		and "the addon's flat unit frames."
		or "the game's own unit frames, in the same places, still moved in edit mode (tap Alt)."))
	-- The game's frames do not all come back by themselves until a reload.
	SurvivorUI_AskReload(settings.unitStyle and "the addon's unit frames are on."
		or "the game's own unit frames are back.")
end

SurvivorUI_RegisterOption({
	section = "Unit frames",
	label = "Unit frames",
	tip = "The addon's flat player and target frames. Off, the game's own frames show instead, in the same places, still moved in edit mode (tap Alt) and sized by the slider below.",
	command = "/sui frames",
	get = Styled,
	toggle = SurvivorUI_ToggleUnitStyle,
})

SurvivorUI_RegisterOption({
	section = "Unit frames",
	kind = "slider",
	label = "Unit frame size (%)",
	parent = "Unit frames",
	tip = "The size of the player and target frames, from half to twice their own.",
	min = UNIT_SCALE_MIN,
	max = UNIT_SCALE_MAX,
	step = 5,
	get = UnitScale,
	set = function(value)
		Settings().unitScale = value
		ApplyUnitScale()
	end,
})

SurvivorUI_RegisterOption({
	section = "Unit frames",
	kind = "slider",
	label = "Unit frame width",
	parent = "Unit frames",
	tip = "The width of the player and target frames' bars, in pixels before the size above.",
	min = UNIT_WIDTH_MIN,
	max = UNIT_WIDTH_MAX,
	step = 5,
	get = UnitWidth,
	set = function(value)
		Settings().unitWidth = value
		ApplyUnitSize()
	end,
})

SurvivorUI_RegisterOption({
	section = "Unit frames",
	kind = "slider",
	label = "Unit frame height",
	parent = "Unit frames",
	tip = "The height of the player and target frames, portrait included, in pixels before the size above.",
	min = UNIT_HEIGHT_MIN,
	max = UNIT_HEIGHT_MAX,
	step = 1,
	get = UnitHeight,
	set = function(value)
		Settings().unitHeight = value
		ApplyUnitSize()
	end,
})

SurvivorUI_RegisterOption({
	section = "Unit frames",
	label = "Show Health Value",
	parent = "Unit frames",
	tip = "Your health as a number on the right of your health bar (\"882\"). With Show Health % on too, both: \"882 | 100%\".",
	get = function() return Settings().unitHealthValue ~= false end,
	toggle = function()
		local settings = Settings()
		settings.unitHealthValue = settings.unitHealthValue == false
	end,
})

SurvivorUI_RegisterOption({
	section = "Unit frames",
	label = "Show Health %",
	parent = "Unit frames",
	tip = "Health as a percentage on the right of the health bar (\"100%\"), on your frame and your target's.",
	get = function() return Settings().unitHealthPercent ~= false end,
	toggle = function()
		local settings = Settings()
		settings.unitHealthPercent = settings.unitHealthPercent == false
	end,
})

SurvivorUI_RegisterOption({
	section = "Unit frames",
	label = "Short health numbers",
	parent = "Unit frames",
	tip = "Your health in thousands from 1000 up: 1250 reads 1.2k, 1260 reads 1.3k (a tenth goes up only from its sixtieth part).",
	get = function() return Settings().unitShortHealth == true end,
	toggle = function()
		local settings = Settings()
		settings.unitShortHealth = not settings.unitShortHealth
	end,
})

------------------------------------------------------------------------------
-- Action bar

-- Flat look: no rounded slot art and a cropped icon; the row's slot behind it
-- supplies the border.
local function StyleButton(button)
	local name = button:GetName()
	if not name then
		return
	end

	local normal = getglobal(name.."NormalTexture")
	if normal then
		normal:SetAlpha(0)
	end

	local icon = getglobal(name.."Icon")
	if icon then
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end

	if not button.survivorStyled then
		button.survivorStyled = true

		-- No key labels: the spells cast themselves. Made clear rather than hidden,
		-- since the stock code shows and fills them again on its own.
		local hotkey = getglobal(name.."HotKey")
		if hotkey then
			hotkey:SetAlpha(0)
		end
	end
end

-- The stock update puts the rounded slot art back; take it off again each time.
local stockActionButtonUpdate = ActionButton_Update
if stockActionButtonUpdate then
	ActionButton_Update = function()
		stockActionButtonUpdate()
		if this and this.survivorKept then
			StyleButton(this)
		end
	end
end

-- The stock code tints a button it calls unusable blue-grey (the "not enough
-- mana" look), and the game calls a spell unusable while it cools down. The
-- addon's buttons keep their own colors instead: the sweep and the count say
-- when a spell is cooling down, as on the buffs.
local stockUpdateUsable = ActionButton_UpdateUsable
if stockUpdateUsable then
	ActionButton_UpdateUsable = function()
		stockUpdateUsable()
		if this and this.survivorKept and this.GetName then
			local icon = getglobal(this:GetName().."Icon")
			if icon then
				icon:SetVertexColor(1, 1, 1)
			end
			local normal = getglobal(this:GetName().."NormalTexture")
			if normal then
				normal:SetVertexColor(1, 1, 1)
			end
		end
	end
end

local BAR_STRATA = "HIGH"

local function PlaceButton(prefix, id, position)
	local button = getglobal(prefix..id)
	if not button then
		return
	end

	button:ClearAllPoints()
	if position then
		local x, y = SlotOffset(position)
		button:SetPoint("TOPLEFT", row, "TOP", x, y)
		button.survivorKept = true
		-- Above what the game draws over the field (nameplates among it), so
		-- the mouse always reaches the button and its tooltip; the options
		-- window, the Codex and the tooltips stand higher still. Its
		-- cooldown sweep and numbers come with it.
		button:SetFrameStrata(BAR_STRATA)
		StyleButton(button)
	else
		-- Off screen rather than hidden: the stock code shows buttons on its own.
		button:SetPoint("TOP", UIParent, "BOTTOM", 0, -600)
	end
end

local function LayoutBar()
	local positions = {}
	for position = 1, table.getn(shownButtons) do
		positions[shownButtons[position]] = position
	end

	-- A stance bar's buttons, when a class has one, sit where the main bar's do.
	for id = 1, 12 do
		PlaceButton("ActionButton", id, positions[id])
		PlaceButton("BonusActionButton", id, positions[id])
	end

	for _, name in pairs({
		"MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
		"MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
		"ActionBarUpButton", "ActionBarDownButton", "MainMenuBarPageNumber",
		"MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
		"KeyRingButton", "MainMenuBarPerformanceBarFrame",
		"BonusActionBarTexture0", "BonusActionBarTexture1",
		"MainMenuXPBarTexture0", "MainMenuXPBarTexture1", "MainMenuXPBarTexture2", "MainMenuXPBarTexture3",
		"ExhaustionTick",
	}) do
		Hide(name)
	end

	-- The experience bar: a thin flat strip under the whole row (the last of
	-- its lines).
	local xp = getglobal("MainMenuExpBar")
	if xp then
		xp:ClearAllPoints()
		xp:SetPoint("TOP", block, "BOTTOM", 0, -5)
		xp:SetWidth(row:GetWidth() + 2 * (SECTION_GAP + FRAME_WIDTH + 1 + BUTTON_SIZE))
		xp:SetHeight(4)
		xp:SetStatusBarTexture(FLAT)
		if not xp.survivorBorder then
			xp.survivorBorder = AddBorder(xp)
			xp.survivorBack = AddBacking(xp)
		end
	end
end

function SurvivorUI_SetBarPerRow(count)
	Settings().barPerRow = count
	SizeRows()
	LayoutBar()
end

-- Display Racial: off, the racial's button leaves the bar and the rest close
-- up. Which button holds it can change (a run's spells arrive, a button is
-- swapped), so it is looked for again every second.
SurvivorUI_RegisterOption({
	section = "Ability Bar",
	label = "Display Racial",
	tip = "Your racial ability's button on the ability bar. Off, it is left out and the other buttons close up.",
	get = function() return Settings().showRacial ~= false end,
	toggle = function()
		Settings().showRacial = Settings().showRacial == false
		SizeRows()
		LayoutBar()
	end,
})

local racialWatch = CreateFrame("Frame")
racialWatch.elapsed = 0
racialWatch:SetScript("OnUpdate", function()
	this.elapsed = this.elapsed + arg1
	if this.elapsed < 1 then
		return
	end
	this.elapsed = 0
	if table.concat(ShownButtons(), ",") ~= table.concat(shownButtons, ",") then
		SizeRows()
		LayoutBar()
	end
end)

SurvivorUI_RegisterOption({
	section = "Ability Bar",
	kind = "slider",
	label = "Max abilities per row",
	tip = "How many action buttons stand side by side. Set it lower and the buttons past it move down to a new row under the first, centered, and so on; what sits under the bar moves down with them.",
	min = 1,
	max = table.getn(BAR_BUTTONS),
	step = 1,
	get = BarPerRow,
	set = SurvivorUI_SetBarPerRow,
})

------------------------------------------------------------------------------
-- The hero's buffs and debuffs, in a row above the player frame, each with
-- its time left and its stacks. Right click a buff to cancel it. The row grows
-- from its center outward, and its icons take the size set in /sui opt. It
-- follows the player frame until it is moved on its own: in edit mode (tap Alt), drag it
-- (/sui layout puts it back).

local AURA_SIZE = 22            -- the size until one is chosen
local AURA_SIZE_MIN, AURA_SIZE_MAX = 16, 40
local AURA_GAP = 3
local AURA_MAX = 12

local function AuraSize()
	local size = tonumber(Settings().buffSize) or AURA_SIZE
	return math.max(AURA_SIZE_MIN, math.min(AURA_SIZE_MAX, size))
end

local auraHolder = CreateFrame("Frame", "SurvivorUIBuffs", UIParent)
auraHolder:SetWidth(AURA_MAX * (AURA_SIZE + AURA_GAP) - AURA_GAP)
auraHolder:SetHeight(AURA_SIZE)
auraHolder:SetFrameStrata("LOW")
auraHolder:SetMovable(true)
if auraHolder.SetClampedToScreen then
	auraHolder:SetClampedToScreen(true)
end

-- Its place is kept by its bottom middle, the point the row grows from.
local function SaveAuraPlace()
	local settings = Settings()
	local x = auraHolder:GetCenter()
	settings.buffX = math.floor(x + 0.5)
	settings.buffBottom = math.floor(auraHolder:GetBottom() + 0.5)
	auraHolder:ClearAllPoints()
	auraHolder:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", settings.buffX, settings.buffBottom)
end

-- The saved place, or centered just above the player frame, following it.
local function RestoreAuraPlace()
	local settings = Settings()
	auraHolder:ClearAllPoints()
	if settings.buffX then
		auraHolder:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", settings.buffX, settings.buffBottom)
	else
		auraHolder:SetPoint("BOTTOM", player, "TOP", 0, 5)
	end
end
auraHolder:ClearAllPoints()
auraHolder:SetPoint("BOTTOM", player, "TOP", 0, 5)

local function TimeText(seconds)
	if seconds >= 3600 then
		return math.floor(seconds / 3600 + 0.5).."h"
	elseif seconds >= 60 then
		return math.floor(seconds / 60 + 0.5).."m"
	elseif seconds >= 10 then
		return math.floor(seconds)
	end
	return string.format("%.1f", seconds)
end

local auras = {}
for index = 1, AURA_MAX do
	local aura = CreateFrame("Button", nil, auraHolder)
	aura:SetWidth(AURA_SIZE)
	aura:SetHeight(AURA_SIZE)
	aura.border = AddBorder(aura)

	aura.texture = aura:CreateTexture(nil, "ARTWORK")
	aura.texture:SetAllPoints(aura)
	aura.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	-- The clock sweep: the stock cooldown model, made at the 36 pixels of an
	-- action button it is drawn for and scaled down to the icon. It runs
	-- backwards here: an action button's sweep clears as the spell comes
	-- ready, a buff's darkens as its time runs out, so the two never read
	-- alike. The model's one sequence is a second long, its time set from the
	-- share of the buff still left.
	aura.sweep = CreateFrame("Model", nil, aura, "CooldownFrameTemplate")
	aura.sweep:SetWidth(36)
	aura.sweep:SetHeight(36)
	aura.sweep:SetScale(AURA_SIZE / 36)
	aura.sweep:SetPoint("CENTER", aura, "CENTER", 0, 0)
	aura.sweep:SetScript("OnUpdateModel", function()
		if not (this.expires and this.duration and this.duration > 0) then
			return
		end
		local left = (this.expires - GetTime()) / this.duration
		this:SetSequenceTime(0, math.max(0, math.min(0.999, left)) * 1000)
	end)
	aura.sweep:SetScript("OnAnimFinished", nil)
	aura.sweep:Hide()

	-- The time and stacks above the sweep, so it never darkens them. A frame
	-- level above it was not enough: a long buff's sweep stays mostly dark for
	-- minutes and its number disappeared under it. A stratum above the row is.
	aura.overlay = CreateFrame("Frame", nil, aura)
	aura.overlay:SetAllPoints(aura)
	aura.overlay:SetFrameStrata("MEDIUM")
	aura.overlay:SetFrameLevel(aura.sweep:GetFrameLevel() + 3)

	aura.time = Text(aura.overlay, 10, "CENTER", 0, 0)
	aura.time:SetTextColor(1, 0.95, 0.6)
	aura.count = Text(aura.overlay, 9, "BOTTOMRIGHT", -1, 1)

	aura:RegisterForClicks("RightButtonUp")
	aura:SetScript("OnClick", function() if this.helpful then CancelPlayerBuff(this.buffIndex) end end)
	aura:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
		GameTooltip:SetPlayerBuff(this.buffIndex)
	end)
	aura:SetScript("OnLeave", function() GameTooltip:Hide() end)
	aura:Hide()
	auras[index] = aura
end

-- Every icon, its sweep and its type at the chosen size; the holder as wide
-- as a full row of them, so its edit-mode handle shows where the row can reach.
local auraLaidOut                -- "size:count" of the last layout
local function ApplyAuraSize()
	local size = AuraSize()
	auraHolder:SetWidth(AURA_MAX * (size + AURA_GAP) - AURA_GAP)
	auraHolder:SetHeight(size)
	local timeSize = math.max(8, math.floor(size * 0.45 + 0.5))
	local countSize = math.max(7, math.floor(size * 0.4 + 0.5))
	for index = 1, AURA_MAX do
		local aura = auras[index]
		aura:SetWidth(size)
		aura:SetHeight(size)
		aura.sweep:SetScale(size / 36)
		aura.time:SetFont(FONT, timeSize + FONT_BUMP, "OUTLINE")
		aura.count:SetFont(FONT, countSize + FONT_BUMP, "OUTLINE")
	end
	auraLaidOut = nil
end

-- The shown icons centered on the holder: the row grows from the middle.
local function LayoutAuras(shown)
	local size = AuraSize()
	local key = size..":"..shown
	if auraLaidOut == key then
		return
	end
	auraLaidOut = key
	local step = size + AURA_GAP
	local left = -(shown * step - AURA_GAP) / 2
	for index = 1, shown do
		local aura = auras[index]
		aura:ClearAllPoints()
		aura:SetPoint("BOTTOMLEFT", auraHolder, "BOTTOM", left + (index - 1) * step, 0)
	end
end

function SurvivorUI_SetAuraSize(size)
	Settings().buffSize = math.max(AURA_SIZE_MIN, math.min(AURA_SIZE_MAX, math.floor((tonumber(size) or AURA_SIZE) + 0.5)))
	ApplyAuraSize()
end

SurvivorUI_RegisterOption({
	section = "Ability Bar",
	kind = "slider",
	label = "Buff icon size",
	tip = "The size of your buff and debuff icons above the player frame, in pixels.",
	min = AURA_SIZE_MIN,
	max = AURA_SIZE_MAX,
	step = 1,
	get = AuraSize,
	set = SurvivorUI_SetAuraSize,
})

-- The game tells only the seconds an aura has left, not its full length. The
-- length is learned instead: the time left when it is first seen, or when it
-- comes back up on a refresh. Keyed by its icon and kind.
local auraLength = {}           -- [key] = seconds it lasts
local auraLastLeft = {}         -- [key] = seconds it had left last time

-- Runs the sweep from when the aura ends and how long it lasts, read by its
-- own OnUpdateModel (above). CooldownFrame_SetTimer is not used, as the
-- cooldown numbers below hang from it and would put a second count on the
-- icon. The sweep is set again only when the aura's timing really changes.
local function Sweep(aura, left, length)
	local sweep = aura.sweep
	if not (Settings().auraSweep and left and left > 0 and length and length > 0) then
		sweep:Hide()
		return
	end
	local expires = GetTime() + left
	if sweep:IsShown() and sweep.duration == length and math.abs((sweep.expires or 0) - expires) < 0.2 then
		return
	end
	sweep.expires, sweep.duration = expires, length
	sweep:SetSequence(0)
	sweep:Show()
end

-- A buff that lasts as long as it is kept up (a shield the game refreshes,
-- an aura) tells no real time left: 0, nothing, or an endless number. Those
-- stand still, with no time and no sweep; a shield shows what it has left to
-- absorb instead (ShieldLeft, in the absorb section below).
local PERMANENT = 86400         -- seconds; a time left this long is no timer
local ShieldLeft

-- 950, 1.2k, 12k
local function AbsorbText(value)
	if value >= 10000 then
		return math.floor(value / 1000 + 0.5).."k"
	elseif value >= 1000 then
		return (string.gsub(string.format("%.1f", value / 1000), "%.0$", "")).."k"
	end
	return math.floor(value)
end

-- The client does not know every buff's timer: some of the game's own come
-- with none (GetPlayerBuffTimeLeft gives 0), which is why the game also sends
-- its buffs to addons (AZS_BUFFS: spell id and seconds left). Such a buff is
-- matched to a spell of the game's list (AZS_SPELLS) by the name on its
-- tooltip, and its time read from there. The match is kept per icon; a buff
-- not found there is looked for again a few seconds later, as the list grows.
local buffScan = CreateFrame("GameTooltip", "SurvivorUIBuffScan", nil, "GameTooltipTemplate")
local NAME_KEYS = {
	["shadow word: pain"] = "sw_pain", ["power word: shield"] = "pw_shield",
	["demoralizing shout"] = "demo_shout", ["hunter's mark"] = "hunters_mark",
}
local BUFF_RETRY = 5
local buffSpell = {}            -- [icon] = { spell = id or nil, at = when looked up }

local function GameField(entry, name, index)
	if entry[name] ~= nil then
		return entry[name]
	end
	return entry[index]
end

local function SpellOfBuff(buffIndex, texture)
	local known = buffSpell[texture]
	if known and (known.spell or GetTime() - known.at < BUFF_RETRY) then
		return known.spell
	end
	local spell
	buffScan:SetOwner(WorldFrame, "ANCHOR_NONE")
	buffScan:ClearLines()
	buffScan:SetPlayerBuff(buffIndex)
	local line = getglobal("SurvivorUIBuffScanTextLeft1")
	local name = line and line:GetText()
	if name then
		local lower = string.lower(name)
		local key = NAME_KEYS[lower] or string.gsub(string.gsub(lower, "[^%a ]", ""), " ", "_")
		for index = 1, table.getn(AZS_SPELLS) do
			local entry = AZS_SPELLS[index]
			if GameField(entry, "key", 1) == key then
				spell = tonumber(GameField(entry, "spell", 2))
				break
			end
		end
	end
	buffSpell[texture] = { spell = spell, at = GetTime() }
	return spell
end

-- The seconds the game says the buff has left, counted down since its last
-- word while the run is playing; nil when it has nothing on it.
local function GameBuffLeft(buffIndex, texture)
	if not (AZS_BUFFS and AZS_SPELLS and texture) then
		return nil
	end
	local spell = SpellOfBuff(buffIndex, texture)
	if not spell then
		return nil
	end
	for index = 1, table.getn(AZS_BUFFS) do
		local entry = AZS_BUFFS[index]
		if tonumber(GameField(entry, "spell", 1)) == spell then
			local left = tonumber(GameField(entry, "left", 2)) or 0
			local playing = AZS_GetPhase and AZS_GetPhase() == "playing"
			if playing and AZS_BUFFS_UPDATED then
				left = left - (GetTime() - AZS_BUFFS_UPDATED)
			end
			return math.max(0, left)
		end
	end
end

local function UpdateAuras()
	local shown = 0
	local seen = {}
	for pass = 1, 2 do
		local filter = pass == 1 and "HELPFUL" or "HARMFUL"
		for slot = 0, 15 do
			local buffIndex = GetPlayerBuff(slot, filter)
			if buffIndex and buffIndex >= 0 and shown < AURA_MAX then
				shown = shown + 1
				local aura = auras[shown]
				local texture = GetPlayerBuffTexture(buffIndex)
				aura.buffIndex = buffIndex
				aura.helpful = pass == 1
				aura.texture:SetTexture(texture)

				-- A debuff wears a red border.
				if pass == 1 then
					aura.border:SetVertexColor(0, 0, 0, 1)
				else
					aura.border:SetVertexColor(0.85, 0.10, 0.10, 1)
				end

				local left = GetPlayerBuffTimeLeft(buffIndex)
				if pass == 1 and not (left and left > 0 and left < PERMANENT) then
					left = GameBuffLeft(buffIndex, texture)
				end
				-- No real timer (0, nothing, endless, or not a number): it stands still.
				if not (left and left == left and left > 0 and left < PERMANENT) then
					left = nil
				end
				-- A shield shows what it has left to absorb, timer or not (its
				-- sweep still runs down with the time); else the time left.
				local shield = pass == 1 and ShieldLeft and ShieldLeft(texture)
				if shield and shield > 0 then
					aura.time:SetText(AbsorbText(shield))
					aura.time:SetTextColor(0.75, 0.9, 1)
				elseif left then
					aura.time:SetText(TimeText(left))
					aura.time:SetTextColor(1, 0.95, 0.6)
				else
					aura.time:SetText("")
				end

				local key = filter..(texture or "")
				if left and left > 0 then
					local last = auraLastLeft[key]
					if not last or left > last + 0.3 or not auraLength[key] then
						auraLength[key] = left
					end
					auraLastLeft[key] = left
					seen[key] = true
				end
				Sweep(aura, left, auraLength[key])

				local count = GetPlayerBuffApplications(buffIndex)
				aura.count:SetText(count and count > 1 and count or "")
				aura:Show()
			end
		end
	end
	for index = shown + 1, AURA_MAX do
		auras[index]:Hide()
	end
	LayoutAuras(shown)
	-- An aura gone and cast again later learns its length afresh.
	for key in pairs(auraLastLeft) do
		if not seen[key] then
			auraLastLeft[key] = nil
		end
	end
end

function SurvivorUI_ToggleAuraSweep()
	local settings = Settings()
	settings.auraSweep = not settings.auraSweep
	DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: buff sweep "..(settings.auraSweep and "on." or "off."))
end

SurvivorUI_RegisterOption({
	section = "Ability Bar",
	label = "Buff sweep",
	tip = "A clock sweep over your buffs and debuffs above the player frame, darkening as their time runs out: the other way round from the action buttons' sweep, which clears as a spell comes ready.",
	command = "/sui sweep",
	get = function() return Settings().auraSweep end,
	toggle = SurvivorUI_ToggleAuraSweep,
})

------------------------------------------------------------------------------
-- The absorb on the player's health bar: a pale band laid over the bar from
-- its right end leftward, as wide against the bar as the shield left against
-- the hero's most health.
--
-- The game has no call for a shield's size, so it is worked out: each shield
-- buff says on its tooltip what it absorbs ("Absorbs up to 300 damage."), and
-- the combat log says how much of each hit a shield took ("(120 absorbed)"),
-- which is taken off. Where a shield's tooltip counts down by itself, its own
-- number is used as it stands. A hit absorbed whole names no amount, so it
-- cannot be taken off.

local ABSORB_PATTERNS = { "[Aa]bsorbs up to (%d+)", "[Aa]bsorbs (%d+) damage", "[Aa]bsorbing (%d+)" }

local absorbBand = player.health:CreateTexture(nil, "ARTWORK")
absorbBand:SetTexture(FLAT)
absorbBand:SetVertexColor(0.75, 0.9, 1, 0.45)
absorbBand:SetPoint("TOPRIGHT", player.health, "TOPRIGHT", 0, 0)
absorbBand:SetPoint("BOTTOMRIGHT", player.health, "BOTTOMRIGHT", 0, 0)
absorbBand:Hide()

-- Its left edge, a brighter line, so where the shield ends reads clearly.
local absorbEdge = player.health:CreateTexture(nil, "ARTWORK")
absorbEdge:SetTexture(FLAT)
absorbEdge:SetVertexColor(0.85, 0.95, 1, 0.9)
absorbEdge:SetWidth(1)
absorbEdge:SetPoint("TOPRIGHT", absorbBand, "TOPLEFT", 0, 0)
absorbEdge:SetPoint("BOTTOMRIGHT", absorbBand, "BOTTOMLEFT", 0, 0)
absorbEdge:Hide()

local shields = {}              -- [icon] = { start = what it absorbed when first seen, now = what its tooltip says now }
local soaked = 0                -- absorbed since the shields now up went up, from the combat log

local function AbsorbShown()
	return Settings().absorbBar ~= false
end

-- What a buff's tooltip says it absorbs, or nil, and the buff's name (its
-- tooltip's first line).
local function BuffAbsorb(buffIndex)
	buffScan:SetOwner(WorldFrame, "ANCHOR_NONE")
	buffScan:ClearLines()
	buffScan:SetPlayerBuff(buffIndex)
	local first = getglobal("SurvivorUIBuffScanTextLeft1")
	local name = first and first:GetText()
	for line = 1, buffScan:NumLines() do
		local text = getglobal("SurvivorUIBuffScanTextLeft"..line)
		text = text and text:GetText()
		if text then
			for index = 1, table.getn(ABSORB_PATTERNS) do
				local _, _, amount = string.find(text, ABSORB_PATTERNS[index])
				if amount then
					return tonumber(amount), name
				end
			end
		end
	end
end

-- What each shield has absorbed this run, by name, for the damage meter's
-- healing view (Meter.lua). Kept in the run's memory, so a reload keeps it.
local function AbsorbTotals()
	if not SurvivorUI_RunMemory then
		return {}
	end
	local memory = SurvivorUI_RunMemory("absorbs")
	memory.totals = memory.totals or {}
	return memory.totals
end

-- What one shield has absorbed, by whichever source says most: its share of
-- the combat log's "(120 absorbed)", what its tooltip counted down, or, once
-- it broke before its time ran out, all of it. Only the growth since last
-- time is added to its total (shield.credited holds what was).
local BROKEN_EARLY = 0.5        -- seconds it had left when it vanished; more counts as broken

local function Absorbed(shield, broken)
	if broken then
		return shield.start
	end
	return math.max(shield.logged, shield.start - shield.now)
end

local function Credit(shield, broken)
	local absorbed = Absorbed(shield, broken)
	if absorbed <= shield.credited then
		return
	end
	local totals = AbsorbTotals()
	local name = shield.name or "Absorbs"
	totals[name] = (totals[name] or 0) + absorbed - shield.credited
	shield.credited = absorbed
end

-- The shields up now: a new one starts its count, a gone one is forgotten
-- (counted whole if it broke early), and with none up the log's tally starts
-- over.
local function ReadShields()
	local seen = {}
	for slot = 0, 15 do
		local buffIndex = GetPlayerBuff(slot, "HELPFUL")
		if buffIndex and buffIndex >= 0 then
			local amount, name = BuffAbsorb(buffIndex)
			if amount then
				local key = GetPlayerBuffTexture(buffIndex) or buffIndex
				seen[key] = true
				local shield = shields[key]
				if not shield or amount > shield.now then
					-- New, or cast again: counted from its full amount.
					shield = { start = amount, now = amount, name = name, logged = 0, credited = 0 }
					shields[key] = shield
				else
					shield.now = amount
					shield.name = shield.name or name
				end
				shield.left = GetPlayerBuffTimeLeft and GetPlayerBuffTimeLeft(buffIndex) or 0
				Credit(shield)
			end
		end
	end
	local any = false
	local alive = not UnitIsDeadOrGhost("player")
	for key, shield in pairs(shields) do
		if not seen[key] then
			-- Gone with time left (or with no timer at all): used up.
			if alive and (shield.left == 0 or shield.left > BROKEN_EARLY) then
				Credit(shield, true)
			end
			shields[key] = nil
		else
			any = true
		end
	end
	if not any then
		soaked = 0
	end
end

-- What the shields have left: a shield whose tooltip counts down by itself
-- as it stands, the rest from their full amounts less what the log says was
-- soaked.
local function AbsorbLeft()
	local live, fixed = 0, 0
	for _, shield in pairs(shields) do
		if shield.now < shield.start then
			live = live + shield.now
		else
			fixed = fixed + shield.start
		end
	end
	return live + math.max(0, fixed - soaked)
end

-- What one shield has left, by its icon, for its buff icon: as its tooltip
-- says where that counts down, else its share of what the log says the
-- shields that do not count down have left.
ShieldLeft = function(key)
	local shield = key and shields[key]
	if not shield then
		return nil
	end
	if shield.now < shield.start then
		return shield.now
	end
	local fixed = 0
	for _, other in pairs(shields) do
		if other.now >= other.start then
			fixed = fixed + other.start
		end
	end
	if fixed <= 0 then
		return 0
	end
	return shield.start / fixed * math.max(0, fixed - soaked)
end

local function DrawAbsorb()
	local left = AbsorbShown() and Styled() and AbsorbLeft() or 0
	local most = UnitHealthMax("player") or 0
	if left <= 0 or most <= 0 then
		absorbBand:Hide()
		absorbEdge:Hide()
		return
	end
	local width = player.health:GetWidth() * math.min(1, left / most)
	absorbBand:SetWidth(math.max(1, width))
	absorbBand:Show()
	absorbEdge:Show()
end

local absorbWatch = CreateFrame("Frame")
for _, event in pairs({
	"CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS", "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE", "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS",
	"CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
}) do
	absorbWatch:RegisterEvent(event)
end
function SurvivorUI_AbsorbTotals()
	return AbsorbTotals()
end

-- A logged absorbed amount goes to the shields up when it was absorbed,
-- split by their sizes when several are, to "Absorbs" when none is known.
local function CountAbsorbed(amount)
	local size = 0
	for _, shield in pairs(shields) do
		size = size + shield.start
	end
	if size <= 0 then
		local totals = AbsorbTotals()
		totals["Absorbs"] = (totals["Absorbs"] or 0) + amount
		return
	end
	for _, shield in pairs(shields) do
		shield.logged = shield.logged + amount * shield.start / size
		Credit(shield)
	end
end

absorbWatch:SetScript("OnEvent", function()
	-- "Kobold Vermin hits you for 5. (120 absorbed)"
	local _, _, amount = string.find(arg1 or "", "%((%d+) absorbed%)")
	if amount then
		soaked = soaked + tonumber(amount)
		CountAbsorbed(tonumber(amount))
	end
end)

local absorbElapsed = 0
absorbWatch:SetScript("OnUpdate", function()
	absorbElapsed = absorbElapsed + arg1
	if absorbElapsed < 0.1 then
		return
	end
	absorbElapsed = 0
	ReadShields()
	DrawAbsorb()
end)

SurvivorUI_RegisterOption({
	section = "Unit frames",
	label = "Absorb on the health bar",
	parent = "Unit frames",
	tip = "A pale band over your health bar, from its right end leftward, as long as the shield you have left against your most health. Worked out from your shields' tooltips and the combat log; a hit absorbed whole cannot be counted.",
	get = AbsorbShown,
	toggle = function()
		Settings().absorbBar = not AbsorbShown()
	end,
})

local auraElapsed = 0
local auraUpdater = CreateFrame("Frame")
auraUpdater:SetScript("OnUpdate", function()
	auraElapsed = auraElapsed + arg1
	if auraElapsed >= 0.1 then
		auraElapsed = 0
		UpdateAuras()
	end
end)

local function HideStockBuffs()
	for _, name in pairs({ "BuffFrame", "TemporaryEnchantFrame" }) do
		local frame = getglobal(name)
		if frame then
			frame:Hide()
		end
	end
end

------------------------------------------------------------------------------
-- Cooldown numbers on the action buttons. OmniCC does the same job; with it
-- installed, this stands aside.

if CooldownFrame_SetTimer and not OmniCC_OnUpdate then
	local stockSetTimer = CooldownFrame_SetTimer

	-- The count down to the end, in one warm white; hidden when switched off,
	-- in whole seconds (rounded up) when asked.
	local function CounterUpdate()
		local left = this.start + this.duration - GetTime()
		if left <= 0 then
			this:Hide()
			return
		end
		local settings = Settings()
		if settings.cdNumbers == false then
			this.text:SetText("")
		elseif settings.cdRound and left < 60 then
			this.text:SetText(math.ceil(left))
		else
			this.text:SetText(TimeText(left))
		end
	end

	SurvivorUI_RegisterOption({
		section = "Ability Bar",
		label = "Cooldown numbers",
		tip = "The seconds left on a spell cooling down, over its action button.",
		get = function() return Settings().cdNumbers ~= false end,
		toggle = function()
			local settings = Settings()
			settings.cdNumbers = settings.cdNumbers == false
		end,
	})
	SurvivorUI_RegisterOption({
		section = "Ability Bar",
		label = "Round cooldown numbers",
		parent = "Cooldown numbers",
		tip = "Whole seconds, rounded up (\"1\" rather than \"0.8\"), under a minute.",
		get = function() return Settings().cdRound == true end,
		toggle = function()
			local settings = Settings()
			settings.cdRound = not settings.cdRound
		end,
	})

	-- The numbers' size, for every counter made and to be made.
	local CD_SIZE = 14
	local CD_SIZE_MIN, CD_SIZE_MAX = 8, 28
	local counters = {}

	local function CooldownSize()
		return math.max(CD_SIZE_MIN, math.min(CD_SIZE_MAX, tonumber(Settings().cdSize) or CD_SIZE))
	end

	-- The numbers' color, a warm white until one is picked.
	local CD_COLOR = { 1, 0.95, 0.6 }

	local function CooldownColor()
		local color = Settings().cdColor
		if color and color.r then
			return color.r, color.g, color.b
		end
		return CD_COLOR[1], CD_COLOR[2], CD_COLOR[3]
	end

	SurvivorUI_RegisterOption({
		section = "Ability Bar",
		kind = "color",
		label = "Cooldown number color",
		parent = "Cooldown numbers",
		tip = "The color of the cooldown numbers on the action buttons. Click to pick one on the color wheel.",
		get = CooldownColor,
		set = function(r, g, b)
			Settings().cdColor = { r = r, g = g, b = b }
			for index = 1, table.getn(counters) do
				counters[index].text:SetTextColor(r, g, b)
			end
		end,
	})

	SurvivorUI_RegisterOption({
		section = "Ability Bar",
		kind = "slider",
		label = "Cooldown number size",
		parent = "Cooldown numbers",
		tip = "The size of the cooldown numbers on the action buttons.",
		min = CD_SIZE_MIN,
		max = CD_SIZE_MAX,
		step = 1,
		get = CooldownSize,
		set = function(size)
			Settings().cdSize = size
			for index = 1, table.getn(counters) do
				counters[index].text:SetFont(FONT, size + FONT_BUMP, "OUTLINE")
			end
		end,
	})

	CooldownFrame_SetTimer = function(cooldown, start, duration, enable)
		stockSetTimer(cooldown, start, duration, enable)

		local parent = cooldown and cooldown:GetParent()
		if not parent then
			return
		end

		local counter = parent.survivorCounter
		if not counter then
			counter = CreateFrame("Frame", nil, parent)
			counter:SetAllPoints(parent)
			counter:SetFrameLevel(cooldown:GetFrameLevel() + 3)
			-- No dimming: the button keeps its colors, the sweep and the count
			-- say it is cooling down, as on the buffs.
			counter.text = Text(counter, 14, "CENTER", 0, 0)
			counter.text:SetFont(FONT, CooldownSize() + FONT_BUMP, "OUTLINE")
			counter.text:SetTextColor(CooldownColor())
			counter:SetScript("OnUpdate", CounterUpdate)
			parent.survivorCounter = counter
			table.insert(counters, counter)
		end

		-- Every cooldown gets its number, the short ones too.
		if start and start > 0 and duration and duration > 0 and enable and enable > 0 then
			counter.start, counter.duration = start, duration
			counter:Show()
		else
			counter:Hide()
		end
	end
end

------------------------------------------------------------------------------
-- A square minimap with a thin border, zoomed with the mouse wheel.

local function SquareMinimap()
	if not Minimap then
		return
	end

	-- A solid texture as the mask leaves the whole square visible.
	Minimap:SetMaskTexture(FLAT)

	for _, name in pairs({
		"MinimapBorder", "MinimapBorderTop", "MinimapZoomIn", "MinimapZoomOut",
		"MinimapToggleButton", "GameTimeFrame", "MiniMapWorldMapButton",
	}) do
		Hide(name)
	end

	if not Minimap.survivorBorder then
		local edge = CreateFrame("Frame", nil, Minimap)
		edge:SetAllPoints(Minimap)
		edge:SetFrameLevel(Minimap:GetFrameLevel() + 2)
		for _, side in pairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
			local line = edge:CreateTexture(nil, "OVERLAY")
			line:SetTexture(FLAT)
			line:SetVertexColor(0, 0, 0, 1)
			if side == "TOP" or side == "BOTTOM" then
				line:SetHeight(1)
				line:SetPoint(side.."LEFT", edge, side.."LEFT", -1, side == "TOP" and 1 or -1)
				line:SetPoint(side.."RIGHT", edge, side.."RIGHT", 1, side == "TOP" and 1 or -1)
			else
				line:SetWidth(1)
				line:SetPoint("TOP"..side, edge, "TOP"..side, side == "LEFT" and -1 or 1, 1)
				line:SetPoint("BOTTOM"..side, edge, "BOTTOM"..side, side == "LEFT" and -1 or 1, -1)
			end
		end
		Minimap.survivorBorder = edge

		Minimap:EnableMouseWheel(true)
		Minimap:SetScript("OnMouseWheel", function()
			if arg1 > 0 then
				Minimap:SetZoom(math.min(Minimap:GetZoomLevels() - 1, Minimap:GetZoom() + 1))
			else
				Minimap:SetZoom(math.max(0, Minimap:GetZoom() - 1))
			end
		end)
	end
end

------------------------------------------------------------------------------
-- The micro buttons (character, talents, map, menu, help) go to the bottom
-- right corner. The others are chained to the first, so moving it moves all.

local function MoveMicroButtons()
	local first = getglobal("CharacterMicroButton")
	if first then
		first:ClearAllPoints()
		first:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMRIGHT", -140, 2)
	end
end

------------------------------------------------------------------------------
-- The micro buttons stay out of sight until the mouse reaches their corner.

local MICRO_BUTTONS = {
	"CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton",
	"SocialsMicroButton", "WorldMapMicroButton", "MainMenuMicroButton", "HelpMicroButton",
}

local microZone = CreateFrame("Frame", "SurvivorUIMicroZone", UIParent)
microZone:SetWidth(170)
microZone:SetHeight(60)
microZone:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)

local microAlpha = 0
microZone:SetScript("OnUpdate", function()
	local want = MouseIsOver(this) and 1 or 0
	if microAlpha == want then
		return
	end

	-- A quick fade either way.
	local step = arg1 * 6
	if want > microAlpha then
		microAlpha = math.min(1, microAlpha + step)
	else
		microAlpha = math.max(0, microAlpha - step)
	end
	for _, name in pairs(MICRO_BUTTONS) do
		local button = getglobal(name)
		if button then
			button:SetAlpha(microAlpha)
		end
	end
end)

local function HideMicroButtons()
	microAlpha = 0
	for _, name in pairs(MICRO_BUTTONS) do
		local button = getglobal(name)
		if button then
			button:SetAlpha(0)
		end
	end
end

------------------------------------------------------------------------------
-- Chat: a flat dark panel, no scroll buttons, no tab art. The mouse wheel
-- scrolls; with Shift held it jumps to the top or the bottom.

local function ChatWheel()
	if arg1 > 0 then
		if IsShiftKeyDown() then
			this:ScrollToTop()
		else
			this:ScrollUp()
		end
	else
		if IsShiftKeyDown() then
			this:ScrollToBottom()
		else
			this:ScrollDown()
		end
	end
end

local function StyleChat()
	Hide("ChatFrameMenuButton")

	for index = 1, 7 do
		local name = "ChatFrame"..index
		local chat = getglobal(name)
		if chat then
			Hide(name.."UpButton")
			Hide(name.."DownButton")
			Hide(name.."BottomButton")

			-- Plain text with a soft shadow in place of the stock look.
			chat:SetFont(FONT, Settings().chatSize)
			chat:SetShadowColor(0, 0, 0, 1)
			chat:SetShadowOffset(1, -1)

			chat:EnableMouseWheel(true)
			chat:SetScript("OnMouseWheel", ChatWheel)

			if not chat.survivorPanel then
				local panel = CreateFrame("Frame", nil, chat)
				panel:SetPoint("TOPLEFT", chat, "TOPLEFT", -6, 6)
				panel:SetPoint("BOTTOMRIGHT", chat, "BOTTOMRIGHT", 6, -6)
				panel:SetFrameLevel(math.max(0, chat:GetFrameLevel() - 1))
				local fill = panel:CreateTexture(nil, "BACKGROUND")
				fill:SetTexture(FLAT)
				fill:SetVertexColor(0.04, 0.04, 0.06, 0.55)
				fill:SetAllPoints(panel)
				-- An accent line down the left edge.
				local accent = panel:CreateTexture(nil, "BORDER")
				accent:SetTexture(FLAT)
				accent:SetVertexColor(1, 0.82, 0, 0.8)
				accent:SetWidth(2)
				accent:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
				accent:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
				chat.survivorPanel = panel
			end

			-- The tab keeps its text and loses its art.
			for _, piece in pairs({ "Left", "Middle", "Right" }) do
				local art = getglobal(name.."Tab"..piece)
				if art then
					art:SetTexture("")
				end
			end
			local tabText = getglobal(name.."TabText")
			if tabText then
				tabText:SetFont(FONT, 11 + FONT_BUMP, "OUTLINE")
			end
		end
	end

	-- The edit box: a flat field under the chat.
	local edit = getglobal("ChatFrameEditBox")
	if edit then
		for _, piece in pairs({ "Left", "Mid", "Right" }) do
			local art = getglobal("ChatFrameEditBox"..piece)
			if art then
				art:SetTexture("")
			end
		end
		if not edit.survivorBack then
			edit.survivorBack = edit:CreateTexture(nil, "BACKGROUND")
			edit.survivorBack:SetTexture(FLAT)
			edit.survivorBack:SetVertexColor(0.04, 0.04, 0.06, 0.8)
			edit.survivorBack:SetPoint("TOPLEFT", edit, "TOPLEFT", 4, -5)
			edit.survivorBack:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", -4, 5)
		end
	end
end

------------------------------------------------------------------------------
-- One face everywhere (SurvivorUI_FONT). The stock interface mixes several:
-- Friz Quadrata for most things, others for chat, numbers, quest and mail text.

-- Read by the engine when the world loads, for the text it draws itself.
STANDARD_TEXT_FONT = FONT
UNIT_NAME_FONT = FONT
NAMEPLATE_FONT = FONT
DAMAGE_TEXT_FONT = FONT

local FONT_OBJECTS = {
	"GameFontNormal", "GameFontHighlight", "GameFontDisable", "GameFontGreen", "GameFontRed", "GameFontBlack", "GameFontWhite",
	"GameFontNormalSmall", "GameFontHighlightSmall", "GameFontHighlightSmallOutline", "GameFontDisableSmall",
	"GameFontDarkGraySmall", "GameFontGreenSmall", "GameFontRedSmall",
	"GameFontNormalLarge", "GameFontHighlightLarge", "GameFontDisableLarge", "GameFontGreenLarge", "GameFontRedLarge",
	"GameFontNormalHuge",
	"NumberFontNormal", "NumberFontNormalYellow", "NumberFontNormalSmall", "NumberFontNormalSmallGray",
	"NumberFontNormalLarge", "NumberFontNormalHuge",
	"ChatFontNormal", "ChatFontSmall", "CombatLogFont",
	"QuestTitleFont", "QuestFont", "QuestFontNormalSmall", "QuestFontHighlight",
	"ItemTextFontNormal", "MailTextFontNormal", "InvoiceTextFontNormal", "InvoiceTextFontSmall",
	"SubSpellFont", "DialogButtonNormalText", "DialogButtonHighlightText",
	"ZoneTextFont", "SubZoneTextFont", "PVPInfoTextFont", "ErrorFont", "WorldMapTextFont",
	"TextStatusBarText", "TextStatusBarTextSmall",
	"GameTooltipText", "GameTooltipTextSmall", "GameTooltipHeaderText",
}

local function ApplyFonts()
	for _, name in pairs(FONT_OBJECTS) do
		local object = getglobal(name)
		if object and object.GetFont and object.SetFont then
			-- The stock size is kept on the first pass, so the bump is not added twice.
			if not object.survivorSize then
				local _, size, flags = object:GetFont()
				object.survivorSize, object.survivorFlags = size, flags
			end
			local size = object.survivorSize
			if size and size > 0 then
				object:SetFont(FONT, size + FONT_BUMP, object.survivorFlags)
			end
		end
	end
end

------------------------------------------------------------------------------
-- Tooltip: a flat dark box with a hairline border, a slim health bar along its
-- bottom edge, and smaller type.

local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "WorldMapTooltip" }

local TOOLTIP_BACKDROP = {
	bgFile = FLAT, edgeFile = FLAT,
	tile = false, edgeSize = 1,
	insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local function PaintTooltip(tooltip)
	tooltip:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
	tooltip:SetBackdropBorderColor(0, 0, 0, 1)
end

local function StyleTooltips()
	-- The stock code repaints a tooltip from these two.
	TOOLTIP_DEFAULT_COLOR = { r = 0, g = 0, b = 0 }
	TOOLTIP_DEFAULT_BACKGROUND_COLOR = { r = 0.05, g = 0.05, b = 0.07 }

	for _, name in pairs(TOOLTIPS) do
		local tooltip = getglobal(name)
		if tooltip and not tooltip.survivorStyled then
			tooltip.survivorStyled = true
			tooltip:SetBackdrop(TOOLTIP_BACKDROP)
			PaintTooltip(tooltip)

			local stockShow = tooltip:GetScript("OnShow")
			tooltip:SetScript("OnShow", function()
				if stockShow then
					stockShow()
				end
				PaintTooltip(this)
			end)
		end
	end

	local header = getglobal("GameTooltipHeaderText")
	if header then
		header:SetFont(FONT, 13 + FONT_BUMP)
	end
	local body = getglobal("GameTooltipText")
	if body then
		body:SetFont(FONT, 11 + FONT_BUMP)
	end
	local small = getglobal("GameTooltipTextSmall")
	if small then
		small:SetFont(FONT, 10 + FONT_BUMP)
	end

	local bar = getglobal("GameTooltipStatusBar")
	if bar and GameTooltip then
		bar:SetStatusBarTexture(FLAT)
		bar:SetHeight(4)
		bar:ClearAllPoints()
		bar:SetPoint("BOTTOMLEFT", GameTooltip, "BOTTOMLEFT", 1, 1)
		bar:SetPoint("BOTTOMRIGHT", GameTooltip, "BOTTOMRIGHT", -1, 1)
	end
end

------------------------------------------------------------------------------
-- Damage numbers: small, quick, and gone. A number pops over the enemy it hit,
-- shoots up and fades within half a second; a critical strike is larger and
-- gold. They replace the engine's own floating numbers while switched on
-- (/sui combattext switches back and forth; switched off, the game's floating
-- combat text is all stock again).
--
-- The addon reads hits from the combat log, which names the enemy but not
-- which one of several with that name. The number goes over one of them.

local DAMAGE_LIFE = 0.55        -- seconds on screen
local DAMAGE_RISE = 62          -- how far a number climbs
local DAMAGE_MAX = 48           -- numbers alive at once
local CRIT_SIZE = 22            -- a critical strike's number; a normal one is 14
local CRIT_POP_SIZE = 30        -- its size for the first instant
local CRIT_POP_TIME = 0.09

local damageLayer = CreateFrame("Frame", "SurvivorUIDamage", UIParent)
damageLayer:SetAllPoints(UIParent)
damageLayer:SetFrameStrata("HIGH")

local damageTexts = {}
local damageLive = 0

local function DamageText()
	for index = 1, table.getn(damageTexts) do
		if not damageTexts[index].live then
			return damageTexts[index]
		end
	end
	if table.getn(damageTexts) >= DAMAGE_MAX then
		return nil
	end
	local text = damageLayer:CreateFontString(nil, "OVERLAY")
	table.insert(damageTexts, text)
	return text
end

-- Every nameplate on screen showing this name. Survivor Plates blanks the art
-- a plate is recognized by, so its own list is used when it is installed.
local function PlatesNamed(name)
	local found = {}
	if SurvivorPlatesRegistry then
		for index = 1, table.getn(SurvivorPlatesRegistry) do
			local overlay = SurvivorPlatesRegistry[index]
			if overlay.plate:IsVisible() and overlay.stock.name:GetText() == name then
				table.insert(found, overlay.plate)
			end
		end
		return found
	end

	local children = { WorldFrame:GetChildren() }
	for index = 1, table.getn(children) do
		local plate = children[index]
		local border = plate:GetRegions()
		if plate:IsVisible() and border and border.GetTexture and border:GetObjectType() == "Texture"
			and border:GetTexture() == "Interface\\Tooltips\\Nameplate-Border" then
			local regions = { plate:GetRegions() }
			for region = 1, table.getn(regions) do
				if regions[region]:GetObjectType() == "FontString" then
					if regions[region]:GetText() == name then
						table.insert(found, plate)
					end
					break
				end
			end
		end
	end
	return found
end

-- target is nil for a hit the hero took: that number rises over the hero, in red.
-- A pooled number changes size and outline only when it must: setting the same
-- face again still costs the engine a font lookup, many times a second.
local function Face(text, size, flags)
	local key = size..flags
	if text.faceKey ~= key then
		text.faceKey = key
		text:SetFont(FONT, size, flags)
	end
end

local function SpawnDamage(target, amount, crit, periodic)
	local text = DamageText()
	if not text then
		return
	end

	-- Over one of the enemies with that name, else in a ring around the hero.
	local x, y
	local plates = target and PlatesNamed(target) or {}
	local count = table.getn(plates)
	if not target then
		-- The camera keeps the hero in the middle of the screen.
		x = UIParent:GetWidth() / 2
		-- From the hero's feet down, ending short of the bar row (150 below).
		y = UIParent:GetHeight() / 2 - 15
	elseif count > 0 then
		local plate = plates[math.random(1, count)]
		local px, py = plate:GetCenter()
		if px and py then
			local ratio = 1
			if plate.GetEffectiveScale and UIParent.GetEffectiveScale then
				ratio = plate:GetEffectiveScale() / UIParent:GetEffectiveScale()
			end
			x, y = px * ratio, py * ratio - 10
		end
	end
	if not x then
		local angle = math.random() * 6.2832
		local reach = 90 + math.random() * 70
		x = UIParent:GetWidth() / 2 + math.cos(angle) * reach
		y = UIParent:GetHeight() / 2 + 30 + math.sin(angle) * reach * 0.6
	end

	if not target then
		Face(text, crit and CRIT_POP_SIZE or 14, crit and "THICKOUTLINE" or "OUTLINE")
		text:SetTextColor(1, 0.22, 0.22)
		amount = "-"..amount
	elseif crit then
		-- Lands oversized, then settles: see the update below.
		Face(text, CRIT_POP_SIZE, "THICKOUTLINE")
		text:SetTextColor(1, 0.76, 0.08)
	elseif periodic then
		Face(text, 12 + FONT_BUMP, "OUTLINE")
		text:SetTextColor(0.80, 0.80, 0.80)
	else
		Face(text, 14 + FONT_BUMP, "OUTLINE")
		text:SetTextColor(1, 1, 1)
	end
	text:SetText(amount)

	text.live = true
	text.crit = crit
	text.popped = nil
	text.life = crit and DAMAGE_LIFE * 1.3 or DAMAGE_LIFE
	text.age = 0
	text.x = x + (math.random() - 0.5) * 24
	text.y = y
	text.drift = (math.random() - 0.5) * 30
	text.rise = crit and DAMAGE_RISE * 1.3 or DAMAGE_RISE
	if not target then
		-- A hit the hero took falls instead, apart from the ones it deals.
		text.rise = -text.rise
	end
	text:SetAlpha(1)
	text:Show()
	damageLive = damageLive + 1
end

damageLayer:SetScript("OnUpdate", function()
	if damageLive == 0 then
		return
	end

	for index = 1, table.getn(damageTexts) do
		local text = damageTexts[index]
		if text.live then
			text.age = text.age + arg1
			local t = text.age / text.life
			if text.crit and not text.popped and text.age >= CRIT_POP_TIME then
				text.popped = true
				Face(text, CRIT_SIZE, "THICKOUTLINE")
			end
			if t >= 1 then
				text.live = nil
				text:Hide()
				damageLive = damageLive - 1
			else
				-- Fast at first, slowing as it tops out; fading over the last third.
				local eased = 1 - (1 - t) * (1 - t)
				text:ClearAllPoints()
				text:SetPoint("CENTER", UIParent, "BOTTOMLEFT", text.x + text.drift * eased, text.y + text.rise * eased)
				text:SetAlpha(t > 0.66 and (1 - t) / 0.34 or 1)
			end
		end
	end
end)

local function ParseDamage(message)
	local _, _, target, amount = string.find(message, " crits (.+) for (%d+)")
	if target then
		return target, amount, true
	end
	_, _, target, amount = string.find(message, " crit (.+) for (%d+)")
	if target then
		return target, amount, true
	end
	_, _, target, amount = string.find(message, " hits (.+) for (%d+)")
	if target then
		return target, amount
	end
	_, _, target, amount = string.find(message, " hit (.+) for (%d+)")
	if target then
		return target, amount
	end
	-- "Kobold Vermin suffers 12 Fire damage from your Flame Shock."
	_, _, target, amount = string.find(message, "^(.+) suffers (%d+) .+ from your ")
	if target then
		return target, amount, false, true
	end
end

-- The hits the hero takes come from the stock floating combat text's own feed.
local TAKEN_TYPES = { DAMAGE = true, DAMAGE_CRIT = true, SPELL_DAMAGE = true }

local damageEvents = CreateFrame("Frame")
damageEvents:SetScript("OnEvent", function()
	if not Settings().damageText then
		return
	end
	if event == "COMBAT_TEXT_UPDATE" then
		if TAKEN_TYPES[arg1] and tonumber(arg2) then
			SpawnDamage(nil, arg2, arg1 == "DAMAGE_CRIT")
		end
		return
	end
	local target, amount, crit, periodic = ParseDamage(arg1 or "")
	if target then
		SpawnDamage(target, amount, crit, periodic)
	end
end)

local DAMAGE_EVENTS = {
	"CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_SPELL_SELF_DAMAGE",
	"CHAT_MSG_COMBAT_PET_HITS", "CHAT_MSG_SPELL_PET_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "COMBAT_TEXT_UPDATE",
}

-- The stock floating combat text (Blizzard_CombatText, loaded on demand)
-- scrolls the hits the hero takes slowly, in its own face. While the quick
-- numbers are on, it leaves those to them; heals and the rest stay its own.
-- Switched off, every piece is the stock one again.
local stockWarnings = {}        -- [kind] = the stock { var, show }, kept before the first change

local function ApplyTakenText()
	if not COMBAT_TEXT_TYPE_INFO then
		return
	end
	local on = Settings().damageText
	-- "Health Low" in big letters over the fight says what the player frame
	-- already shows. Tied to a setting no one sets, so the stock refresh keeps
	-- it off.
	for _, kind in pairs({ "HEALTH_LOW", "MANA_LOW" }) do
		local info = COMBAT_TEXT_TYPE_INFO[kind]
		if info then
			if not stockWarnings[kind] then
				stockWarnings[kind] = { var = info.var, show = info.show }
			end
			if on then
				info.var = "SURVIVORUI_NEVER"
				info.show = nil
			else
				info.var = stockWarnings[kind].var
				info.show = stockWarnings[kind].show
			end
		end
	end
	-- The hits taken float in the stock text only while neither the quick
	-- numbers nor hidden numbers take them over.
	local stock = not (on or Settings().damageHidden)
	for kind in pairs(TAKEN_TYPES) do
		local info = COMBAT_TEXT_TYPE_INFO[kind]
		if info then
			info.show = stock and 1 or nil
		end
	end
end

local takenWatch = CreateFrame("Frame")
takenWatch:RegisterEvent("ADDON_LOADED")
takenWatch:SetScript("OnEvent", function()
	if arg1 == "Blizzard_CombatText" then
		ApplyTakenText()
	end
end)

-- The engine's numbers are on when the addon's are off, and the other way round.
-- Hidden, neither shows: the game's CombatDamage masters every number that
-- floats over a unit, and the stock text leaves the hits taken alone.
local function ApplyDamageText()
	local hidden = Settings().damageHidden
	local on = Settings().damageText and not hidden
	for _, event in pairs(DAMAGE_EVENTS) do
		if on then
			damageEvents:RegisterEvent(event)
		else
			damageEvents:UnregisterEvent(event)
		end
	end
	SetCVar("CombatDamage", (on or hidden) and "0" or "1")
	ApplyTakenText()
end

function SurvivorUI_ToggleDamageHidden()
	local settings = Settings()
	settings.damageHidden = not settings.damageHidden
	ApplyDamageText()
	DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: damage numbers "..(settings.damageHidden
		and "hidden, the game's and the addon's alike."
		or "shown again."))
end

function SurvivorUI_ToggleDamageText()
	local settings = Settings()
	settings.damageText = not settings.damageText
	ApplyDamageText()
	DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: "..(settings.damageText
		and "quick damage numbers."
		or "the game's own floating combat text."))
end

SurvivorUI_RegisterOption({
	section = "Text & Numbers",
	label = "Quick damage numbers",
	tip = "Small, quick numbers over the enemies you hit and the hits you take, in place of the game's floating combat text. Off, the game's own is back as it was.",
	command = "/sui combattext",
	get = function() return Settings().damageText end,
	toggle = SurvivorUI_ToggleDamageText,
})

SurvivorUI_RegisterOption({
	section = "Text & Numbers",
	label = "Hide damage numbers",
	tip = "No damage numbers at all: neither the quick ones nor the game's floating ones, over enemies or over you. Overrides Quick damage numbers while on.",
	command = "/sui nodamage",
	get = function() return Settings().damageHidden == true end,
	toggle = SurvivorUI_ToggleDamageHidden,
})

------------------------------------------------------------------------------
-- Error text: the red lines over the middle of the screen ("This cache needs
-- 1787 gold.") and the game's yellow notices, all written by the stock
-- UIErrorsFrame. Switched off, the frame hangs from a hidden one: out of
-- sight, every message still taken in, and back as it was when switched on.

local errorsAway = CreateFrame("Frame")
errorsAway:Hide()

local function ApplyErrorText()
	if not UIErrorsFrame then
		return
	end
	if Settings().errorText == false then
		UIErrorsFrame:SetParent(errorsAway)
	else
		UIErrorsFrame:SetParent(UIParent)
	end
end

function SurvivorUI_ToggleErrorText()
	local settings = Settings()
	settings.errorText = settings.errorText == false
	ApplyErrorText()
	DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: error text "..(settings.errorText and "shown." or "hidden."))
end

------------------------------------------------------------------------------
-- Events text: the game's own banners over the fight ("A wall of foes closes
-- in! Qiraji Champion approaches!"). They are one of the run's screens the game
-- lets addons switch (its "banners"), kept as the game's own setting.

--
-- Switched off, the addon keeps it off: the game can switch its banners back
-- on by itself (a new run, a reload), so the setting is put back whenever it
-- is found on again. The raid warning frame, which a game may also write such
-- lines to and which a run has no other use for, hangs from a hidden frame
-- meanwhile.
local eventsAway = CreateFrame("Frame")
eventsAway:Hide()

local function EventsShown()
	local hidden = Settings().eventsHidden
	if hidden ~= nil then
		return not hidden
	end
	if AZS_IsHudShown then
		return AZS_IsHudShown("banners") and true or false
	end
	return true
end

local function ApplyEventsText()
	local hidden = Settings().eventsHidden == true
	if AZS_SetHudShown and AZS_IsHudShown and hidden and AZS_IsHudShown("banners") then
		AZS_SetHudShown("banners", false)
	end
	if RaidWarningFrame then
		RaidWarningFrame:SetParent(hidden and eventsAway or UIParent)
	end
end

function SurvivorUI_ToggleEventsText()
	local shown = not EventsShown()
	Settings().eventsHidden = not shown
	if AZS_SetHudShown then
		AZS_SetHudShown("banners", shown)
	end
	ApplyEventsText()
	DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: event text "..(shown and "shown." or "hidden."))
end

local eventsWatch = CreateFrame("Frame")
local eventsElapsed = 0
eventsWatch:SetScript("OnUpdate", function()
	eventsElapsed = eventsElapsed + arg1
	if eventsElapsed < 1 then
		return
	end
	eventsElapsed = 0
	if Settings().eventsHidden then
		ApplyEventsText()
	end
end)

SurvivorUI_RegisterOption({
	section = "Text & Numbers",
	label = "Events text",
	tip = "The game's banners over the fight, such as \"A wall of foes closes in!\" or \"Qiraji Champion approaches!\". Kept as the game's own setting.",
	command = "/sui events",
	get = EventsShown,
	toggle = SurvivorUI_ToggleEventsText,
})

SurvivorUI_RegisterOption({
	section = "Text & Numbers",
	label = "Error text",
	tip = "The game's red messages over the middle of the screen (\"This cache needs 1787 gold.\") and its yellow notices. Off, none of them show.",
	command = "/sui errors",
	get = function() return Settings().errorText ~= false end,
	toggle = SurvivorUI_ToggleErrorText,
})

------------------------------------------------------------------------------
-- The camera's furthest zoom: the client's own setting (cameraDistanceMax,
-- in yards), raised past the game's 15 up to the 50 the client allows. Left
-- alone until the slider is moved; set again on every login, as the client
-- can put it back.

local CAMERA_MIN, CAMERA_MAX = 15, 50

local function CameraDistance()
	local wanted = tonumber(Settings().cameraMax)
	if wanted then
		return wanted
	end
	local ok, current = pcall(GetCVar, "cameraDistanceMax")
	current = ok and tonumber(current) or CAMERA_MIN
	return math.max(CAMERA_MIN, math.min(CAMERA_MAX, current))
end

local function ApplyCamera()
	local wanted = tonumber(Settings().cameraMax)
	if wanted then
		pcall(SetCVar, "cameraDistanceMax", wanted)
	end
end

SurvivorUI_RegisterOption({
	section = "Interface",
	kind = "slider",
	label = "Camera max distance",
	tip = "How far out the camera can zoom, in yards (the client's cameraDistanceMax). Scroll out after raising it. If the game holds its camera itself, this may change nothing.",
	min = CAMERA_MIN,
	max = CAMERA_MAX,
	step = 1,
	get = CameraDistance,
	set = function(value)
		Settings().cameraMax = value
		ApplyCamera()
	end,
})

------------------------------------------------------------------------------
-- /sui inspect and /sui find: what a piece of the game's interface is called,
-- so the addon can be taught to style or hide it. inspect names the frame
-- under the mouse and the frames it hangs from; find names every shown frame
-- whose text holds the words given ("/sui find Options").

local function FramePath(frame)
	local parts = {}
	local node = frame
	while node and node ~= UIParent and table.getn(parts) < 8 do
		local name = node.GetName and node:GetName()
		table.insert(parts, 1, name or ("<"..(node.GetObjectType and node:GetObjectType() or "?")..">"))
		node = node.GetParent and node:GetParent()
	end
	return table.concat(parts, " > ")
end

local function Say(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Survivor UI:|r "..text)
end

local function Inspect()
	local focus = GetMouseFocus and GetMouseFocus()
	if not focus then
		Say("nothing under the mouse; point at the piece and type /sui inspect again.")
		return
	end
	Say("under the mouse: "..FramePath(focus))
	local width, height = focus:GetWidth(), focus:GetHeight()
	Say(string.format("  %s, %.0f by %.0f, strata %s", focus:GetObjectType(), width or 0, height or 0,
		focus.GetFrameStrata and focus:GetFrameStrata() or "?"))
	local top = focus
	while top:GetParent() and top:GetParent() ~= UIParent and top:GetParent() ~= WorldFrame do
		top = top:GetParent()
	end
	if top ~= focus then
		Say("  its window: "..(top:GetName() or "<unnamed "..top:GetObjectType()..">"))
	end
end

local function Find(words)
	if not EnumerateFrames then
		Say("this client cannot list its frames.")
		return
	end
	local wanted = string.lower(words)
	local found = 0
	local frame = EnumerateFrames()
	while frame and found < 12 do
		if frame:IsVisible() and frame.GetRegions then
			local regions = { frame:GetRegions() }
			for index = 1, table.getn(regions) do
				local region = regions[index]
				if region.GetObjectType and region:GetObjectType() == "FontString" then
					local text = region:GetText()
					if text and string.find(string.lower(text), wanted, 1, true) then
						found = found + 1
						Say("\""..string.sub(text, 1, 40).."\" in "..FramePath(frame))
						break
					end
				end
			end
		end
		frame = EnumerateFrames(frame)
	end
	if found == 0 then
		Say("no shown text holds \""..words.."\".")
	end
end

SLASH_SURVIVORUI1 = "/sui"
SlashCmdList["SURVIVORUI"] = function(msg)
	local _, _, command, argument = string.find(msg or "", "^(%S*)%s*(.*)$")
	if command == "chat" and tonumber(argument) then
		local settings = Settings()
		settings.chatSize = math.max(8, math.min(18, tonumber(argument)))
		StyleChat()
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: chat text size "..settings.chatSize..".")
	elseif msg == "bosses" or msg == "bosses elites" then
		if SurvivorUI_BossBars then
			SurvivorUI_BossBars(argument)
		end
	elseif msg == "timer" or msg == "tracker" then
		if SurvivorUI_ToggleTracker then
			SurvivorUI_ToggleTracker()
		end
	elseif msg == "timer compact" or msg == "tracker compact" then
		if SurvivorUI_ToggleTrackerCompact then
			SurvivorUI_ToggleTrackerCompact()
		end
	elseif msg == "xp" then
		if SurvivorUI_ToggleXP then
			SurvivorUI_ToggleXP()
		end
	elseif msg == "tally" then
		if SurvivorUI_Tally then
			SurvivorUI_Tally()
		end
	elseif msg == "meter" then
		if SurvivorUI_ToggleMeter then
			SurvivorUI_ToggleMeter()
		end
	elseif command == "scale" then
		if SurvivorUI_SetScale then
			SurvivorUI_SetScale(argument)
		end
	elseif msg == "layout" then
		if SurvivorUI_ResetLayout then
			SurvivorUI_ResetLayout()
		end
	elseif msg == "loot" then
		if SurvivorUI_ToggleLoot then
			SurvivorUI_ToggleLoot()
		end
	elseif msg == "build" then
		if SurvivorUI_ToggleBuild then
			SurvivorUI_ToggleBuild()
		end
	elseif msg == "gear" then
		SurvivorUI_GearReport()
	elseif command == "logwatch" and argument ~= "" then
		SurvivorUI_LogWatch(argument)
	elseif msg == "spells" then
		if SurvivorUI_SpellReport then
			SurvivorUI_SpellReport()
		end
	elseif msg == "codex" then
		if SurvivorUI_ToggleCodex then
			SurvivorUI_ToggleCodex()
		end
	elseif msg == "center" then
		if SurvivorUI_CenterRow then
			SurvivorUI_CenterRow()
		end
	elseif msg == "nodamage" then
		SurvivorUI_ToggleDamageHidden()
	elseif msg == "combattext" or msg == "damage" then
		SurvivorUI_ToggleDamageText()
	elseif msg == "sweep" then
		SurvivorUI_ToggleAuraSweep()
	elseif msg == "frames" then
		SurvivorUI_ToggleUnitStyle()
	elseif msg == "errors" then
		SurvivorUI_ToggleErrorText()
	elseif msg == "events" then
		SurvivorUI_ToggleEventsText()
	elseif msg == "caches" then
		if SurvivorUI_DebugCaches then
			SurvivorUI_DebugCaches()
		end
	elseif msg == "icons" then
		if SurvivorUI_DebugIcons then
			SurvivorUI_DebugIcons()
		end
	elseif msg == "inspect" then
		Inspect()
	elseif command == "find" and argument ~= "" then
		Find(argument)
	elseif msg == "reload" then
		-- The whole interface again, every addon's files read afresh from disk:
		-- an edited file takes effect without leaving the game. A new file (or a
		-- change to the .toc) still needs the game restarted.
		ReloadUI()
	elseif msg == "opt" or msg == "options" then
		if SurvivorUI_ToggleOptions then
			SurvivorUI_ToggleOptions()
		end
	else
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui opt  opens a window with every switch below")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui combattext  switches between the quick damage numbers and the game's own floating combat text")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui nodamage  hides every damage number, the game's and the addon's")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui frames  switches between the addon's unit frames and the game's")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui sweep  switches the clock sweep over your buffs")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui errors  shows or hides the game's red error text; /sui events  its event banners")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui reload  reloads the interface, picking up edited addon files")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui chat 12  sets the chat text size, 8 to 18")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: tap Alt for edit mode: drag what moves, click it for its options; /sui center puts the middle back, /sui layout puts everything back")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui bosses  switches the boss bars on or off; /sui bosses elites  lists elites too")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui tally  switches between the kills and gold line under the bar and the game's own box")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui timer  shows or hides the run timer under the minimap (the clock and the bosses); /sui timer compact  leaves out the list of bosses")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui xp  shows or hides the run's level bar")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui build  shows or hides the build (spells and jewelry); /sui codex  opens the Codex")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui loot  shows or hides the loot log; /sui caches  lists what the cache arrow is made from")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui inspect  names the frame under the mouse; /sui find words  names the frames showing those words")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui scale 0.85  sizes the panels, 0.6 to 1.4, for smaller screens")
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: /sui meter  switches between the addon's damage meter, with the crits, and the game's own")
	end
end


------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("PLAYER_TARGET_CHANGED")
loader:RegisterEvent("UNIT_PORTRAIT_UPDATE")
loader:SetScript("OnEvent", function()
	if event == "PLAYER_ENTERING_WORLD" then
		ApplyUnitStyle()
		ApplyErrorText()
		ApplyUnitSize()
		RestoreAnchor(playerAnchor)
		RestoreAnchor(targetAnchor)
		-- Mover.lua loads after this file: the unit frames' edit-mode handles are made here.
		if SurvivorUI_RegisterMover and not playerAnchor.mover then
			playerAnchor.mover = SurvivorUI_RegisterMover(playerAnchor, "Player frame",
				function() SaveAnchor(playerAnchor) end, nil, function() RestoreAnchor(playerAnchor) end)
			targetAnchor.mover = SurvivorUI_RegisterMover(targetAnchor, "Target frame",
				function() SaveAnchor(targetAnchor) end, nil, function() RestoreAnchor(targetAnchor) end)
		end
		HideStockBuffs()
		ApplyAuraSize()
		RestoreAuraPlace()
		-- Mover.lua loads after this file: the buff row's edit-mode handle is made here.
		if SurvivorUI_RegisterMover and not auraHolder.mover then
			auraHolder.mover = SurvivorUI_RegisterMover(auraHolder, "Buffs", SaveAuraPlace, nil, RestoreAuraPlace)
		end
		SizeRows()
		LayoutBar()
		SquareMinimap()
		MoveMicroButtons()
		HideMicroButtons()
		ApplyFonts()
		StyleChat()
		StyleTooltips()
		ApplyDamageText()
		ApplyEventsText()
		ApplyCamera()
		UpdatePortrait(player)
	elseif event == "PLAYER_TARGET_CHANGED" then
		UpdatePortrait(target)
	elseif arg1 == "player" then
		UpdatePortrait(player)
	elseif arg1 == "target" then
		UpdatePortrait(target)
	end
end)
