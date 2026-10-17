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
local ECHO_HEX = "|cffffd100"       -- the same, for its percentage within a line
local GEAR_GREEN = { 0.12, 1, 0 }   -- the game's item green, for the gear's effects
local GEAR_HEX = "|cff1eff00"

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
-- tip: the tooltip to read, the game's own unless another is given (a hidden
-- one, named name, for the build's cards).
local function Read(tip, name)
	tip = tip or GameTooltip
	name = name or "GameTooltip"
	local count = tip:NumLines()
	if count < 2 then
		return nil
	end

	local ability = { stats = {}, description = {}, sections = {}, other = {} }
	local title = getglobal(name.."TextLeft1")
	local rank = getglobal(name.."TextRight1")
	ability.title = Plain(title:GetText())
	ability.rank = rank:IsShown() and Plain(rank:GetText()) or nil

	-- The line saying how it is cast: "Automatic" or "Passive", with the
	-- cooldown on its right. Lines above it are short stats ("11 yd radius").
	local castLine
	for line = 2, count do
		local left = Plain(getglobal(name.."TextLeft"..line):GetText())
		local right = getglobal(name.."TextRight"..line)
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
		local text = Plain(getglobal(name.."TextLeft"..line):GetText())
		if text ~= "" then
			table.insert(ability.stats, text)
		end
	end

	-- Everything below, one piece per line of text.
	for line = castLine + 1, count do
		local left = getglobal(name.."TextLeft"..line)
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
			local _, critEnd, critChance, critDamage = string.find(text, "^(%d+%%) chance to crit for (%d+%%) damage")
			if section then
				table.insert(ability.sections, { info = section, items = List(string.sub(text, string.len(section.prefix) + 1)) })
			elseif critChance then
				ability.crit = critChance.." crit"..DOT..critDamage
				ability.critChance, ability.critDamage = critChance, critDamage
				-- The game writes the chance to cast twice on the same line,
				-- after the crit: kept as a line of its own.
				local rest = string.gsub(string.sub(text, critEnd + 1), "^[%s%.,;\194\183]+", "")
				if string.find(rest, "chance to cast", 1, true) or string.find(rest, "^Casts ") then
					table.insert(ability.other, { text = rest, color = ECHO_COLOR })
				end
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

-- Holding Shift shows the full description in place of the simplified list,
-- for a closer look; letting go brings the list back.
local function ShowSimplified()
	return Simplified() and not IsShiftKeyDown()
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

-- Each fact: its place in the list (damage, the spell's main effect, reach,
-- targets, everything else, then the two that hold for every spell together
-- at the foot: the chance to cast twice and the crit chance), its value and
-- its label.
local DAMAGE, MAIN, REACH, TARGETS, EFFECT, OTHER, ECHO, CRIT = 1, 2, 3, 4, 5, 6, 7, 8

-- How many targets a spell hits, in the colors of gear rarity, each mixed a
-- quarter of the way to white, softened but still plainly colored: 1 white,
-- 2 to 4 green, 5 to 9 blue, 10 to 14 purple, and orange from 15.
local TARGET_TIERS = {          -- from the top: targets reached, color
	{ 15, "ffa040" },           -- legendary
	{ 10, "ba68f2" },           -- epic
	{ 5,  "4094e5" },           -- rare
	{ 2,  "56ff40" },           -- uncommon
	{ 0,  "ffffff" },           -- common
}

local function TargetsText(count)
	for index = 1, table.getn(TARGET_TIERS) do
		if count >= TARGET_TIERS[index][1] then
			return "|cff"..TARGET_TIERS[index][2]..count.."|r"
		end
	end
	return tostring(count)
end

-- A rule may give a line's words in full as its fifth value, the number in
-- white in it, in place of value and label; a rule giving no place drops what
-- it reads from the list (the full description, with Shift, still has it).
local FACTS = {
	-- What a hit gives back, by the spot of the 2x damage line, ahead of the
	-- damage and heal rules that would take its numbers: "Shields you against
	-- 58 damage for every enemy hit, up to 292" is "58 Shield on hit, max
	-- 292"; "Heals you for 50, plus 10 for every enemy hit" is "50 Heal, +10
	-- per enemy hit"; "Each hit heals you for 20" is "20 Heal on hit".
	{ "shields you against (%d+) damage for every enemy hit, up to (%d+)[^%.;]*",
		function(n, most) return OTHER, n, "Shield on hit, max "..most end },
	{ "heals you for (%d+), plus (%d+) for every enemy hit",
		function(n, more) return OTHER, n, "Heal, +"..more.." per enemy hit" end },
	{ "each hit heals you for (%d+)", function(n) return OTHER, n, "Heal on hit" end },
	-- Effects worded around "damage" or "sec", read whole before the damage
	-- and duration rules would take their numbers and drop the rest.
	{ "deals? "..NUMBER.."%% less damage", function(p) return EFFECT, "-"..p.."%", "enemy damage" end },
	{ "damage increased by "..NUMBER.."%%", function(p) return EFFECT, "+"..p.."%", "damage" end },
	{ "attackers take "..NUMBER.." damage", function(n) return EFFECT, n, "damage to melee attackers" end },
	-- A shield or heal sized by your health: "Absorbs the next 293 damage
	-- you take, 42% of your max health" is "293 Absorb Shield (42% of max health)",
	-- not 293 damage dealt; "Heals you for 120, 15% of your max health" is
	-- "120 Heal (15% of max health)".
	{ "absorbs the next "..NUMBER.." damage you take, "..NUMBER.."%% of your max health",
		function(n, p) return EFFECT, n, "Absorb Shield ("..p.."% of max health)" end },
	{ "absorbs the next "..NUMBER.." damage[%a ]*", function(n) return EFFECT, n, "Absorb Shield" end },
	{ "heals you for "..NUMBER..", "..NUMBER.."%% of your max health",
		function(n, p) return EFFECT, n, "Heal ("..p.."% of max health)" end },
	{ "immune to all damage for "..NUMBER.." sec", function(t) return EFFECT, t.." sec", "Immunity" end },
	{ "immune to all damage", function() return EFFECT, nil, "Immunity", nil, "Immune to all damage" end },
	{ "flee for "..NUMBER.." sec", function(t) return EFFECT, t.." sec", "Fear" end },
	{ "healing "..NUMBER.." over "..NUMBER.." sec", function(n, t) return EFFECT, n, "Healing over "..t.." sec" end },
	-- "Stacks up to 3 times on one enemy" is "Stacks up to 3 times".
	{ "stacks up to (%d+) times?[^,;:]*", function(n) return EFFECT, n, "", nil, "Stacks up to "..n.." times" end },
	-- "Hits every enemy within 8 yd": no count, everything in reach, "AoE"
	-- in the targets' place.
	{ "every enem%a*", function() return TARGETS, "AoE", "" end },
	-- "Afflicts the 4 healthiest enemies", "the 3 nearest enemies", "the
	-- nearest enemy": how many it picks.
	{ "the (%d+) %a+est enem%a*", function(n) return TARGETS, n, "Targets" end },
	-- "Fires 10 missiles at random enemies": how many it sends out, in the
	-- targets' place ("10 Targets"), though several may find the same enemy.
	{ "fires (%d+) missiles?[%a ]-enem%a*", function(n) return TARGETS, n, "Targets" end },
	{ "fires (%d+) missiles?", function(n) return TARGETS, n, "Targets" end },
	{ "the %a+est enemy", function() return TARGETS, "1", "Targets" end },
	{ "up to (%d+) enem%a*", function(n) return TARGETS, n, "Targets" end },
	{ "up to (%d+) targets?", function(n) return TARGETS, n, "Targets" end },
	{ "(%d+) additional enem%a*", function(n) return TARGETS, "+"..n, "Targets" end },
	{ "(%d+) additional targets?", function(n) return TARGETS, "+"..n, "Targets" end },
	{ "(%d+) nearby enem%a*", function(n) return TARGETS, n, "Targets" end },
	{ "(%d+) enem%a*", function(n) return TARGETS, n, "Targets" end },
	{ "(%d+) targets", function(n) return TARGETS, n, "Targets" end },
	{ "absorbs? up to "..NUMBER, function(n) return EFFECT, n, "Absorb Shield" end },
	{ "absorbs? "..NUMBER, function(n) return EFFECT, n, "Absorb Shield" end },
	{ "absorbing "..NUMBER, function(n) return EFFECT, n, "Absorb Shield" end },
	{ "heals? you for "..NUMBER.."%% of the damage[%a ]*", function(n) return EFFECT, n.."%", "Leech" end },
	{ NUMBER.." (%a+) damage over "..NUMBER.." sec", function(n, school, t)
		return DAMAGE, n, Capital(school).." Damage over "..t.." sec", school end },
	{ NUMBER.." (%a+) damage", function(n, school) return DAMAGE, n, Capital(school).." Damage", school end },
	{ NUMBER.." damage", function(n) return DAMAGE, n, "Damage" end },
	-- "doubled to 1506 against an enemy below 30% health": near the bottom,
	-- over the chance to cast twice, "2x damage on targets below 30%", the 2x
	-- in white as a value, as "2 Targets" is.
	{ "doubled to [%d%.]+ against an? enem%a* below (%d+)%%[%a ]*",
		function(p) return OTHER, "2x", "damage on targets below "..p.."%" end },
	{ "tripled to [%d%.]+ against an? enem%a* below (%d+)%%[%a ]*",
		function(p) return OTHER, "3x", "damage on targets below "..p.."%" end },
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
	-- "Your cooldowns recover 60% faster": cooldowns that recover p% faster
	-- take 1 / (1 + p/100) as long, so "-38% cooldown".
	{ "cooldowns recover "..NUMBER.."%% faster", function(p)
		local faster = tonumber(p) or 0
		return EFFECT, "-"..math.floor(faster / (100 + faster) * 100 + 0.5).."%", "cooldown" end },
	{ "increases? (.-) by "..NUMBER.."%%", function(what, n) return EFFECT, "+"..n.."%", Thing(what) end },
	{ "reduces? (.-) by "..NUMBER.."%%", function(what, n) return EFFECT, "-"..n.."%", Thing(what) end },
	{ "for "..NUMBER.." sec", function(t) return EFFECT, t.." sec", "Duration" end },
	{ "lasts? "..NUMBER.." sec", function(t) return EFFECT, t.." sec", "Duration" end },
	{ "every "..NUMBER.." sec", function(t) return EFFECT, t.." sec", "Interval" end },
	-- "Bosses and elites are targeted first, then the most wounded below 30%
	-- health": how it picks its targets, left to the full description. Last,
	-- as it takes the rest of its sentence.
	{ "[%a ,]*targeted first.*", function() return nil end },
}

local function Trim(text)
	return (string.gsub(string.gsub(text, "^[%s,]+", ""), "[%s,%.]+$", ""))
end

-- Words that carry no meaning of their own, left over once the rules have
-- read a sentence ("makes you", "deals to").
local GLUE = {
	a = true, an = true, the = true, of = true, to = true, ["and"] = true, ["or"] = true, ["for"] = true,
	you = true, your = true, it = true, its = true, with = true, ["in"] = true, on = true, at = true,
	that = true, them = true, they = true, makes = true, deals = true, deal = true, hits = true, hit = true,
	casts = true, cast = true, also = true, each = true, all = true, is = true, are = true,
}

-- Whether the rules read a sentence only in part: more than one word of
-- meaning left over ("enemies you slay have a"), or a rule that took the
-- rest of its sentence with holes where other rules cut their numbers out.
local function HalfRead(residue, captures)
	for index = 1, table.getn(captures) do
		if type(captures[index]) == "string" and string.find(captures[index], "%s%s") then
			return true
		end
	end
	local words = 0
	for word in string.gfind(residue, "%a+") do
		if not GLUE[word] then
			words = words + 1
		end
	end
	return words > 1
end

-- The facts of a description (its lines, joined), as { place, value, label,
-- school } in the order they were read, and whether a sentence of it was
-- read only in part (then the description is best shown as written).
local function ReadFacts(lines)
	local facts = {}
	local partial = false
	local text = table.concat(lines, " ").." . "
	for clause in string.gfind(text, "(.-)[%.;]%s") do
		local original = Trim(clause)
		local lower = string.lower(original)
		local matched = false
		local captures = {}
		for index = 1, table.getn(FACTS) do
			local rule = FACTS[index]
			while true do
				local found = { string.find(lower, rule[1]) }
				if not found[1] then
					break
				end
				matched = true
				table.insert(captures, found[3])
				table.insert(captures, found[4])
				table.insert(captures, found[5])
				local place, value, label, school, text = rule[2](found[3], found[4], found[5])
				if place then
					table.insert(facts, { place = place, value = value, label = label, school = school, text = text })
				end
				-- Cut from both, so the next rules read only what is left.
				lower = string.sub(lower, 1, found[1] - 1).." "..string.sub(lower, found[2] + 1)
				original = string.sub(original, 1, found[1] - 1).." "..string.sub(original, found[2] + 1)
			end
		end
		if not matched and string.find(original, "%d") then
			table.insert(facts, { place = OTHER, text = original })
		end
		if matched and HalfRead(lower, captures) then
			partial = true
		end
	end
	return facts, partial
end

-- The echo line ("34% chance to cast twice"), wherever it was written.
local function IsEcho(text)
	return string.find(text, "chance to cast", 1, true) or string.find(text, "^Casts ")
end

-- A fact as a line: the value in white (a damage's in its school's color),
-- the label muted.
-- A plain amount (damage, healing, an absorb) from 1000 up in thousands, to
-- the nearest hundred: 1789 is "1.8k", 1000 is "1k"; from a million, "2.4m".
local function Thousands(value)
	local number = tonumber(value)
	if not (number and string.find(value, "^%d+$")) or number < 1000 then
		return value
	end
	local short, suffix = number / 1000, "k"
	if number >= 1000000 then
		short, suffix = number / 1000000, "m"
	end
	return (string.gsub(string.format("%.1f", short), "%.0$", ""))..suffix
end

local function FactText(fact, school, tint)
	if fact.text then
		return Highlight(fact.text, school, tint)
	end
	local shown = fact.place == TARGETS and fact.value or Thousands(fact.value)
	local value = "|cffffffff"..shown.."|r"
	-- Targets as a count ("3"), colored by how many.
	local _, _, count = string.find(fact.place == TARGETS and fact.value or "", "^%+?(%d+)$")
	if count then
		value = TargetsText(tonumber(count))
	elseif fact.place == DAMAGE and fact.school and SCHOOL_COLORS[Capital(fact.school)] then
		value = Hex(SCHOOL_COLORS[Capital(fact.school)])..shown.."|r"
	end
	if fact.label == "" then
		return value
	end
	-- One is "1 Target".
	local label = fact.label
	if count and tonumber(count) == 1 and fact.place == TARGETS then
		label = string.gsub(label, "s$", "")
	end
	-- A number in the label is white too: "over 11 sec" on a damage over time.
	return value.." "..Highlight(label)
end

-- The facts in their places: the line under the name's (range, radius) with
-- the reach, the echo and the crit after it, then the description's own.
local function AllFacts(ability)
	local facts, seen = {}, {}
	for index = 1, table.getn(ability.stats) do
		local stat = ability.stats[index]
		local _, _, yards = string.find(stat, "^([%d%.]+) yds?")
		-- The line under the name holds the reach, and may hold the targets.
		local _, _, targets = string.find(string.lower(stat), "(%d+) targets?")
		if targets then
			table.insert(facts, { place = TARGETS, value = targets, label = "Targets" })
		else
			table.insert(facts, { place = REACH, text = stat })
		end
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
	-- A description read only in part is shown as written (Compose), so none
	-- of its facts are listed; the reach, crit and echo above still are.
	local read, partial = ReadFacts(ability.description)
	if partial then
		read = {}
	end
	for index = 1, table.getn(read) do
		local fact = read[index]
		-- "within 7 yd" says again what "7 yd range" said.
		if not (fact.place == REACH and seen[fact.value]) then
			table.insert(facts, fact)
		end
	end
	-- The spell's main effect, its first that is more than a duration or an
	-- interval ("-38% cooldown", an absorb, "-20% enemy damage"), comes right
	-- under the damage, or at the top for a spell that deals none.
	for index = 1, table.getn(facts) do
		local fact = facts[index]
		if fact.place == EFFECT and fact.label ~= "Duration" and fact.label ~= "Interval" then
			fact.place = MAIN
			break
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
	return facts, partial
end

-- The lines of the layout: { left, right, r, g, b, rr, rg, rb } a double
-- line, { left, nil, r, g, b, wrap = true } a line, { rule = color } a blank
-- line with a rule across it.
-- simple: the simplified layout whatever the switch and Shift say (the
-- build's cards always use it).
local function Compose(ability, simple)
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
	if simple or ShowSimplified() then
		local facts, partial = AllFacts(ability)
		-- Its wording too unusual to read in full ("burst in holy light,
		-- dealing 240 Holy damage to every enemy within 9.8 yd of the body"):
		-- the description as the game wrote it, its numbers lit, over the
		-- facts that come from elsewhere (reach, crit, the echo).
		if partial and table.getn(ability.description) > 0 then
			Spacer(tint)
			for index = 1, table.getn(ability.description) do
				Line(Highlight(ability.description[index], school, tint), DESCRIPTION_COLOR)
			end
		end
		if table.getn(facts) > 0 then
			Spacer(tint)
			for index = 1, table.getn(facts) do
				local fact = facts[index]
				if fact.echo then
					-- Its percentage in the game's gold, the words muted as
					-- the other lines' are.
					Line((string.gsub(fact.echo, "(%d+%%)", ECHO_HEX.."%1|r")), MUTED)
				elseif fact.crit then
					Line(CRIT_HEX..ability.critChance.."|r crit", MUTED)
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

	-- What the worn gear adds beyond numbers (a neck's "Whirlwind's hits stun
	-- for 1.5 sec"), under a rule in the game's item green; its numbers in
	-- that green, its words muted. Left off the build's card, which lists the
	-- gear itself.
	local effects = not simple and SurvivorUI_GearEffects and SurvivorUI_GearEffects(ability.title) or {}
	if table.getn(effects) > 0 then
		Spacer(GEAR_GREEN)
		for index = 1, table.getn(effects) do
			Line((string.gsub(effects[index], "(%d[%d%.]*%%?)", GEAR_HEX.."%1|r")), MUTED)
		end
	end

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

-- The simplified description of the spell on an action button, as lines for
-- another card (the build's): everything below the name, the cast line and
-- the rule under them. nil where the button cannot be read.
local abilityScan = CreateFrame("GameTooltip", "SurvivorUIAbilityScan", nil, "GameTooltipTemplate")

-- An action button's ability as read off its tooltip, or nil.
local function ScanAbility(slot)
	if not (slot and HasAction and HasAction(slot)) then
		return nil
	end
	abilityScan:SetOwner(WorldFrame, "ANCHOR_NONE")
	abilityScan:ClearLines()
	abilityScan:SetAction(slot)
	local ok, ability = pcall(Read, abilityScan, "SurvivorUIAbilityScan")
	return ok and ability or nil
end

-- Whether the ability on an action button hits every enemy in reach (its
-- targets read "AoE"), for the build's tiers; nil where it cannot be read.
function SurvivorUI_HitsEveryEnemy(slot)
	local ability = ScanAbility(slot)
	if not ability then
		return nil
	end
	-- Read off the description itself: one read only in part still says
	-- where it hits.
	local listed, facts = pcall(ReadFacts, ability.description)
	if not (listed and facts) then
		return nil
	end
	for index = 1, table.getn(facts) do
		if facts[index].place == TARGETS and facts[index].value == "AoE" then
			return true
		end
	end
	return false
end

function SurvivorUI_SimplifiedLines(slot)
	local ability = ScanAbility(slot)
	if not ability then
		return nil
	end
	local composed, lines = pcall(Compose, ability, true)
	if not (composed and lines) then
		return nil
	end
	local below = {}
	for index = 3, table.getn(lines) do
		if not (index == 3 and lines[index].rule) then
			table.insert(below, lines[index])
		end
	end
	return table.getn(below) > 0 and below or nil
end
-- The game's tooltip as last read, and whether Shift was down when it was
-- laid out: Shift changes nothing the game writes, so a press is caught here
-- and the same tooltip laid out again.
local lastAbility, lastShift

-- Other cards on the game's tooltip (the build's) draw rules the same way:
-- SurvivorUI_TooltipRules({ { line, color }, ... }) once the card is shown,
-- each line a blank one to draw across. The layout then counts as written,
-- so the watcher below leaves it be.
function SurvivorUI_TooltipRules(list)
	HideRules()
	for index = 1, table.getn(list) do
		Rule(list[index][1], list[index][2])
	end
	written = Signature()
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function()
	if not GameTooltip:IsVisible() then
		return
	end
	local signature = Signature()
	local shift = IsShiftKeyDown() and true or false
	if signature == written then
		if lastAbility and shift ~= lastShift then
			lastShift = shift
			HideRules()
			local wrote, done = pcall(Write, lastAbility)
			if wrote and done then
				written = Signature()
			end
		end
		return
	end
	HideRules()
	written = nil
	local ok, ability = pcall(Read)
	if ok and ability then
		lastAbility, lastShift = ability, shift
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
	lastAbility = nil
	if stockHide then
		stockHide()
	end
end)

if SurvivorUI_RegisterOption then
	SurvivorUI_RegisterOption({
		section = "Ability Bar",
		order = 1,
		label = "Simplified Ability Description",
		tip = "Ability tooltips as a list: under the name, rank, cast and cooldown, every number on a line of its own, value first (\"7 yd\", \"826 Physical Damage\", \"+3 Targets\", \"26% crit\"). Hold Shift over an ability for the full description. Off, the description always reads as the game writes it, its numbers in white.",
		get = Simplified,
		toggle = function()
			SurvivorUIDB = SurvivorUIDB or {}
			SurvivorUIDB.simpleTips = not Simplified()
		end,
	})
end
