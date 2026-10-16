-- Survivor UI: the ability tooltip, laid out again.
--
-- The game writes an ability's tooltip itself: the name and rank, how it is
-- cast and its cooldown, a description, then "Upgrades: ...", "Your bonuses:
-- ..." and "Talents: ..." as comma lists, and the crit chance. This file reads
-- those lines back once the game has written them and lays them out again,
-- short: the name and rank, a summary under it, and the description with its
-- numbers in white. The upgrades, bonuses and talents are left out (the
-- build's card lists a spell's upgrades). The tooltip stays where the game
-- placed it.
--
-- The chance to cast twice and the crit line are the game's own: it writes
-- them only on a spell that can cast twice or crit, so the layout shows them
-- where the game wrote them and nowhere else.
--
-- Simplified (a switch in /sui opt, Ability Bar, on unless switched off):
-- under the name, rank, cast and cooldown, every number the description and
-- the line under the name give stands on a line of its own, value first: "3
-- Targets", "7 yd", "34% chance to cast twice", "26% crit · 219% crit
-- damage", "826 Physical Damage", "50% Leech". Wording without a number
-- ("Bosses and elites are targeted first.") is left out.
--
-- The game rewrites the tooltip a few times a second while the mouse stays,
-- so the layout is redone whenever its text changes. A tooltip it cannot read
-- is left as the game wrote it, and so is one whose new layout fails to come
-- together: the lines are worked out in full before the tooltip is touched.

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local DOT = " \194\183 "

local SECTIONS = {
	{ prefix = "Upgrades: ",     title = "Upgrades",     color = { 1.00, 1.00, 1.00 } },
	{ prefix = "Your bonuses: ", title = "Your bonuses", color = { 0.12, 1.00, 0.00 } },
	{ prefix = "Talents: ",      title = "Talents",      color = { 0.44, 0.84, 1.00 } },
}

local DESCRIPTION_COLOR = { 0.72, 0.72, 0.72 }   -- neutral, so the school's color stands out

-- An ability wears the color of its school, read from its description
-- ("29 Holy damage"); one that names none is physical.
local SCHOOL_COLORS = {
	Holy     = { 1.00, 0.78, 0.15 },
	Fire     = { 1.00, 0.42, 0.08 },
	Frost    = { 0.30, 0.72, 1.00 },
	Nature   = { 0.30, 0.88, 0.25 },
	Shadow   = { 0.66, 0.38, 1.00 },
	Arcane   = { 1.00, 0.40, 0.85 },
}
local PHYSICAL_COLOR = { 0.90, 0.68, 0.45 }

-- The summary's numbers, each kind in a color of its own; the words stay muted.
local COOLDOWN_HEX = "|cff8cccff"   -- light blue
local REACH_HEX = "|cff99f2bf"      -- mint
local CRIT_HEX = "|cffffc214"       -- the gold of a critical strike's number
local MUTED = { 0.62, 0.62, 0.62 }
local ECHO_COLOR = { 1, 0.82, 0 }   -- the game's own gold for "chance to cast twice"

------------------------------------------------------------------------------
-- Rules: thin lines drawn across the tooltip, each over a blank line.

local rules = {}
local rulesUsed = 0

local function HideRules()
	for index = 1, table.getn(rules) do
		rules[index]:Hide()
	end
	rulesUsed = 0
end

local function Rule(line, color)
	rulesUsed = rulesUsed + 1
	local rule = rules[rulesUsed]
	if not rule then
		rule = GameTooltip:CreateTexture(nil, "ARTWORK")
		rule:SetTexture(FLAT)
		rule:SetHeight(1)
		rules[rulesUsed] = rule
	end
	local text = getglobal("GameTooltipTextLeft"..line)
	rule:ClearAllPoints()
	rule:SetPoint("LEFT", text, "LEFT", 0, 0)
	rule:SetPoint("RIGHT", GameTooltip, "RIGHT", -10, 0)
	rule:SetVertexColor(color[1], color[2], color[3], 0.6)
	rule:Show()
end

------------------------------------------------------------------------------
-- Reading what the game wrote.

local function Plain(text)
	text = string.gsub(text or "", "|c%x%x%x%x%x%x%x%x", "")
	text = string.gsub(text, "|r", "")
	return text
end

local function Signature()
	local parts = {}
	for line = 1, GameTooltip:NumLines() do
		local left = getglobal("GameTooltipTextLeft"..line)
		local right = getglobal("GameTooltipTextRight"..line)
		table.insert(parts, (left and left:GetText() or "").."~"..(right and right:IsShown() and right:GetText() or ""))
	end
	return table.concat(parts, "^")
end

-- "a, b, c" into { "a", "b", "c" }
local function List(text)
	local items = {}
	for item in string.gfind(text, "[^,]+") do
		item = string.gsub(item, "^%s+", "")
		item = string.gsub(item, "%s+$", "")
		if item ~= "" then
			table.insert(items, item)
		end
	end
	return items
end

-- Returns the tooltip's pieces, or nil when it is not an ability's.
local function Read()
	local count = GameTooltip:NumLines()
	if count < 2 then
		return nil
	end

	local ability = { stats = {}, description = {}, sections = {}, other = {} }
	local title = getglobal("GameTooltipTextLeft1")
	local rank = getglobal("GameTooltipTextRight1")
	ability.title = Plain(title:GetText())
	ability.rank = rank:IsShown() and Plain(rank:GetText()) or nil

	-- The line saying how it is cast: "Automatic" or "Passive", with the
	-- cooldown on its right. Lines above it are short stats ("11 yd radius").
	local castLine
	for line = 2, count do
		local left = Plain(getglobal("GameTooltipTextLeft"..line):GetText())
		local right = getglobal("GameTooltipTextRight"..line)
		local rightText = right:IsShown() and Plain(right:GetText()) or ""
		if string.find(rightText, "cooldown", 1, true) or left == "Automatic" or left == "Passive" then
			castLine = line
			ability.cast = left
			ability.cooldown = rightText ~= "" and rightText or nil
			break
		end
	end
	if not castLine then
		return nil
	end
	for line = 2, castLine - 1 do
		local text = Plain(getglobal("GameTooltipTextLeft"..line):GetText())
		if text ~= "" then
			table.insert(ability.stats, text)
		end
	end

	-- Everything below, one piece per line of text.
	for line = castLine + 1, count do
		local left = getglobal("GameTooltipTextLeft"..line)
		local r, g, b = left:GetTextColor()
		for piece in string.gfind((left:GetText() or "").."\n", "([^\n]*)\n") do
			local text = Plain(piece)
			local section
			for index = 1, table.getn(SECTIONS) do
				if string.sub(text, 1, string.len(SECTIONS[index].prefix)) == SECTIONS[index].prefix then
					section = SECTIONS[index]
					break
				end
			end
			local _, _, critChance, critDamage = string.find(text, "^(%d+%%) chance to crit for (%d+%%) damage")
			if section then
				table.insert(ability.sections, { info = section, items = List(string.sub(text, string.len(section.prefix) + 1)) })
			elseif critChance then
				ability.crit = critChance.." crit"..DOT..critDamage
				ability.critChance, ability.critDamage = critChance, critDamage
			elseif text ~= "" then
				-- The description is the first text below the cast line; the
				-- rest ("Not learned yet", a racial's note) keep their color.
				if table.getn(ability.sections) == 0 and not ability.crit and table.getn(ability.other) == 0
					and (table.getn(ability.description) == 0 or ability.descriptionColor == r..g..b) then
					table.insert(ability.description, text)
					ability.descriptionColor = r..g..b
				else
					table.insert(ability.other, { text = text, color = { r, g, b } })
				end
			end
		end
	end

	-- Only an ability's tooltip has a rank, its upgrade lists or a crit line.
	if not (ability.rank and string.find(ability.rank, "^Rank")) and table.getn(ability.sections) == 0 and not ability.crit then
		return nil
	end
	return ability
end

------------------------------------------------------------------------------
-- Writing it again.

local function School(ability)
	for index = 1, table.getn(ability.description) do
		for word in string.gfind(ability.description[index], "%a+") do
			if SCHOOL_COLORS[word] then
				return word, SCHOOL_COLORS[word]
			end
		end
	end
	return nil, PHYSICAL_COLOR
end

local function Hex(color)
	return string.format("|cff%02x%02x%02x", math.floor(color[1] * 255), math.floor(color[2] * 255), math.floor(color[3] * 255))
end

-- The numbers in white, a unit after one ("11 yd", "14 sec") with it, and
-- the damage of the ability's school ("29 Holy") in that school's color.
local function Highlight(text, school, schoolColor)
	text = string.gsub(text, "(%d[%d%.]*%%?)( ?)(%a*)", function(number, space, word)
		if school and word == school then
			return Hex(schoolColor)..number..space..word.."|r"
		elseif word == "yd" or word == "sec" then
			return "|cffffffff"..number..space..word.."|r"
		end
		return "|cffffffff"..number.."|r"..space..word
	end)
	if school then
		-- "29 Holy" took the color; "damage" after it joins in.
		text = string.gsub(text, school.."|r damage", school.." damage|r")
	end
	return text
end

-- The new layout is worked out as a list of lines first, and the tooltip
-- written from it only once that list is whole: a layout that fails halfway
-- would otherwise leave the tooltip empty, and an empty tooltip hides.
local function Simplified()
	SurvivorUIDB = SurvivorUIDB or {}
	return SurvivorUIDB.simpleTips ~= false
end

-- The simplified description: the numbers a description gives, one fact to a
-- line, the value first ("3 Targets", "7 yd", "826 Physical Damage", "50%
-- Leech"), read from the description's wording, clause by clause. A rule
-- takes what it reads out of the clause, so no later rule reads it again; a
-- clause with a number no rule knows stands as it is written; one with no
-- number at all ("Bosses and elites are targeted first.") is left out.

local NUMBER = "([%d%.]+)"

local function Capital(text)
	return string.upper(string.sub(text, 1, 1))..string.sub(text, 2)
end

-- "your attack speed" as a label: "Attack speed".
local function Thing(text)
	return Capital((string.gsub(string.gsub(text, "^your ", ""), "^the ", "")))
end

-- Each fact: its place in the list (targets, then reach, the cast twice and
-- crit lines, damage, then everything else), its value and its label.
local TARGETS, REACH, ECHO, CRIT, DAMAGE, EFFECT, OTHER = 1, 2, 3, 4, 5, 6, 7

local FACTS = {
	{ "up to (%d+) enem%a*", function(n) return TARGETS, n, "Targets" end },
	{ "up to (%d+) targets?", function(n) return TARGETS, n, "Targets" end },
	{ "(%d+) additional enem%a*", function(n) return TARGETS, "+"..n, "Targets" end },
	{ "(%d+) additional targets?", function(n) return TARGETS, "+"..n, "Targets" end },
	{ "(%d+) nearby enem%a*", function(n) return TARGETS, n, "Targets" end },
	{ "(%d+) enem%a*", function(n) return TARGETS, n, "Targets" end },
	{ "(%d+) targets", function(n) return TARGETS, n, "Targets" end },
	{ "absorbs? up to "..NUMBER, function(n) return EFFECT, n, "Absorb" end },
	{ "absorbs? "..NUMBER, function(n) return EFFECT, n, "Absorb" end },
	{ "absorbing "..NUMBER, function(n) return EFFECT, n, "Absorb" end },
	{ "heals? you for "..NUMBER.."%% of the damage[%a ]*", function(n) return EFFECT, n.."%", "Leech" end },
	{ NUMBER.." (%a+) damage over "..NUMBER.." sec", function(n, school, t)
		return DAMAGE, n, Capital(school).." Damage over "..t.." sec", school end },
	{ NUMBER.." (%a+) damage", function(n, school) return DAMAGE, n, Capital(school).." Damage", school end },
	{ NUMBER.." damage", function(n) return DAMAGE, n, "Damage" end },
	{ "within "..NUMBER.." yds?", function(n) return REACH, n.." yd", "" end },
	{ NUMBER.." yds? radius", function(n) return REACH, n.." yd", "radius" end },
	{ NUMBER.." yds? range", function(n) return REACH, n.." yd", "range" end },
	{ NUMBER.." yds?", function(n) return REACH, n.." yd", "" end },
	{ "heals? [%a ]-for "..NUMBER.."%%", function(n) return EFFECT, n.."%", "Heal" end },
	{ "heals? [%a ]-for "..NUMBER, function(n) return EFFECT, n, "Healing" end },
	{ "restores? "..NUMBER.." health", function(n) return EFFECT, n, "Healing" end },
	{ "(%a+)s them for "..NUMBER.." sec", function(verb, t) return EFFECT, t.." sec", Capital(verb) end },
	{ "(%a+)s them by "..NUMBER.."%%", function(verb, n) return EFFECT, n.."%", Capital(verb) end },
	{ NUMBER.."%% chance to (.+)", function(n, rest) return EFFECT, n.."%", "chance to "..rest end },
	{ "increases? (.-) by "..NUMBER.."%%", function(what, n) return EFFECT, "+"..n.."%", Thing(what) end },
	{ "reduces? (.-) by "..NUMBER.."%%", function(what, n) return EFFECT, "-"..n.."%", Thing(what) end },
	{ "for "..NUMBER.." sec", function(t) return EFFECT, t.." sec", "Duration" end },
	{ "lasts? "..NUMBER.." sec", function(t) return EFFECT, t.." sec", "Duration" end },
	{ "every "..NUMBER.." sec", function(t) return EFFECT, t.." sec", "Interval" end },
}

local function Trim(text)
	return (string.gsub(string.gsub(text, "^[%s,]+", ""), "[%s,%.]+$", ""))
end

-- The facts of a description (its lines, joined), as { place, value, label,
-- school } in the order they were read.
local function ReadFacts(lines)
	local facts = {}
	local text = table.concat(lines, " ").." . "
	for clause in string.gfind(text, "(.-)[%.;]%s") do
		local original = Trim(clause)
		local lower = string.lower(original)
		local matched = false
		for index = 1, table.getn(FACTS) do
			local rule = FACTS[index]
			while true do
				local found = { string.find(lower, rule[1]) }
				if not found[1] then
					break
				end
				matched = true
				local place, value, label, school = rule[2](found[3], found[4], found[5])
				table.insert(facts, { place = place, value = value, label = label, school = school })
				-- Cut from both, so the next rules read only what is left.
				lower = string.sub(lower, 1, found[1] - 1).." "..string.sub(lower, found[2] + 1)
				original = string.sub(original, 1, found[1] - 1).." "..string.sub(original, found[2] + 1)
			end
		end
		if not matched and string.find(original, "%d") then
			table.insert(facts, { place = OTHER, text = original })
		end
	end
	return facts
end

-- The echo line ("34% chance to cast twice"), wherever it was written.
local function IsEcho(text)
	return string.find(text, "chance to cast", 1, true) or string.find(text, "^Casts ")
end

-- A fact as a line: the value in white (a damage's in its school's color),
-- the label muted.
local function FactText(fact, school, tint)
	if fact.text then
		return Highlight(fact.text, school, tint)
	end
	local value = "|cffffffff"..fact.value.."|r"
	if fact.place == DAMAGE and fact.school and SCHOOL_COLORS[Capital(fact.school)] then
		value = Hex(SCHOOL_COLORS[Capital(fact.school)])..fact.value.."|r"
	end
	if fact.label == "" then
		return value
	end
	return value.." "..fact.label
end

-- The facts in their places: the line under the name's (range, radius) with
-- the reach, the echo and the crit after it, then the description's own.
local function AllFacts(ability)
	local facts, seen = {}, {}
	for index = 1, table.getn(ability.stats) do
		local stat = ability.stats[index]
		local _, _, yards = string.find(stat, "^([%d%.]+) yds?")
		table.insert(facts, { place = REACH, text = stat })
		if yards then
			seen[yards.." yd"] = true
		end
	end
	for index = 1, table.getn(ability.other) do
		local other = ability.other[index]
		if IsEcho(other.text) then
			table.insert(facts, { place = ECHO, echo = other.text })
		end
	end
	if ability.critChance then
		table.insert(facts, { place = CRIT, crit = true })
	end
	local read = ReadFacts(ability.description)
	for index = 1, table.getn(read) do
		local fact = read[index]
		-- "within 7 yd" says again what "7 yd range" said.
		if not (fact.place == REACH and seen[fact.value]) then
			table.insert(facts, fact)
		end
	end
	-- In their places, each place in the order read.
	for index = 1, table.getn(facts) do
		facts[index].order = index
	end
	table.sort(facts, function(a, b)
		if a.place ~= b.place then
			return a.place < b.place
		end
		return a.order < b.order
	end)
	return facts
end

-- The lines of the layout: { left, right, r, g, b, rr, rg, rb } a double
-- line, { left, nil, r, g, b, wrap = true } a line, { rule = color } a blank
-- line with a rule across it.
local function Compose(ability)
	local lines = {}
	local function Double(left, right, color, rightColor)
		table.insert(lines, { left, right, color[1], color[2], color[3], rightColor[1], rightColor[2], rightColor[3] })
	end
	local function Line(text, color)
		table.insert(lines, { text, nil, color[1], color[2], color[3], wrap = true })
	end
	local function Spacer(color)
		table.insert(lines, { rule = color })
	end
	local school, tint = School(ability)

	if ability.rank then
		Double(ability.title, ability.rank, tint, MUTED)
	else
		Line(ability.title, tint)
	end
	-- "3.4 sec" cooldown, "28 yd" range, "7%" crit "204%".
	local cooldown = string.gsub(ability.cooldown or " ", "^([%d%.]+ sec)", COOLDOWN_HEX.."%1|r")
	Double(ability.cast, cooldown, MUTED, MUTED)

	local others = ability.other
	if Simplified() then
		local facts = AllFacts(ability)
		if table.getn(facts) > 0 then
			Spacer(tint)
			for index = 1, table.getn(facts) do
				local fact = facts[index]
				if fact.echo then
					Line(fact.echo, ECHO_COLOR)
				elseif fact.crit then
					Line(CRIT_HEX..ability.critChance.."|r crit"..DOT..CRIT_HEX..ability.critDamage.."|r crit damage", MUTED)
				else
					Line(FactText(fact, school, tint), MUTED)
				end
			end
		elseif table.getn(ability.description) > 0 then
			-- Nothing to count: the description as the game wrote it.
			Spacer(tint)
			for index = 1, table.getn(ability.description) do
				Line(Highlight(ability.description[index], school, tint), DESCRIPTION_COLOR)
			end
		end
		-- The echo line has its place among the facts.
		others = {}
		for index = 1, table.getn(ability.other) do
			if not IsEcho(ability.other[index].text) then
				table.insert(others, ability.other[index])
			end
		end
	else
		if table.getn(ability.stats) > 0 or ability.crit then
			local reach = string.gsub(table.concat(ability.stats, DOT), "([%d%.]+ yd)", REACH_HEX.."%1|r")
			local crit = string.gsub(ability.crit or " ", "(%d+%%)", CRIT_HEX.."%1|r")
			Double(reach, crit, MUTED, MUTED)
		end
		if table.getn(ability.description) > 0 then
			Spacer(tint)
			for index = 1, table.getn(ability.description) do
				Line(Highlight(ability.description[index], school, tint), DESCRIPTION_COLOR)
			end
		end
	end

	-- The upgrades, bonuses and talents are left out: the card stays short,
	-- and the build's own card lists a spell's upgrades.

	if table.getn(others) > 0 then
		Spacer(MUTED)
		for index = 1, table.getn(others) do
			Line(others[index].text, others[index].color)
		end
	end
	return lines
end

local function Write(ability)
	local ok, lines = pcall(Compose, ability)
	if not (ok and lines and table.getn(lines) > 0) then
		return false
	end
	HideRules()
	GameTooltip:ClearLines()
	for index = 1, table.getn(lines) do
		local line = lines[index]
		if line.rule then
			GameTooltip:AddLine(" ")
			Rule(GameTooltip:NumLines(), line.rule)
		elseif line[2] then
			GameTooltip:AddDoubleLine(line[1], line[2], line[3], line[4], line[5], line[6], line[7], line[8])
		else
			GameTooltip:AddLine(line[1], line[3], line[4], line[5], line.wrap and 1 or nil)
		end
	end
	-- Shown again to fit the new lines, where the game placed it.
	GameTooltip:Show()
	return true
end

------------------------------------------------------------------------------
-- Watching for the game's text.

local written                   -- the signature of the last layout written

local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function()
	if not GameTooltip:IsVisible() then
		return
	end
	local signature = Signature()
	if signature == written then
		return
	end
	HideRules()
	written = nil
	local ok, ability = pcall(Read)
	if ok and ability then
		local wrote, done = pcall(Write, ability)
		if wrote and done then
			written = Signature()
		end
	end
end)

-- Rules belong to this layout only: they go when the tooltip closes.
local stockHide = GameTooltip:GetScript("OnHide")
GameTooltip:SetScript("OnHide", function()
	HideRules()
	written = nil
	if stockHide then
		stockHide()
	end
end)

if SurvivorUI_RegisterOption then
	SurvivorUI_RegisterOption({
		section = "Ability Bar",
		order = 1,
		label = "Simplified Ability Description",
		tip = "Ability tooltips as a list: under the name, rank, cast and cooldown, every number on a line of its own, value first (\"3 Targets\", \"7 yd\", \"26% crit · 219% crit damage\", \"826 Physical Damage\", \"50% Leech\"). Off, the description reads as the game writes it, its numbers in white.",
		get = Simplified,
		toggle = function()
			SurvivorUIDB = SurvivorUIDB or {}
			SurvivorUIDB.simpleTips = not Simplified()
		end,
	})
end
