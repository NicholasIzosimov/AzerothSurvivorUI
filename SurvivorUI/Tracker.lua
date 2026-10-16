-- Survivor UI: the run timer, after a Mythic+ timer.
--
-- Under the minimap, where a quest log would sit, centered: the zone, how the
-- run stands and the lives left, the time gone against the zone's full length
-- (the time gone alone in endless mode), a green timeline with a tick for
-- every boss, and every boss with the second it comes, colored by where it
-- stands (grey to come, white next, orange alive, green slain). It stands in
-- for the game's own clock, which is put away while it shows. Its size is
-- fixed for the run: every line keeps its place, shown or not, so nothing
-- jumps as the run goes on. The run's level bar is an element of its own
-- (XPBar.lua).
--
-- Needs the game's addon API (AZS_RUN, AZS_SCHEDULE); without it nothing
-- shows. Hold Alt and drag it to move it; the place is kept. /sui timer
-- hides it and brings the game's clock back; /sui timer compact leaves out
-- the list of bosses, keeping the timeline with its ticks and countdowns.
--
-- Best times, as a speedrun timer keeps them: how long each boss took from the
-- moment it came to the moment it fell, kept per class (SurvivorUIDB.bossBests).
-- A boss alive shows its fight's time against the best; a slain one its time,
-- green when it beat the best ("best!"), with the best beside it.
--
-- What it has seen of the bosses (when each came and fell) is kept in the
-- run's memory (SurvivorUI_RunMemory), so a reload in the middle of a run
-- keeps every fight's time instead of starting the bosses over.

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local FONT = SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BUMP = SurvivorUI_FONT_BUMP or 0

local WIDTH = 220
local BOSS_SLOTS = 5             -- lines kept for bosses, more if the zone has more

local function Settings()
	SurvivorUIDB = SurvivorUIDB or {}
	if SurvivorUIDB.tracker == nil then
		SurvivorUIDB.tracker = true
	end
	return SurvivorUIDB
end

-- The game's run, while one is on: AZS_RUN and the phase.
local function Game()
	if AZS_GetPhase and AZS_RUN then
		local phase = AZS_GetPhase()
		if phase and phase ~= "ready" then
			return AZS_RUN, phase
		end
	end
end

local function Num(value)
	return tonumber(value) or 0
end

-- A list entry's field, by name or by place.
local function Field(entry, name, index)
	if entry[name] ~= nil then
		return entry[name]
	end
	return entry[index]
end

local function Clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), math.mod(seconds, 60))
end

-- 950, 1.2k, 3.4m
local function Short(value)
	if value >= 1000000 then
		return string.format("%.1fm", value / 1000000)
	elseif value >= 1000 then
		return string.format("%.1fk", value / 1000)
	end
	return math.floor(value + 0.5)
end

local function Pair(label, value)
	GameTooltip:AddDoubleLine(label, value, 0.7, 0.7, 0.7, 1, 1, 1)
end

------------------------------------------------------------------------------
-- The frame.

local head = CreateFrame("Frame", "SurvivorUITracker", UIParent)
head:SetWidth(WIDTH)
head:SetHeight(100)
if Minimap then
	head:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 0, -30)
else
	head:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -230)
end
head:SetMovable(true)
head:EnableMouse(true)
head:RegisterForDrag("LeftButton")
head:Hide()

-- The right column's one shade, as the build and the meter wear it.
head.shade = head:CreateTexture(nil, "BACKGROUND")
head.shade:SetTexture(FLAT)
head.shade:SetPoint("TOPLEFT", head, "TOPLEFT", -8, 6)
head.shade:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 8, -6)
head.shade:SetVertexColor(0.04, 0.04, 0.07, 0.55)

local function SavePlace()
	local settings = Settings()
	settings.trackerRight = math.floor(head:GetRight() + 0.5)
	settings.trackerTop = math.floor(head:GetTop() + 0.5)
end

local function RestorePlace()
	local settings = Settings()
	if settings.trackerRight then
		head:ClearAllPoints()
		head:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", settings.trackerRight, settings.trackerTop)
	end
end

head:SetScript("OnDragStart", function() if IsAltKeyDown() then head:StartMoving() end end)
head:SetScript("OnDragStop", function() head:StopMovingOrSizing() SavePlace() end)

local function HeadText(size, flags, justify)
	local text = head:CreateFontString(nil, "OVERLAY")
	text:SetFont(FONT, size + FONT_BUMP, flags or "OUTLINE")
	text:SetJustifyH(justify or "CENTER")
	return text
end

local function HeadBar(height)
	local bar = CreateFrame("StatusBar", nil, head)
	bar:SetWidth(WIDTH)
	bar:SetHeight(height)
	bar:SetStatusBarTexture(FLAT)
	bar:SetMinMaxValues(0, 1)
	bar.backing = bar:CreateTexture(nil, "BACKGROUND")
	bar.backing:SetTexture(FLAT)
	bar.backing:SetVertexColor(0.12, 0.12, 0.15, 0.9)
	bar.backing:SetAllPoints(bar)
	return bar
end

head.zone = HeadText(12)
head.state = HeadText(9)
head.clock = HeadText(18, "THICKOUTLINE")
head.timeline = HeadBar(8)
head.timeline:SetStatusBarColor(0.30, 0.80, 0.35, 1)
head.ticks = {}
head.bosses = {}

-- Across the frame at y, centered; returns the y under it.
local function Put(object, y, height)
	object:ClearAllPoints()
	object:SetPoint("TOP", head, "TOP", 0, y)
	object:Show()
	return y - height
end

-- A boss's color says where it stands, as in a Mythic+ timer: grey still to
-- come, white the next one, orange alive, green slain.
local STATE_COLORS = {
	due  = { 0.55, 0.55, 0.55 },
	next = { 1.00, 1.00, 1.00 },
	up   = { 1.00, 0.55, 0.25 },
	dead = { 0.30, 0.85, 0.35 },
}
local WAITING = STATE_COLORS.due

local function Hex(color)
	return string.format("|cff%02x%02x%02x", math.floor(color[1] * 255), math.floor(color[2] * 255), math.floor(color[3] * 255))
end

------------------------------------------------------------------------------
-- The bosses.

local lastSeconds
local bossSeenUp = {}             -- [boss] = true once seen alive
local bossKilled = {}             -- [boss] = the run second it was seen to fall
local bossSeenDue = {}            -- [boss] = true once seen still to come
local bossUpAt = {}               -- [boss] = the run second it was first seen alive
local bossFight = {}              -- [boss] = { time, best before it, beat }, once it fell

-- The tables above, from the run's memory as it stands.
local function Remember()
	if not SurvivorUI_RunMemory then
		return
	end
	local memory = SurvivorUI_RunMemory("tracker")
	memory.seenUp = memory.seenUp or {}
	memory.killed = memory.killed or {}
	memory.seenDue = memory.seenDue or {}
	memory.upAt = memory.upAt or {}
	memory.fight = memory.fight or {}
	bossSeenUp, bossKilled, bossSeenDue = memory.seenUp, memory.killed, memory.seenDue
	bossUpAt, bossFight = memory.upAt, memory.fight
end

-- The bosses' schedule (AZS_SCHEDULE) and the zone's facts (AZS_ZONE) come
-- from the game when they change, not again after a reload, which left the
-- timeline without its ticks and the bosses' list empty until the next boss
-- came. The last ones seen are kept in the run's memory and stand in until
-- the game sends them again; a new run lets them go with the rest of it.
local function Kept(name, live)
	if live and next(live) ~= nil then
		if SurvivorUI_RunMemory then
			SurvivorUI_RunMemory("tracker")[name] = live
		end
		return live
	end
	local memory = SurvivorUI_RunMemory and SurvivorUI_RunMemory("tracker")
	return memory and memory[name] or live or {}
end

local function Schedule()
	return Kept("schedule", AZS_SCHEDULE)
end

local function Zone()
	return Kept("zone", AZS_ZONE)
end

-- Best times are kept per class and boss name: { [class] = { [boss] = seconds } }.
local function BestsShown()
	return Settings().trackerBests ~= false
end

local function ClassBests()
	local settings = Settings()
	settings.bossBests = settings.bossBests or {}
	local _, class = UnitClass("player")
	class = class or "UNKNOWN"
	settings.bossBests[class] = settings.bossBests[class] or {}
	return settings.bossBests[class]
end

-- A fight is counted only when the boss was seen coming, so a reload in the
-- middle of one cannot pass a short time off as the best.
local function RecordFight(key, name)
	if bossFight[key] or not (bossSeenDue[key] and bossUpAt[key] and bossKilled[key]) then
		return
	end
	local time = bossKilled[key] - bossUpAt[key]
	if time <= 0 then
		return
	end
	local bests = ClassBests()
	local best = bests[name]
	local beat = not best or time < best
	if beat then
		bests[name] = time
	end
	bossFight[key] = { time = time, best = best, beat = beat }
end

-- The boss alive under this name, for its health.
local function LiveBoss(name)
	if not AZS_UNITS then
		return nil
	end
	for index = 1, table.getn(AZS_UNITS) do
		local unit = AZS_UNITS[index]
		local kind = Field(unit, "kind", 1)
		if (kind == "boss" or kind == "final") and Field(unit, "name", 3) == name then
			return unit
		end
	end
end

-- A boss line: the name on the left, the second it comes on the right.
local function BossLine(index)
	local line = head.bosses[index]
	if not line then
		line = CreateFrame("Frame", nil, head)
		line:SetWidth(WIDTH)
		line:SetHeight(13)
		line.name = line:CreateFontString(nil, "OVERLAY")
		line.name:SetFont(FONT, 9 + FONT_BUMP, "OUTLINE")
		line.name:SetPoint("LEFT", line, "LEFT", 0, 0)
		line.name:SetJustifyH("LEFT")
		line.time = line:CreateFontString(nil, "OVERLAY")
		line.time:SetFont(FONT, 9 + FONT_BUMP, "OUTLINE")
		line.time:SetPoint("RIGHT", line, "RIGHT", 0, 0)
		line.time:SetJustifyH("RIGHT")
		head.bosses[index] = line
	end
	return line
end

-- Grey until it falls, then in its own color. Alive, its health shows by the
-- time; the next to come says how long.
local function FillBossLine(line, entry, index, seconds, isNext)
	local name = Field(entry, "name", 3) or "?"
	local at = Num(Field(entry, "at", 2))
	local state = Field(entry, "state", 5) or "due"
	local key = index..name
	if state == "due" then
		bossSeenDue[key] = true
	elseif state == "up" then
		bossSeenUp[key] = true
		bossUpAt[key] = bossUpAt[key] or seconds
	elseif state == "dead" and bossSeenUp[key] and not bossKilled[key] then
		bossKilled[key] = seconds
		RecordFight(key, name)
	end
	local best = ClassBests()[name]
	local bests = BestsShown()

	line.name:SetText(name)
	if state == "dead" then
		local color = STATE_COLORS.dead
		line.name:SetTextColor(color[1], color[2], color[3])
		-- With best times: how long the fight took, green when it beat the
		-- best, and the best beside it. Otherwise the second it came, and the
		-- second it fell when that was seen.
		local fight = bossFight[key]
		if bests and fight then
			if fight.beat then
				line.time:SetText("|cff4dff4dbest!|r  "..Clock(fight.time)..(fight.best and "  |cff8a8a8a"..Clock(fight.best).."|r" or ""))
			else
				line.time:SetText("|cffffffff"..Clock(fight.time).."|r  |cff8a8a8abest "..Clock(fight.best).."|r")
			end
		elseif bossKilled[key] then
			line.time:SetText("|cff8a8a8a"..Clock(at).."  /|r  "..Clock(bossKilled[key]))
		else
			line.time:SetText(Clock(at))
		end
		line.time:SetTextColor(color[1], color[2], color[3])
	elseif state == "up" then
		local color = STATE_COLORS.up
		line.name:SetTextColor(color[1], color[2], color[3])
		local share = ""
		local unit = LiveBoss(name)
		if unit then
			local hpm = Num(Field(unit, "hpm", 5))
			if hpm > 0 then
				share = math.floor(Num(Field(unit, "hp", 4)) / hpm * 100 + 0.5).."%   "
			end
			if Num(Field(unit, "state", 6)) == 1 then
				share = "|cffff4040enraged|r  "..share
			end
		end
		if bests and bossUpAt[key] then
			-- The fight's time so far, red once it is behind the best.
			local time = seconds - bossUpAt[key]
			local behind = best and time > best
			line.time:SetText("|cffff8c40"..share.."|r"..(behind and "|cffff5050" or "|cffffffff")..Clock(time).."|r"
				..(best and "  |cff8a8a8a"..Clock(best).."|r" or ""))
		else
			line.time:SetText("|cffff8c40"..share.."|r"..Clock(at))
		end
		line.time:SetTextColor(1, 1, 1)
	else
		local color = isNext and STATE_COLORS.next or WAITING
		line.name:SetTextColor(color[1], color[2], color[3])
		if isNext then
			line.time:SetText("|cffffd24din "..Clock(at - seconds).."|r   "..Clock(at))
		else
			line.time:SetText(Clock(at))
		end
		line.time:SetTextColor(color[1], color[2], color[3])
	end
	line:Show()
end

------------------------------------------------------------------------------
-- Drawing.

local function Draw(game, phase)
	local zone = Zone()
	local seconds = (AZS_GetRunTime and AZS_GetRunTime()) or Num(game.t)
	-- The run's memory lets the last run's bosses go when a new one starts.
	Remember()
	lastSeconds = seconds

	-- The zone's facts come once a run, and can be missed (a restart mid-run):
	-- then the client's own zone name, and the run's length from AZS_RUN.
	local zoneName = zone.zname
	if not zoneName or zoneName == "" then
		zoneName = (GetRealZoneText and GetRealZoneText()) or GetZoneText() or ""
	end

	-- Compact: the zone, the clock and the timeline with its ticks and
	-- countdowns; no list of bosses.
	local compact = Settings().trackerCompact

	local y = 0
	head.zone:SetText(zoneName)
	head.zone:SetTextColor(1, 0.82, 0)
	y = Put(head.zone, y, 15)

	-- How the run stands: won, fallen or endless, and the lives left, small in
	-- the top right corner, so it takes no line of its own.
	local parts = {}
	if phase == "victory" then
		table.insert(parts, "|cff4dd94dVictory|r")
	elseif phase == "dead" then
		table.insert(parts, "|cffff4040Fallen|r")
	elseif phase == "paused" then
		table.insert(parts, "|cff9a9a9aPaused|r")
	elseif phase == "choosing" then
		table.insert(parts, "|cff9a9a9aChoosing|r")
	elseif Num(game.endl) == 1 then
		table.insert(parts, "|cffd080ffEndless|r")
	end
	local lives = Num(game.lives)
	if lives > 0 then
		table.insert(parts, "|cffff8080"..lives..(lives == 1 and " life" or " lives").." left|r")
	end
	head.state:SetText(table.concat(parts, "  "))
	head.state:ClearAllPoints()
	head.state:SetPoint("TOPRIGHT", head, "TOPRIGHT", 0, -20)
	head.state:Show()

	-- Elapsed / the zone's full length, the time to victory. In endless mode,
	-- once chosen, the elapsed time alone.
	local length = Num(zone.len)
	if length <= 0 and AZS_GetRunLength then
		length = Num(AZS_GetRunLength())
	end
	if length <= 0 then
		length = Num(game.fin)
	end
	local endless = Num(game.endl) == 1
	if endless or length <= 0 then
		head.clock:SetText(Clock(seconds))
	else
		head.clock:SetText(Clock(seconds).." |cff8a8a8a/|r |cffb0b0b0"..Clock(length).."|r")
	end
	if phase == "paused" or phase == "choosing" then
		head.clock:SetTextColor(0.6, 0.6, 0.6)
	else
		head.clock:SetTextColor(1, 1, 1)
	end
	y = Put(head.clock, y - 1, 24)
	-- Room over the timeline for each coming boss's countdown.
	y = y - 10

	-- The timeline: green up to now, each boss's tick in its own color.
	head.timeline:SetValue(length > 0 and math.min(1, seconds / length) or 1)
	if endless then
		head.timeline:SetStatusBarColor(0.70, 0.40, 1.00, 1)
	else
		head.timeline:SetStatusBarColor(0.30, 0.80, 0.35, 1)
	end
	y = Put(head.timeline, y, 15)

	local schedule = Schedule()
	local count = table.getn(schedule)
	-- The same number of lines all run long: the zone's bosses, at least five.
	-- Compact keeps none.
	local slots = compact and 0 or math.max(BOSS_SLOTS, Num(zone.bt), count)
	local nextShown = false
	for index = 1, count do
		local entry = schedule[index]
		local state = Field(entry, "state", 5) or "due"
		local isNext = state == "due" and not nextShown
		if isNext then
			nextShown = true
		end
		-- A tick is white until its boss is slain, then green.
		local color = state == "dead" and STATE_COLORS.dead or STATE_COLORS.next
		local final = Num(Field(entry, "final", 4)) == 1

		local tick = head.ticks[index]
		if not tick then
			tick = head.timeline:CreateTexture(nil, "OVERLAY")
			tick:SetTexture(FLAT)
			tick:SetWidth(3)
			tick:SetHeight(14)
			head.ticks[index] = tick
		end
		local at = Num(Field(entry, "at", 2))
		-- The final boss's tick is a little heavier.
		tick:SetWidth(final and 5 or 3)
		tick:ClearAllPoints()
		tick:SetPoint("CENTER", head.timeline, "LEFT", length > 0 and WIDTH * math.min(1, at / length) or WIDTH, 0)
		tick:SetVertexColor(color[1], color[2], color[3], 1)
		tick:Show()

		-- Over a boss still to come, small and yellow, the time until it does.
		if not tick.label then
			tick.label = head.timeline:CreateFontString(nil, "OVERLAY")
			tick.label:SetFont(FONT, 8 + FONT_BUMP, "OUTLINE")
		end
		-- The next boss's countdown in orange, the later ones in yellow.
		if isNext then
			tick.label:SetTextColor(1, 0.55, 0.15)
		else
			tick.label:SetTextColor(1, 0.82, 0.2)
		end
		if state == "due" and at > seconds then
			-- Over its tick, kept inside the box at the ends.
			tick.label:SetText(Clock(at - seconds))
			local half = tick.label:GetStringWidth() / 2 + 1
			local x = length > 0 and WIDTH * math.min(1, at / length) or WIDTH
			x = math.max(half, math.min(WIDTH - half, x))
			tick.label:ClearAllPoints()
			tick.label:SetPoint("BOTTOM", head.timeline, "TOPLEFT", x, 4)
			tick.label:Show()
		else
			tick.label:Hide()
		end

		-- Filled even when compact hides it: it keeps track of when each boss fell.
		local line = BossLine(index)
		FillBossLine(line, entry, index, seconds, isNext)
		if compact then
			line:Hide()
		else
			y = Put(line, y, 13)
		end
	end
	for index = count + 1, table.getn(head.ticks) do
		head.ticks[index]:Hide()
		if head.ticks[index].label then
			head.ticks[index].label:Hide()
		end
	end
	for index = count + 1, table.getn(head.bosses) do
		head.bosses[index]:Hide()
	end
	-- Empty lines keep their room.
	if not compact then
		y = y - (slots - count) * 13
	end

	-- Endless mode: the schedule is spent and bosses return on a timer, so one
	-- more line, kept all run long, says when the next comes: one text,
	-- centered, "Next boss  in 4:08".
	local nextLine = head.nextBoss
	if not nextLine then
		nextLine = BossLine(table.getn(head.bosses) + 1)
		head.bosses[table.getn(head.bosses)] = nil
		head.nextBoss = nextLine
		nextLine.name:ClearAllPoints()
		nextLine.name:SetPoint("CENTER", nextLine, "CENTER", 0, 0)
		nextLine.name:SetJustifyH("CENTER")
		nextLine.time:Hide()
	end
	local nextIn = tonumber(game.nb) or -1
	if Num(game.endl) == 1 and nextIn >= 0 then
		local name = game.nbn
		if not name or name == "" then
			name = "Next boss"
		end
		nextLine.name:SetText(name.."  |cffffd24din "..Clock(nextIn).."|r")
		nextLine.name:SetTextColor(1, 1, 1)
		y = Put(nextLine, y, 13)
	else
		nextLine:Hide()
		if not compact then
			y = y - 13
		end
	end
	head:SetHeight(-y)
end
-- The run to draw: the game's, or in preview (before the first step, or with
-- Alt held) whatever it has shared so far, so the timer can be placed.
local function Shown()
	local game, phase = Game()
	if not game and SurvivorUI_Preview and SurvivorUI_Preview() then
		return AZS_RUN or {}, "ready"
	end
	return game, phase
end

local elapsed = 0
head:SetScript("OnUpdate", function()
	elapsed = elapsed + arg1
	if elapsed < 0.1 then
		return
	end
	elapsed = 0
	local game, phase = Shown()
	if game then
		Draw(game, phase)
	end
end)

-- The frame's own OnUpdate stops while it is hidden, so a watcher shows it.
local watcher = CreateFrame("Frame")
local watched = 0
watcher:SetScript("OnUpdate", function()
	watched = watched + arg1
	if watched < 0.25 then
		return
	end
	watched = 0
	local game, phase = Shown()
	local showing = game and Settings().tracker
	if showing then
		if not head:IsShown() then
			Draw(game, phase)
			head:Show()
		end
	elseif head:IsShown() then
		head:Hide()
	end
end)

------------------------------------------------------------------------------
-- More on hover: the time to the final boss, the run's settings.

local MOD_NAMES = { "Enemy density", "Enemy health", "Enemy damage", "Enemy speed" }
head:SetScript("OnEnter", function()
	local game = Game()
	if not game then
		return
	end
	local zone = Zone()
	GameTooltip:SetOwner(this, "ANCHOR_LEFT")
	GameTooltip:SetText(zone.zname or "This run", 1, 0.82, 0)
	if Num(game.endl) == 1 then
		GameTooltip:AddLine("Endless mode: bosses return on a timer.", 0.85, 0.5, 1, 1)
	elseif Num(game.left) >= 0 then
		Pair("Final boss in", Clock(Num(game.left)))
	end
	Pair("Bosses so far", Num(game.bs).." / "..Num(game.bt))
	Pair("Lairs on the map", Num(game.lairs))
	-- This class's best fight against each of the zone's bosses.
	local schedule = Schedule()
	if BestsShown() and table.getn(schedule) > 0 then
		local bests = ClassBests()
		local className = UnitClass("player") or "this class"
		GameTooltip:AddLine("Best times ("..className..")", 1, 0.82, 0)
		local listed = {}
		for index = 1, table.getn(schedule) do
			local name = Field(schedule[index], "name", 3)
			if name and not listed[name] then
				listed[name] = true
				Pair(name, bests[name] and Clock(bests[name]) or "-")
			end
		end
	end
	if tonumber(zone.diff) and tonumber(zone.diff) ~= 1 then
		Pair("Zone difficulty", "x"..zone.diff)
	end
	-- "100 100 100 100" is a normal run; anything else is worth a line.
	if zone.mods then
		local index = 0
		for value in string.gfind(zone.mods, "%d+") do
			index = index + 1
			if MOD_NAMES[index] and value ~= "100" then
				Pair(MOD_NAMES[index], value.."%")
			end
		end
	end
	GameTooltip:AddLine("Hold Alt and drag to move. /sui timer hides it.", 0.7, 0.7, 0.7, 1)
	GameTooltip:Show()
end)
head:SetScript("OnLeave", function() GameTooltip:Hide() end)

------------------------------------------------------------------------------
-- The game's own clock and "next boss" line: away while the timer stands in
-- for them. The setting is the game's and is saved, so the addon remembers
-- that it was the one to turn it off.

local function ApplyGameHud()
	if not (AZS_SetHudShown and AZS_IsHudShown) then
		return
	end
	local settings = Settings()
	if settings.tracker then
		if AZS_IsHudShown("clock") then
			AZS_SetHudShown("clock", false)
			settings.hidGameClock = true
		end
	elseif settings.hidGameClock then
		AZS_SetHudShown("clock", true)
		settings.hidGameClock = nil
	end
end

function SurvivorUI_ToggleTracker()
	local settings = Settings()
	settings.tracker = not settings.tracker
	ApplyGameHud()
	DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: "..(settings.tracker
		and "run timer on; the game's own clock is put away."
		or "run timer off; the game's own clock is back."))
end

function SurvivorUI_ToggleTrackerCompact()
	local settings = Settings()
	settings.trackerCompact = not settings.trackerCompact
	DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: run timer "..(settings.trackerCompact
		and "compact: the timeline without the list of bosses."
		or "in full: the zone, the bosses and their timeline."))
end

if SurvivorUI_RegisterOption then
	SurvivorUI_RegisterOption({
		section = "General",
		label = "Run timer",
		tip = "The clock and the bosses' timeline under the minimap, in place of the game's own clock.",
		command = "/sui timer",
		get = function() return Settings().tracker end,
		toggle = SurvivorUI_ToggleTracker,
	})
	SurvivorUI_RegisterOption({
		section = "General",
		label = "Best boss times",
		parent = "Run timer",
		tip = "Like a speedrun timer: each boss's fight, from the moment it comes to the moment it falls, timed against your best on that boss with this class. Green \"best!\" when you beat it. Hover the timer for every best in the zone.",
		get = BestsShown,
		toggle = function()
			Settings().trackerBests = not BestsShown()
		end,
	})
	SurvivorUI_RegisterOption({
		section = "General",
		label = "Compact run timer",
		parent = "Run timer",
		tip = "The run timer leaves out the list of bosses: the zone, the clock, and the timeline with each boss's tick and countdown.",
		command = "/sui timer compact",
		get = function() return Settings().trackerCompact end,
		toggle = SurvivorUI_ToggleTrackerCompact,
	})
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function()
	RestorePlace()
	ApplyGameHud()
end)

if SurvivorUI_RegisterMover then
	SurvivorUI_RegisterMover(head, "Run timer", SavePlace, nil, function()
		head:ClearAllPoints()
		if Minimap then
			head:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 0, -30)
		else
			head:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -230)
		end
	end)
end
