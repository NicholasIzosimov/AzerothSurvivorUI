-- Survivor UI: kills, gold and caches, in a small dark box under the
-- experience bar: each number over its rate (kills and gold a second) or, for
-- the cache's price, the gold still missing to it.
--
-- The game draws the same three numbers in a box of its own that no addon can
-- move. Where it shares them (its addon API, AZS_RUN), this box takes their
-- place, and the game's box is put away. /sui tally brings the game's box back.
--
-- It sits under the middle block and follows it until it is moved on its own:
-- in edit mode (tap Alt), drag it. /sui layout puts it back under the block.

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local FONT = SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BUMP = SurvivorUI_FONT_BUMP or 0
local PAD_X, PAD_Y = 8, 4
local TEXT_SIZE = 11                    -- until one is chosen in /sui opt
local TEXT_SIZE_MIN, TEXT_SIZE_MAX = 8, 24

local row = getglobal("SurvivorUIRow")
if not row then
	return
end

local function Settings()
	SurvivorUIDB = SurvivorUIDB or {}
	if SurvivorUIDB.tally == nil then
		SurvivorUIDB.tally = true
	end
	return SurvivorUIDB
end

-- 2,054
-- 950, 2.1k, 3.4m: from a thousand on, in thousands (millions) to a tenth.
-- up rounds up rather than down: a price is never shown lower than it is, and
-- gold never higher, so a cache never looks affordable before it is.
local function Short(value, up)
	value = tonumber(value) or 0
	local unit, suffix = 1, ""
	if value >= 1000000 then
		unit, suffix = 1000000, "m"
	elseif value >= 1000 then
		unit, suffix = 1000, "k"
	end
	if unit == 1 then
		return tostring(up and math.ceil(value) or math.floor(value))
	end
	local tenths = value / unit * 10
	tenths = up and math.ceil(tenths - 0.000001) or math.floor(tenths + 0.000001)
	local text = string.format("%.1f", tenths / 10)
	return (string.gsub(text, "%.0$", ""))..suffix
end
SurvivorUI_Short = Short

local function TextSize()
	local size = tonumber(Settings().tallySize) or TEXT_SIZE
	return math.max(TEXT_SIZE_MIN, math.min(TEXT_SIZE_MAX, size))
end

local box = CreateFrame("Frame", "SurvivorUITally", UIParent)
box:SetHeight(2 * TEXT_SIZE + 2 + 2 * PAD_Y)
box:SetWidth(200)
box:SetFrameStrata("LOW")
box:SetMovable(true)
if box.SetClampedToScreen then
	box:SetClampedToScreen(true)
end
box:SetBackdrop({
	bgFile = FLAT, edgeFile = FLAT, tile = false, edgeSize = 1,
	insets = { left = 1, right = 1, top = 1, bottom = 1 },
})
box:SetBackdropColor(0, 0, 0, 0.75)
box:SetBackdropBorderColor(0, 0, 0, 1)
box:Hide()

-- Two rows of three columns, each number over its rate or its follow-up:
--   Kills 4,206     Gold 698        Cache 1,051
--   k/s 2.4         g/s 0.6         Gold Needed 353
-- The box keeps one size: each column is as wide as its cells are with a
-- generous number in them ("00,000"), worked out once for the chosen text
-- size. A number that outgrows its column shrinks its own text to fit, the
-- box staying put. The second row is set a little smaller than the first.
local LINE_GAP = 2
local COLUMN_GAP = 18
local ROWS, COLUMNS = 2, 3
local SECOND_ROW = 0.8          -- the second row's size, against the first's
local SMALLEST = 6              -- the least a cell shrinks to

-- Each cell's widest expected text, sized once to set its column's width.
local TEMPLATES = {
	{ "Kills 000.0k", "Gold 000.0k", "Cache 000.0k" },
	{ "k/s 00.0", "g/s 00.0", "Gold Needed 000.0k" },
}

local cells = {}
for r = 1, ROWS do
	cells[r] = {}
	for c = 1, COLUMNS do
		local cell = box:CreateFontString(nil, "OVERLAY")
		cell:SetFont(FONT, TEXT_SIZE + FONT_BUMP, "OUTLINE")
		cells[r][c] = cell
	end
end

local columnWidth = {}          -- [column] = its fixed width
local rowSize = {}              -- [row] = its text size before any shrinking

-- Simplified keeps the first row alone: kills, gold and the cache.
local function ShownRows()
	return Settings().tallySimple and 1 or ROWS
end

local function SetCellFont(cell, size)
	if cell.size ~= size then
		cell.size = size
		cell:SetFont(FONT, size + FONT_BUMP, "OUTLINE")
	end
end

-- The box's height with both rows, whether or not Simplified shows one: the
-- unmoved box keeps its bottom where the full box's bottom would be.
local fullHeight = 2 * TEXT_SIZE + LINE_GAP + 2 * PAD_Y
local RestorePlace

-- The sizes for the chosen text size, the columns' widths from the templates,
-- and the cells in their places: the box's one size, until the size or
-- Simplified changes.
local function ApplySize()
	local size = TextSize()
	local rows = ShownRows()
	rowSize[1] = size
	rowSize[2] = math.max(SMALLEST, math.floor(size * SECOND_ROW + 0.5))
	local x = PAD_X
	for c = 1, COLUMNS do
		local width = 0
		for r = 1, rows do
			local cell = cells[r][c]
			SetCellFont(cell, rowSize[r])
			cell:SetText(TEMPLATES[r][c])
			width = math.max(width, cell:GetStringWidth())
		end
		columnWidth[c] = width
		local y = -PAD_Y
		for r = 1, ROWS do
			local cell = cells[r][c]
			if r <= rows then
				cell:ClearAllPoints()
				cell:SetPoint("TOP", box, "TOPLEFT", x + width / 2, y)
				cell:Show()
				y = y - rowSize[r] - FONT_BUMP - LINE_GAP
			else
				cell:Hide()
			end
		end
		x = x + width + (c < COLUMNS and COLUMN_GAP or 0)
	end
	box:SetWidth(x + PAD_X)
	local height = 2 * PAD_Y - LINE_GAP
	fullHeight = 2 * PAD_Y - LINE_GAP
	for r = 1, ROWS do
		local line = rowSize[r] + FONT_BUMP + LINE_GAP
		fullHeight = fullHeight + line
		if r <= rows then
			height = height + line
		end
	end
	box:SetHeight(height)
	if RestorePlace then
		RestorePlace()
	end
end

-- A label muted, its value in its color, at its row's size, or smaller if it
-- has outgrown its column.
local function Cell(r, c, label, value, hex)
	local cell = cells[r][c]
	cell:SetText("|cff9a9a9a"..label.."|r |cff"..hex..value.."|r")
	local size = rowSize[r] or TEXT_SIZE
	SetCellFont(cell, size)
	while size > SMALLEST and columnWidth[c] and cell:GetStringWidth() > columnWidth[c] do
		size = size - 1
		SetCellFont(cell, size)
	end
end

-- Kills and gold a second over the last minute of the run's clock, so the
-- rates follow how the run is going now, not its whole length. A sample a
-- second; until there are a few seconds of them, the run so far stands in.
local RATE_WINDOW = 60          -- run seconds the rates are taken over
local RATE_MIN_SPAN = 5
local samples = {}              -- { t = run second, kills, gold earned }
local lastClock

local function Rates(seconds, kills, gold)
	seconds = seconds or 0
	-- The samples live in the run's memory, so a reload keeps the rates going.
	if SurvivorUI_RunMemory then
		local memory = SurvivorUI_RunMemory("tally")
		memory.samples = memory.samples or {}
		samples = memory.samples
	end
	-- The clock going back means a new run: sample afresh.
	if lastClock and seconds + 3 < lastClock then
		samples = {}
		if SurvivorUI_RunMemory then
			SurvivorUI_RunMemory("tally").samples = samples
		end
	end
	lastClock = seconds
	local newest = samples[table.getn(samples)]
	if not newest or seconds - newest.t >= 1 then
		table.insert(samples, { t = seconds, kills = kills, gold = gold })
	end
	while table.getn(samples) > 1 and seconds - samples[1].t > RATE_WINDOW do
		table.remove(samples, 1)
	end
	local first = samples[1]
	local span = seconds - first.t
	if span >= RATE_MIN_SPAN then
		return math.max(0, kills - first.kills) / span, math.max(0, gold - first.gold) / span
	end
	if seconds >= 1 then
		return kills / seconds, gold / seconds
	end
	return 0, 0
end

-- Its place is kept by its bottom middle: the bottom edge stays put, so the
-- box grows and shrinks upward (Simplified takes its second row off the top).
local function SavePlace()
	local x = box:GetCenter()
	local bottom = box:GetBottom()
	if not (x and bottom) then
		return
	end
	local settings = Settings()
	settings.tallyX = math.floor(x + 0.5)
	settings.tallyBottom = math.floor(bottom + 0.5)
	settings.tallyY = nil
	box:ClearAllPoints()
	box:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", settings.tallyX, settings.tallyBottom)
end

-- The saved place; a place saved by its center before is turned into its
-- bottom once. Unmoved, it sits under the middle block, following it, its
-- bottom where the full two-row box's bottom would be.
RestorePlace = function()
	local settings = Settings()
	if settings.tallyX and settings.tallyY and not settings.tallyBottom then
		settings.tallyBottom = math.floor(settings.tallyY - fullHeight / 2 + 0.5)
		settings.tallyY = nil
	end
	box:ClearAllPoints()
	if settings.tallyX and settings.tallyBottom then
		box:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", settings.tallyX, settings.tallyBottom)
	else
		box:SetPoint("BOTTOM", getglobal("SurvivorUIRowBlock") or row, "BOTTOM", 0, -20 - fullHeight)
	end
end
RestorePlace()

local function Running()
	if not (AZS_GetPhase and AZS_RUN) then
		return false
	end
	local phase = AZS_GetPhase()
	return phase and phase ~= "ready"
end

local elapsed = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function()
	elapsed = elapsed + arg1
	if elapsed < 0.2 then
		return
	end
	elapsed = 0

	-- In preview (before the first step, or in edit mode) it shows anyway, so
	-- it can be placed.
	local preview = SurvivorUI_Preview and SurvivorUI_Preview()
	if not (Settings().tally and (Running() or preview)) then
		box:Hide()
		return
	end
	-- Kills white, gold gold; the rates a shade softer, the gold still missing to
	-- the cache in yellow. The cache's price is green once the gold covers it, red until
	-- then. The rates run over the run's own clock, which stops for a pause or a
	-- card choice, and gold counts all earned this run (AZS_RUN.ge), spent or not.
	local run = AZS_RUN or {}
	local seconds = (AZS_GetRunTime and AZS_GetRunTime()) or tonumber(run.t)
	local killRate, goldRate = Rates(seconds, tonumber(run.kills) or 0, tonumber(run.ge or run.gold) or 0)
	local gold, price = tonumber(run.gold) or 0, tonumber(run.chest) or 0
	local missing = math.max(0, price - gold)
	local cacheHex = missing > 0 and "ff6060" or "8cd98c"
	Cell(1, 1, "Kills", Short(run.kills), "ffffff")
	Cell(1, 2, "Gold", Short(run.gold), "ffd24d")
	Cell(1, 3, "Cache", Short(run.chest, true), cacheHex)
	Cell(2, 1, "k/s", string.format("%.1f", killRate), "d8d8d8")
	Cell(2, 2, "g/s", string.format("%.1f", goldRate), "e6c454")
	Cell(2, 3, "Gold Needed", Short(missing, true), "ffe84d")
	box:Show()
end)

if SurvivorUI_RegisterMover then
	SurvivorUI_RegisterMover(box, "Kills & gold", SavePlace, nil, RestorePlace)
end

-- The game's own box: away while this line is on. The setting is the game's
-- and is saved, so the addon remembers that it was the one to turn it off.
local function ApplyGameHud()
	if not (AZS_SetHudShown and AZS_IsHudShown) then
		return
	end
	local settings = Settings()
	if settings.tally then
		if AZS_IsHudShown("tally") then
			AZS_SetHudShown("tally", false)
			settings.hidGameTally = true
		end
	elseif settings.hidGameTally then
		AZS_SetHudShown("tally", true)
		settings.hidGameTally = nil
	end
end

function SurvivorUI_Tally()
	local settings = Settings()
	settings.tally = not settings.tally
	ApplyGameHud()
	DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: "..(settings.tally
		and "kills, gold and cache under the bar; the game's own box is put away."
		or "the game's own kills and gold box is back."))
end

if SurvivorUI_RegisterOption then
	SurvivorUI_RegisterOption({
		section = "Interface",
		label = "Kills and gold line",
		tip = "Kills, gold and the next cache's price under the experience bar, in place of the game's own box.",
		command = "/sui tally",
		get = function() return Settings().tally end,
		toggle = SurvivorUI_Tally,
	})
	SurvivorUI_RegisterOption({
		section = "Interface",
		label = "Simplified",
		parent = "Kills and gold line",
		tip = "The kills and gold line keeps one row: kills, gold and the cache, without the rates and the gold to the next cache.",
		get = function() return Settings().tallySimple end,
		toggle = function()
			local settings = Settings()
			settings.tallySimple = not settings.tallySimple
			ApplySize()
		end,
	})
	SurvivorUI_RegisterOption({
		section = "Interface",
		kind = "slider",
		label = "Kills and gold size",
		parent = "Kills and gold line",
		tip = "The text size of the kills, gold and cache line; its box grows around it.",
		min = TEXT_SIZE_MIN,
		max = TEXT_SIZE_MAX,
		step = 1,
		get = TextSize,
		set = function(size)
			Settings().tallySize = size
			ApplySize()
		end,
	})
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function()
	ApplySize()
	RestorePlace()
	ApplyGameHud()
end)
