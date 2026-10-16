-- Survivor UI: the card beside a damage meter line.
--
-- Hover a line of the damage meter (Meter.lua) for its card, kept short: what
-- one cast of it deals on average, and the targets it has hit as small meter
-- bars. Both counted here from the combat log. The meter's Reset clears it
-- (SurvivorUI_ResetRun); a new run does too. The tally is kept in the run's
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

local casts = {}                -- [ability] = { sum, count, at = when its last blow landed }
local targetDamage = {}         -- [ability] = { [target name] = damage }
local logNames = {}             -- [ability] = blows seen under that name, for /sui icons

-- The tally from the run's memory, as it stands.
local function Remember()
	if not SurvivorUI_RunMemory then
		return
	end
	local memory = SurvivorUI_RunMemory("crits")
	memory.casts = memory.casts or {}
	memory.targets = memory.targets or {}
	casts, targetDamage = memory.casts, memory.targets
end

-- Every ability name the combat log has given a blow, with how many: a meter
-- line whose name is missing here has no blows in the log to build a card from.
function SurvivorUI_LogNames()
	return logNames
end

local function ResetCrits()
	casts, targetDamage = {}, {}
	if SurvivorUI_RunMemory then
		local memory = SurvivorUI_RunMemory("crits")
		memory.casts, memory.targets = casts, targetDamage
	end
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

-- The spell's targets, the most damaged first, and the damage over them all.
local function Targets(ability)
	local list, total = {}, 0
	for name, damage in pairs(targetDamage[ability] or {}) do
		table.insert(list, { name = name, damage = damage })
		total = total + damage
	end
	table.sort(list, function(a, b) return a.damage > b.damage end)
	return list, total
end

local critHovered = nil

local function CritTooltip(row)
	local ability = row.ability
	local targets, targetTotal = Targets(ability)
	-- A proc's blows reach no combat log, so it has no casts or targets to
	-- show: its card holds the meter line's own numbers instead.
	local fromMeter = ability and not casts[ability] and row.damage
	if not (ability and (casts[ability] or fromMeter)) then
		critTip:Hide()
		return
	end
	local color = row.color or { 0.8, 0.8, 0.8 }

	-- A proc goes by "The Reaper's Amulet: Eviscerate": the card is titled by
	-- the ability, as any other line's, and names its source in a row.
	local title, source = ability, nil
	if fromMeter then
		local _, _, from, name = string.find(ability, "^(.-): (.+)$")
		if from then
			title, source = name, from
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
	if casts[ability] then
		Add("row", "Avg cast", Average(casts[ability]))
	else
		if source then
			Add("row", "Proc of", source)
		end
		Add("row", "Damage", Short(Num(row.damage)))
		Add("row", "Share", math.floor(Num(row.share) * 100 + 0.5).."%")
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

-- The meter's Reset: the tally starts over.
function SurvivorUI_ResetRun()
	ResetCrits()
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

local HIT_EVENTS = {
	"CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_SPELL_SELF_DAMAGE",
	"CHAT_MSG_COMBAT_PET_HITS", "CHAT_MSG_SPELL_PET_DAMAGE",
}

local events = CreateFrame("Frame")
for index = 1, table.getn(HIT_EVENTS) do
	events:RegisterEvent(HIT_EVENTS[index])
end
events:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
events:RegisterEvent("CHAT_MSG_SYSTEM")
events:SetScript("OnEvent", function()
	local message = arg1 or ""
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
