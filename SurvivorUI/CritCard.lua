-- Survivor UI: the card beside a damage meter line.
--
-- Hover a line of the damage meter (Meter.lua) for its card, kept short: what
-- one cast of it deals on average, and the targets it has hit as small meter
-- bars. Both counted here from the combat log. The meter's other views have
-- cards of their own, from the log too: healing, what one cast heals on
-- average and who it healed; damage taken, an enemy's average hit and what it
-- hit you with (melee and each spell). The meter's Reset clears its view's
-- tally (SurvivorUI_ResetRun); a new run clears them all. The tally is kept in the run's
-- memory (SurvivorUI_RunMemory), so a reload in the middle of a run keeps it.
-- Each ability's average cast also goes to the Lexicon, which keeps the best
-- one a run has reached (SurvivorUI_LexiconAverage).

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local FONT = SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BUMP = SurvivorUI_FONT_BUMP or 0

-- Blows of one spell this close together are one cast: an area spell lands on
-- every target in the same instant.
local CAST_WINDOW = 0.15

------------------------------------------------------------------------------
-- The tally.

-- A tally per view of the meter, each { casts, targets }:
--   damage   casts [ability] = { sum, count, at }, targets [ability] = { [target] = damage }
--   healing  casts [ability] = { sum, count, at }, targets [ability] = { [target] = healing }
--   taken    casts [enemy] = { sum, count } (its hits), targets [enemy] = { [ability] = damage }
local VIEWS = { "damage", "healing", "taken" }
local tallies = { damage = { casts = {}, targets = {} }, healing = { casts = {}, targets = {} },
	taken = { casts = {}, targets = {} } }
local casts, targetDamage = tallies.damage.casts, tallies.damage.targets
local logNames = {}             -- [ability] = blows seen under that name, for /sui icons

-- The tallies from the run's memory, as they stand. The damage tally keeps
-- the place it had before the other views came, so a reload keeps it.
local function Remember()
	if not SurvivorUI_RunMemory then
		return
	end
	local memory = SurvivorUI_RunMemory("crits")
	memory.casts = memory.casts or {}
	memory.targets = memory.targets or {}
	tallies.damage = { casts = memory.casts, targets = memory.targets }
	for _, view in pairs({ "healing", "taken" }) do
		memory[view] = memory[view] or { casts = {}, targets = {} }
		tallies[view] = memory[view]
	end
	casts, targetDamage = tallies.damage.casts, tallies.damage.targets
end

local function Tally(view)
	return tallies[view] or tallies.damage
end

-- Every ability name the combat log has given a blow, with how many: a meter
-- line whose name is missing here has no blows in the log to build a card from.
function SurvivorUI_LogNames()
	return logNames
end

-- One view's tally starts over, or every view's with none named.
local function ResetCrits(view)
	for _, name in pairs(VIEWS) do
		if not view or view == name then
			tallies[name] = { casts = {}, targets = {} }
			if SurvivorUI_RunMemory then
				local memory = SurvivorUI_RunMemory("crits")
				if name == "damage" then
					memory.casts, memory.targets = tallies[name].casts, tallies[name].targets
				else
					memory[name] = tallies[name]
				end
			end
		end
	end
	casts, targetDamage = tallies.damage.casts, tallies.damage.targets
end

local function Num(value)
	return tonumber(value) or 0
end

-- 950, 1k, 1.2k, 3.4m
local function Short(value)
	local short, suffix
	if value >= 1000000 then
		short, suffix = value / 1000000, "m"
	elseif value >= 1000 then
		short, suffix = value / 1000, "k"
	else
		return math.floor(value + 0.5)
	end
	local text = string.format("%.1f", short)
	text = string.gsub(text, "%.0$", "")
	return text..suffix
end

local function Average(stats)
	if not stats or stats.count == 0 then
		return "-"
	end
	return Short(stats.sum / stats.count)
end

-- The game's run, while one is on.
local function Game()
	if AZS_GetPhase and AZS_RUN then
		local phase = AZS_GetPhase()
		if phase and phase ~= "ready" then
			return AZS_RUN, phase
		end
	end
end

------------------------------------------------------------------------------
-- The card: the average cast over a thin rule in the spell's color, then its
-- targets as bars.

local TIP_WIDTH = 170
local TIP_ROW = 16

local critTip = CreateFrame("Frame", "SurvivorUICritTip", UIParent)
critTip:SetFrameStrata("TOOLTIP")
if critTip.SetClampedToScreen then
	critTip:SetClampedToScreen(true)
end
critTip:SetWidth(TIP_WIDTH + 16)
critTip:Hide()

critTip.edge = critTip:CreateTexture(nil, "BACKGROUND")
critTip.edge:SetTexture(FLAT)
critTip.edge:SetPoint("TOPLEFT", critTip, "TOPLEFT", -1, 1)
critTip.edge:SetPoint("BOTTOMRIGHT", critTip, "BOTTOMRIGHT", 1, -1)

critTip.fill = critTip:CreateTexture(nil, "BORDER")
critTip.fill:SetTexture(FLAT)
critTip.fill:SetVertexColor(0.05, 0.05, 0.07, 0.97)
critTip.fill:SetAllPoints(critTip)

critTip.title = critTip:CreateFontString(nil, "OVERLAY")
critTip.title:SetFont(FONT, 12 + FONT_BUMP, "OUTLINE")
critTip.title:SetPoint("TOPLEFT", critTip, "TOPLEFT", 8, -8)

critTip.lines = {}

-- kind: "row" label and value, "head" a section title over a heavier rule.
local function TipLine(index, kind, label, value, color)
	local line = critTip.lines[index]
	if not line then
		line = CreateFrame("Frame", nil, critTip)
		line:SetWidth(TIP_WIDTH)
		line:SetHeight(TIP_ROW)
		line.rule = line:CreateTexture(nil, "ARTWORK")
		line.rule:SetTexture(FLAT)
		line.rule:SetHeight(1)
		line.rule:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", 0, 0)
		line.rule:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT", 0, 0)
		line.label = line:CreateFontString(nil, "OVERLAY")
		line.label:SetFont(FONT, 10 + FONT_BUMP)
		line.label:SetPoint("LEFT", line, "LEFT", 2, 0)
		line.value = line:CreateFontString(nil, "OVERLAY")
		line.value:SetFont(FONT, 11 + FONT_BUMP, "OUTLINE")
		line.value:SetPoint("RIGHT", line, "RIGHT", -2, 0)
		critTip.lines[index] = line
	end

	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", critTip, "TOPLEFT", 8, -26 - (index - 1) * TIP_ROW)
	line.label:SetText(label)
	line.value:SetText(value or "")
	if kind == "head" then
		line.label:SetTextColor(color[1], color[2], color[3])
		line.rule:SetVertexColor(color[1], color[2], color[3], 0.75)
	else
		line.label:SetTextColor(0.80, 0.80, 0.80)
		line.value:SetTextColor(1, 1, 1)
		line.rule:SetVertexColor(color[1], color[2], color[3], 0.22)
	end
	line:Show()
end

-- The targets a spell has hit, as the damage meter draws its lines: a flat bar
-- in the spell's color, as long as its share of the most hit target's, the
-- name on it and the damage and share on its right. Eight at most.
local TARGET_BAR = 14
local TARGET_GAP = 2
local TARGETS_SHOWN = 8

critTip.bars = {}

local function TargetBar(index)
	local bar = critTip.bars[index]
	if bar then
		return bar
	end
	bar = CreateFrame("StatusBar", nil, critTip)
	bar:SetWidth(TIP_WIDTH)
	bar:SetHeight(TARGET_BAR)
	bar:SetStatusBarTexture(FLAT)
	bar:SetMinMaxValues(0, 1)
	bar.backing = bar:CreateTexture(nil, "BACKGROUND")
	bar.backing:SetTexture(FLAT)
	bar.backing:SetVertexColor(0.10, 0.10, 0.13, 0.9)
	bar.backing:SetAllPoints(bar)
	bar.name = bar:CreateFontString(nil, "OVERLAY")
	bar.name:SetFont(FONT, 9 + FONT_BUMP, "OUTLINE")
	bar.name:SetPoint("LEFT", bar, "LEFT", 4, 0)
	bar.name:SetWidth(TIP_WIDTH - 70)
	bar.name:SetHeight(12)
	bar.name:SetJustifyH("LEFT")
	bar.name:SetTextColor(1, 1, 1)
	bar.value = bar:CreateFontString(nil, "OVERLAY")
	bar.value:SetFont(FONT, 9 + FONT_BUMP, "OUTLINE")
	bar.value:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
	bar.value:SetTextColor(1, 1, 1)
	critTip.bars[index] = bar
	return bar
end

-- A line's bars, the most first, and the amount over them all: a spell's
-- targets, or for damage taken an enemy's abilities.
local function Targets(tally, ability)
	local list, total = {}, 0
	for name, damage in pairs(tally.targets[ability] or {}) do
		table.insert(list, { name = name, damage = damage })
		total = total + damage
	end
	table.sort(list, function(a, b) return a.damage > b.damage end)
	return list, total
end

local critHovered = nil

-- Each view's words: its rate's, and for a line with nothing in the log (a
-- proc), its total's.
local RATE_LABEL = { damage = "DPS", healing = "HPS", taken = "DTPS" }
local TOTAL_LABEL = { damage = "Damage", healing = "Healing", taken = "Damage taken" }

local function CritTooltip(row)
	local ability = row.ability
	local view = row.mode or "damage"
	local tally = Tally(view)
	local casts = tally.casts
	local targets, targetTotal = Targets(tally, ability)
	-- A proc's blows reach no combat log, so it has no casts or targets to
	-- show: its card holds the meter line's own numbers instead.
	local fromMeter = ability and not casts[ability] and row.damage
	if not (ability and (casts[ability] or fromMeter)) then
		critTip:Hide()
		return
	end
	local color = row.color or { 0.8, 0.8, 0.8 }

	-- A proc goes by "The Reaper's Amulet: Eviscerate": the card is titled by
	-- the ability, as any other line's.
	local title = ability
	if fromMeter and view ~= "taken" then
		local _, _, from, name = string.find(ability, "^(.-): (.+)$")
		if from then
			title = name
		end
	end
	critTip.edge:SetVertexColor(color[1], color[2], color[3], 0.8)
	critTip.title:SetText(title)
	critTip.title:SetTextColor(color[1], color[2], color[3])

	local count = 0
	local function Add(kind, label, value)
		count = count + 1
		TipLine(count, kind, label, value, color)
	end
	-- The line's own rate, from the meter (since Reset, or the whole run),
	-- first; a proc's card has its damage under it. Its source is on the
	-- meter's own line, so the card leaves it out.
	Add("row", RATE_LABEL[view] or "DPS", Short(Num(row.rate)))
	if not casts[ability] then
		Add("row", TOTAL_LABEL[view] or "Damage", Short(Num(row.damage)))
	end
	-- As wide as its words need, never narrower than the bars.
	local wide = math.max(critTip.title:GetStringWidth() + 4, TIP_WIDTH)
	for index = 1, count do
		local line = critTip.lines[index]
		wide = math.max(wide, line.label:GetStringWidth() + line.value:GetStringWidth() + 16)
	end
	critTip:SetWidth(wide + 16)
	for index = 1, count do
		critTip.lines[index]:SetWidth(wide)
	end

	local shownTargets = math.min(TARGETS_SHOWN, table.getn(targets))
	for index = count + 1, table.getn(critTip.lines) do
		critTip.lines[index]:Hide()
	end

	local barsTop = 26 + count * TIP_ROW + 4
	local top = shownTargets > 0 and targets[1].damage or 0
	for index = 1, shownTargets do
		local target = targets[index]
		local bar = TargetBar(index)
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", critTip, "TOPLEFT", 8, -barsTop - (index - 1) * (TARGET_BAR + TARGET_GAP))
		bar:SetValue(top > 0 and target.damage / top or 0)
		bar:SetStatusBarColor(color[1], color[2], color[3], 0.85)
		bar.name:SetText(target.name)
		bar.value:SetText(Short(target.damage).."  |cffb0b0b0"
			..math.floor(target.damage / math.max(1, targetTotal) * 100 + 0.5).."%|r")
		bar:Show()
	end
	for index = shownTargets + 1, table.getn(critTip.bars) do
		critTip.bars[index]:Hide()
	end

	local height = 26 + count * TIP_ROW + 8
	if shownTargets > 0 then
		height = barsTop + shownTargets * (TARGET_BAR + TARGET_GAP) + 6
	end
	critTip:SetHeight(height)
	-- Beside the window the row belongs to, top edges together, on its left
	-- (the right column sits at the screen's edge), or on its right when the
	-- row asks.
	critTip:ClearAllPoints()
	if row.cardRight then
		critTip:SetPoint("TOPLEFT", row.cardFrame or row, "TOPRIGHT", 6, 0)
	else
		critTip:SetPoint("TOPRIGHT", row.cardFrame or row, "TOPLEFT", -6, 0)
	end
	critTip:Show()
end

-- The card, for the damage meter's lines. frame.ability is the source's name;
-- frame.color and frame.cardFrame (the window to sit beside) are optional.
function SurvivorUI_CritCardShow(frame)
	Remember()
	critHovered = frame
	CritTooltip(frame)
end

function SurvivorUI_CritCardHide()
	critHovered = nil
	critTip:Hide()
end

-- The meter's Reset: its view's tally starts over (every view's with none named).
function SurvivorUI_ResetRun(view)
	ResetCrits(view)
end

------------------------------------------------------------------------------
-- Keeping it current.

local elapsed = 0
local lastGameT                  -- the game's clock last seen, to notice a new run
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function()
	-- The game's clock going back means a new run: the tally starts over.
	local game = Game()
	if game then
		local now = Num(game.t)
		if lastGameT and now + 3 < lastGameT then
			ResetCrits()
		end
		lastGameT = now
	end

	-- A reset can take a line away from under the mouse; its card goes with it.
	if critTip:IsVisible() and not (critHovered and critHovered:IsVisible() and critHovered.ability) then
		critHovered = nil
		critTip:Hide()
	end

	elapsed = elapsed + arg1
	if elapsed < 0.25 then
		return
	end
	elapsed = 0
	if critHovered and critTip:IsVisible() then
		CritTooltip(critHovered)
	end
end)

------------------------------------------------------------------------------
-- Reading the combat log: every blow the hero (or a pet) lands, as
-- { ability, target, amount } captures, crits and hits alike. A damage over
-- time tick names its target first ("Kobold Vermin suffers 12 Fire damage
-- from your Flame Shock.").

local BLOWS = {
	{ "^Your (.+) crits (.+) for (%d+)", 1, 2, 3, "crit" },
	{ "^Your (.+) hits (.+) for (%d+)", 1, 2, 3, "hit" },
	{ "^You crit (.+) for (%d+)", nil, 1, 2, "crit" },
	{ "^You hit (.+) for (%d+)", nil, 1, 2, "hit" },
	{ "^.+'s (.+) crits (.+) for (%d+)", 1, 2, 3, "crit" },
	{ "^.+'s (.+) hits (.+) for (%d+)", 1, 2, 3, "hit" },
	{ "^(.+) crits (.+) for (%d+)", 1, 2, 3, "crit" },
	{ "^(.+) hits (.+) for (%d+)", 1, 2, 3, "hit" },
	{ "^(.+) suffers (%d+) .- from your (.+)%.", 3, 1, 2, "tick" },
}

local function Add(list, ability, amount)
	local stats = list[ability]
	if not stats then
		stats = { sum = 0, count = 0 }
		list[ability] = stats
	end
	stats.sum = stats.sum + amount
	stats.count = stats.count + 1
	return stats
end

local function Record(message)
	Remember()
	for index = 1, table.getn(BLOWS) do
		local shape = BLOWS[index]
		local found = { string.find(message, shape[1]) }
		if found[1] then
			local ability = shape[2] and found[shape[2] + 2] or "Melee"
			local target = found[shape[3] + 2]
			local amount = tonumber(found[shape[4] + 2])
			if not (ability and target and amount) then
				return
			end
			logNames[ability] = (logNames[ability] or 0) + 1
			-- A cast: the blows of one spell that land together.
			local now = GetTime()
			local cast = casts[ability]
			if cast and now - cast.at <= CAST_WINDOW then
				cast.sum = cast.sum + amount
			else
				cast = Add(casts, ability, amount)
			end
			cast.at = now
			if SurvivorUI_LexiconAverage then
				SurvivorUI_LexiconAverage(ability, cast.sum / cast.count, cast.count)
			end
			targetDamage[ability] = targetDamage[ability] or {}
			targetDamage[ability][target] = (targetDamage[ability][target] or 0) + amount
			if critHovered and critHovered:IsVisible() and critHovered.ability == ability then
				CritTooltip(critHovered)
			end
			return
		end
	end
end

------------------------------------------------------------------------------
-- Healing: what the hero's spells heal, and whom ("you" is the hero by name).

local HEALS = {
	{ "^Your (.+) critically heals (.+) for (%d+)", 1, 2, 3 },
	{ "^Your (.+) heals (.+) for (%d+)", 1, 2, 3 },
	{ "^You gain (%d+) health from your (.+)%.", 2, nil, 1 },
	{ "^You gain (%d+) health from (.+)%.", 2, nil, 1 },
	{ "^(.+) gains (%d+) health from your (.+)%.", 3, 1, 2 },
}

local function RecordHeal(message)
	Remember()
	for index = 1, table.getn(HEALS) do
		local shape = HEALS[index]
		local found = { string.find(message, shape[1]) }
		if found[1] then
			local ability = found[shape[2] + 2]
			local target = shape[3] and found[shape[3] + 2] or "you"
			local amount = tonumber(found[shape[4] + 2])
			if not (ability and amount) then
				return
			end
			if target == "you" then
				target = UnitName("player") or "You"
			end
			local tally = tallies.healing
			local now = GetTime()
			local cast = tally.casts[ability]
			if cast and now - cast.at <= CAST_WINDOW then
				cast.sum = cast.sum + amount
			else
				cast = Add(tally.casts, ability, amount)
			end
			cast.at = now
			tally.targets[ability] = tally.targets[ability] or {}
			tally.targets[ability][target] = (tally.targets[ability][target] or 0) + amount
			return
		end
	end
end

------------------------------------------------------------------------------
-- Damage taken: each enemy's hits on the hero, by the ability it used
-- ("Melee" for a plain blow). The enemy's possessive comes first, so a spell
-- is never read as a plain blow.

local TAKEN = {
	{ "^(.+)'s (.+) crits you for (%d+)", 1, 2, 3 },
	{ "^(.+)'s (.+) hits you for (%d+)", 1, 2, 3 },
	{ "^You suffer (%d+) .- from (.+)'s (.+)%.", 2, 3, 1 },
	{ "^(.+) crits you for (%d+)", 1, nil, 2 },
	{ "^(.+) hits you for (%d+)", 1, nil, 2 },
}

local function RecordTaken(message)
	Remember()
	for index = 1, table.getn(TAKEN) do
		local shape = TAKEN[index]
		local found = { string.find(message, shape[1]) }
		if found[1] then
			local enemy = found[shape[2] + 2]
			local ability = shape[3] and found[shape[3] + 2] or "Melee"
			local amount = tonumber(found[shape[4] + 2])
			if not (enemy and amount) then
				return
			end
			local tally = tallies.taken
			Add(tally.casts, enemy, amount)
			tally.targets[enemy] = tally.targets[enemy] or {}
			tally.targets[enemy][ability] = (tally.targets[enemy][ability] or 0) + amount
			return
		end
	end
end

local HIT_EVENTS = {
	"CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_SPELL_SELF_DAMAGE",
	"CHAT_MSG_COMBAT_PET_HITS", "CHAT_MSG_SPELL_PET_DAMAGE",
}
local HEAL_EVENTS = { CHAT_MSG_SPELL_SELF_BUFF = true, CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS = true }
local TAKEN_EVENTS = {
	CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS = true, CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE = true,
	CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE = true,
}

local events = CreateFrame("Frame")
for index = 1, table.getn(HIT_EVENTS) do
	events:RegisterEvent(HIT_EVENTS[index])
end
events:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
events:RegisterEvent("CHAT_MSG_SYSTEM")
for name in pairs(HEAL_EVENTS) do
	events:RegisterEvent(name)
end
for name in pairs(TAKEN_EVENTS) do
	events:RegisterEvent(name)
end
events:SetScript("OnEvent", function()
	local message = arg1 or ""
	if HEAL_EVENTS[event] then
		RecordHeal(message)
		return
	elseif TAKEN_EVENTS[event] then
		RecordTaken(message)
		return
	end
	if event == "CHAT_MSG_SYSTEM" then
		-- "<hero> enters <zone>. Move to begin.": a new run.
		if string.find(message, "Move to begin", 1, true) then
			ResetCrits()
		end
		return
	end
	-- Ticks on every creature come to the periodic event; only the hero's own count.
	if event == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" and not string.find(message, "from your", 1, true) then
		return
	end
	Record(message)
end)
