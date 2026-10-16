-- Survivor UI: the build, in the right column between the run timer and the
-- damage meter: two boxes in one, the spells and the jewelry.
--
-- Spells: every spell slot, filled or not, each with its icon, its name, its
-- rank and its share of the damage, in the color of gear of its standing
-- (common up to legendary, by what its upgrades add up to), leaving out the racial (it takes no
-- slot and no upgrades). Empty slots show, since how many
-- are left matters at every card choice; the count sits in the middle of the
-- heading. The rarest spells run first; within a rarity the damage spells by their share, the utility ones under them by rank.
--
-- Gear: the pieces a run upgrades, the neck, the two rings and the two
-- trinkets, each in its quality's color.
--
-- Hover a spell or a piece for a card on its right: its rank and what it has
-- taken so far, read off its own tooltip. Hover an empty slot for what could
-- fill it: the spells not learned yet (from the spellbook), or the jewelry of
-- that kind worn in earlier runs (the game shares no list of its own, so the
-- build remembers every piece it sees). Each box folds away with the button
-- in its heading's corner; click a row to open the Lexicon at its kind. From
-- the game's addon API (AZS_SPELLS); without it
-- nothing shows. Hold Alt and drag to move; /sui build hides it.

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local FONT = SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BUMP = SurvivorUI_FONT_BUMP or 0

local WIDTH = 224
local ROW_HEIGHT = 18
local HEADER_HEIGHT = 20
local SECTION_GAP = 6
local SLOTS = 6                 -- spell slots a run has
local MUTED = { 0.45, 0.45, 0.45 }
-- A spell wears the color of gear of its standing, judged by what its upgrades
-- add up to (its score, see SpellScore below), in common picks' worth: up to
-- rare every 5, then epic at 20 and legendary at 30, so the top two take
-- clearly more. Where the upgrades cannot be read yet, its rank stands in on
-- the same steps. wash is how strongly its row is filled (white needs less to
-- stay readable).
local COMMON_PICK = 10          -- placeholder: the score one common pick adds
local TIERS = {                 -- from the top: rank reached, score reached, color, wash
	{ 30, 30 * COMMON_PICK, { 1.00, 0.50, 0.00 }, 0.45 },   -- legendary
	{ 20, 20 * COMMON_PICK, { 0.64, 0.21, 0.93 }, 0.45 },   -- epic
	{ 10, 10 * COMMON_PICK, { 0.00, 0.44, 0.87 }, 0.45 },   -- rare
	{ 5,  5 * COMMON_PICK,  { 0.12, 1.00, 0.00 }, 0.40 },   -- uncommon
	{ 0,  0,                { 1.00, 1.00, 1.00 }, 0.22 },   -- common
}

-- Each slotted spell's tier color, for the damage meter's bars, by lower case
-- name. A common spell's white would hide the meter's white text: its bar is
-- grey instead.
local spellColors = {}
local COMMON_BAR = { 0.55, 0.55, 0.58 }

function SurvivorUI_SpellColor(name)
	return name and spellColors[string.lower(name)]
end

-- The tier a score earns, or with no score, the tier the rank earns: its
-- color, its wash, and its place in TIERS (1 is legendary).
local function Tier(score, rank)
	local value, column = rank or 0, 1
	if score then
		value, column = score, 2
	end
	for index = 1, table.getn(TIERS) do
		local tier = TIERS[index]
		if value >= tier[column] then
			return tier[3], tier[4], index
		end
	end
	local last = TIERS[table.getn(TIERS)]
	return last[3], last[4], table.getn(TIERS)
end

-- A utility spell (no damage on the meter: a shout, a stun, a heal) has fewer
-- upgrades that carry a number (no extra targets, no damage), so its score,
-- or its rank where the score cannot be read, counts a little more toward its
-- tier.
local UTIL_LENIENCY = 1.25      -- placeholder

local function IsUtility(name)
	local share = SurvivorUI_MeterShare and SurvivorUI_MeterShare(name)
	return not share or share <= 0
end

local function SpellTier(name, score, rank)
	if IsUtility(name) then
		score = score and score * UTIL_LENIENCY
		rank = rank and rank * UTIL_LENIENCY
	end
	return Tier(score, rank)
end
local UPGRADES = "Upgrades: "   -- how a tooltip begins its list of upgrades
local GEAR_SLOTS = {            -- inventory slot, label
	{ 2, "Neck" }, { 11, "Ring" }, { 12, "Ring" }, { 13, "Trinket" }, { 14, "Trinket" },
}
-- Lines of an item's tooltip that say nothing about what it gives.
local ITEM_SKIP = { "^Durability", "^Requires", "^Item Level", "^Sell Price", "^Binds", "^Unique", "^Classes" }

local function Settings()
	SurvivorUIDB = SurvivorUIDB or {}
	if SurvivorUIDB.buildList == nil then
		SurvivorUIDB.buildList = true
	end
	return SurvivorUIDB
end

local function Field(entry, name, index)
	if entry[name] ~= nil then
		return entry[name]
	end
	return entry[index]
end

-- "holy_wrath" as the meter and the cards name it: "Holy Wrath".
local NAMES = {
	sw_pain = "Shadow Word: Pain", pw_shield = "Power Word: Shield",
	demo_shout = "Demoralizing Shout", hunters_mark = "Hunter's Mark",
}

-- Small words stay small inside a name, as the game writes it: "Hammer of
-- Justice", "Hammer of the Righteous".
local SMALL_WORDS = { ["of"] = true, ["the"] = true, ["and"] = true, ["a"] = true, ["to"] = true }

local function SpellName(key)
	if NAMES[key] then
		return NAMES[key]
	end
	local name = string.gsub(key or "?", "_", " ")
	local first = true
	return (string.gsub(name, "(%a)([%w']*)", function(letter, rest)
		local word = letter..rest
		if not first and SMALL_WORDS[word] then
			return word
		end
		first = false
		return string.upper(letter)..rest
	end))
end

local function Running()
	if not (AZS_GetPhase and AZS_SPELLS) then
		return false
	end
	local phase = AZS_GetPhase()
	return phase and phase ~= "ready"
end

-- "ffa335ee" into { 0.64, 0.21, 0.93 }.
local function HexColor(hex)
	if not hex or string.len(hex) ~= 8 then
		return { 1, 1, 1 }
	end
	local function Part(from)
		return (tonumber(string.sub(hex, from, from + 1), 16) or 0) / 255
	end
	return { Part(3), Part(5), Part(7) }
end

------------------------------------------------------------------------------
-- Reading a tooltip: a hidden one, filled from the spell's action button or
-- the item's slot.

local scan = CreateFrame("GameTooltip", "SurvivorUIScanTip", nil, "GameTooltipTemplate")
scan:SetOwner(WorldFrame, "ANCHOR_NONE")

local function Plain(text)
	text = string.gsub(text or "", "|c%x%x%x%x%x%x%x%x", "")
	return (string.gsub(text, "|r", ""))
end

-- Each text the hidden tooltip holds from line 'from' on, a line with breaks
-- in it taken piece by piece.
local function ScanTexts(from)
	local texts = {}
	for index = from, scan:NumLines() do
		local left = getglobal("SurvivorUIScanTipTextLeft"..index)
		for piece in string.gfind((left and left:GetText() or "").."\n", "([^\n]*)\n") do
			local text = Plain(piece)
			if text ~= "" then
				table.insert(texts, text)
			end
		end
	end
	return texts
end

-- "Upgrades: +35% damage, +1 target" into its entries, added to list.
local function AddUpgrades(text, list)
	if string.sub(text, 1, string.len(UPGRADES)) ~= UPGRADES then
		return false
	end
	for item in string.gfind(string.sub(text, string.len(UPGRADES) + 1), "[^,]+") do
		item = string.gsub(item, "^%s+", "")
		item = string.gsub(item, "%s+$", "")
		if item ~= "" then
			table.insert(list, item)
		end
	end
	return true
end

-- The icon of the spell whose tooltip lists this talent ("Talents: Hallowed
-- Ground, Hammer of the Righteous"): a talent's proc wears its spell's icon in
-- the damage meter, as the game's talents have no icon an addon can read.
local TALENTS = "Talents: "

function SurvivorUI_TalentOwnerIcon(talent)
	local wanted = string.lower(talent or "")
	if wanted == "" or not AZS_SPELLS then
		return nil
	end
	local slotted = math.max(0, table.getn(AZS_SPELLS) - 1)
	for slot = 1, slotted do
		if HasAction and HasAction(slot) then
			scan:SetOwner(WorldFrame, "ANCHOR_NONE")
			scan:ClearLines()
			scan:SetAction(slot)
			local texts = ScanTexts(1)
			for index = 1, table.getn(texts) do
				local text = texts[index]
				if string.sub(text, 1, string.len(TALENTS)) == TALENTS then
					for item in string.gfind(string.sub(text, string.len(TALENTS) + 1), "[^,]+") do
						item = string.gsub(string.gsub(item, "^%s+", ""), "%s+$", "")
						if string.lower(item) == wanted then
							return GetActionTexture(slot)
						end
					end
				end
			end
		end
	end
end

-- For /sui icons: each slotted spell's tooltip line naming its talents, as
-- read, so its wording can be checked against what the meter looks for.
function SurvivorUI_DebugTalentLines(say)
	local slotted = AZS_SPELLS and math.max(0, table.getn(AZS_SPELLS) - 1) or 0
	for slot = 1, slotted do
		if HasAction and HasAction(slot) then
			scan:SetOwner(WorldFrame, "ANCHOR_NONE")
			scan:ClearLines()
			scan:SetAction(slot)
			local texts = ScanTexts(1)
			local found = false
			for index = 1, table.getn(texts) do
				if string.find(string.lower(texts[index]), "talent", 1, true) then
					say("action "..slot.." ("..(texts[1] or "?").."): ["..texts[index].."]")
					found = true
				end
			end
			if not found then
				say("action "..slot.." ("..(texts[1] or "?").."): no talent line")
			end
		else
			say("action "..slot..": empty")
		end
	end
end

local function SpellUpgrades(slot)
	local found = {}
	if not (slot and HasAction and HasAction(slot)) then
		return found
	end
	scan:SetOwner(WorldFrame, "ANCHOR_NONE")
	scan:ClearLines()
	scan:SetAction(slot)
	local texts = ScanTexts(1)
	for index = 1, table.getn(texts) do
		AddUpgrades(texts[index], found)
	end
	return found
end

-- Which action button holds a spell, by the name its tooltip opens with: the
-- game's spell list need not run in the action bar's order. The buttons are
-- read again only when one of them changes.
local MAX_ACTION_SLOT = 120
local slotByName, slotSignature = {}, nil

local function SpellSlot(name)
	local parts = {}
	for slot = 1, MAX_ACTION_SLOT do
		if HasAction(slot) then
			table.insert(parts, slot.."="..(GetActionTexture(slot) or ""))
		end
	end
	local signature = table.concat(parts, ";")
	if signature ~= slotSignature then
		slotSignature = signature
		slotByName = {}
		for slot = MAX_ACTION_SLOT, 1, -1 do
			if HasAction(slot) then
				scan:SetOwner(WorldFrame, "ANCHOR_NONE")
				scan:ClearLines()
				scan:SetAction(slot)
				local first = getglobal("SurvivorUIScanTipTextLeft1")
				local text = first and Plain(first:GetText())
				if text and text ~= "" then
					slotByName[string.lower(text)] = slot
				end
			end
		end
	end
	return name and slotByName[string.lower(name)]
end

-- An item's rank, where its tooltip names one, and what it gives: its
-- upgrades and every line with a number in it.
local function ItemDetails(slot)
	local rank, found = nil, {}
	scan:SetOwner(WorldFrame, "ANCHOR_NONE")
	scan:ClearLines()
	scan:SetInventoryItem("player", slot)
	local texts = ScanTexts(2)
	for index = 1, table.getn(texts) do
		local text = texts[index]
		local _, _, number = string.find(text, "^Rank (%d+)")
		if number then
			rank = tonumber(number)
		elseif not AddUpgrades(text, found) and string.find(text, "%d") then
			local skipped = false
			for skip = 1, table.getn(ITEM_SKIP) do
				if string.find(text, ITEM_SKIP[skip]) then
					skipped = true
					break
				end
			end
			if not skipped then
				table.insert(found, text)
			end
		end
	end
	return rank, found
end

-- What the worn gear does for one spell: every "Equip:" line naming it, off
-- every worn piece. "Increases the area of Consecration by 50%." adds to that
-- stat ("Reduces" takes away), the same stat from several pieces added up;
-- any other line naming it is an effect of its own ("Enemies Consecration
-- kills explode for 30% of their max health"). An effect that is a count the
-- upgrades also have is read as that stat: "Sinister Strike strikes 6 more
-- targets" is targets +6, beside the upgrades' own targets.
local GEAR_STAT = "^(%a+) the (.-) of .- by ([%d%.]+)%%"
local GEAR_COUNTS = {           -- pattern, stat
	{ "(%d+) more targets?", "targets" },
	{ "(%d+) additional targets?", "targets" },
	{ "(%d+) more enem%a+", "targets" },
	{ "(%d+) additional enem%a+", "targets" },
}

-- unit: "%" for a percentage, "" for a count.
local function AddGearStat(gear, stat, value, unit)
	if not gear.stats[stat] then
		gear.stats[stat] = 0
		gear.units[stat] = unit
		table.insert(gear.order, stat)
	end
	gear.stats[stat] = gear.stats[stat] + value
end

local function GearForSpell(spell)
	local gear = { stats = {}, order = {}, effects = {}, units = {} }
	local wanted = string.lower(spell or "")
	if wanted == "" then
		return gear
	end
	for slot = 1, 19 do
		if GetInventoryItemLink and GetInventoryItemLink("player", slot) then
			scan:SetOwner(WorldFrame, "ANCHOR_NONE")
			scan:ClearLines()
			scan:SetInventoryItem("player", slot)
			local texts = ScanTexts(2)
			for index = 1, table.getn(texts) do
				local text = texts[index]
				if string.find(string.lower(text), wanted, 1, true) then
					local body = string.gsub(text, "^Equip: ", "")
					local lower = string.lower(body)
					local _, _, verb, stat, value = string.find(lower, GEAR_STAT)
					value = tonumber(value)
					if value and (verb == "increases" or verb == "reduces") then
						if verb == "reduces" then
							value = -value
						end
						AddGearStat(gear, stat, value, "%")
					else
						local counted = false
						for count = 1, table.getn(GEAR_COUNTS) do
							local _, _, number = string.find(lower, GEAR_COUNTS[count][1])
							if number then
								AddGearStat(gear, GEAR_COUNTS[count][2], tonumber(number), "")
								counted = true
								break
							end
						end
						if not counted then
							table.insert(gear.effects, (string.gsub(body, "%.$", "")))
						end
					end
				end
			end
		end
	end
	return gear
end

-- +50%, -10%
-- unit: "%" (the default) or "" for a count ("+6").
local function Signed(value, unit)
	local text = string.format("%g", value)..(unit or "%")
	if value > 0 then
		text = "+"..text
	end
	return text
end

-- The spells a level-up may still offer: the spellbook holds every spell of
-- the hero, the unlearned ones too, and says so on their tooltip ("Not learned
-- yet: a level-up may offer it.", "Not learned" in the rank's place).
local function UnlearnedSpells()
	local found, seen = {}, {}
	local book = BOOKTYPE_SPELL or "spell"
	local index = 1
	while true do
		local name = GetSpellName(index, book)
		if not name then
			break
		end
		if not seen[name] then
			seen[name] = true
			scan:SetOwner(WorldFrame, "ANCHOR_NONE")
			scan:ClearLines()
			scan:SetSpell(index, book)
			local right = getglobal("SurvivorUIScanTipTextRight1")
			local unlearned = right and Plain(right:GetText()) == "Not learned"
			if not unlearned then
				local texts = ScanTexts(1)
				for line = 1, table.getn(texts) do
					if string.find(texts[line], "^Not learned") then
						unlearned = true
						break
					end
				end
			end
			if unlearned then
				table.insert(found, { name = name })
			end
		end
		index = index + 1
	end
	table.sort(found, function(a, b) return a.name < b.name end)
	return found
end

-- The jewelry the hero has worn, in any run, by kind: the game shares no list
-- of what a cache may hold, so the build learns it piece by piece.
local KIND_NAMES = { Neck = "Amulets", Ring = "Rings", Trinket = "Trinkets" }

local function RememberGear(kind, name, hex)
	local settings = Settings()
	settings.seenGear = settings.seenGear or {}
	settings.seenGear[kind] = settings.seenGear[kind] or {}
	settings.seenGear[kind][name] = hex or "ffffffff"
end

-- A piece's name without its rank, and the rank: "Quick Strike Ring III" is
-- "Quick Strike Ring", 3; a name with no numeral is rank 1.
local ROMAN_VALUES = { I = 1, V = 5, X = 10, L = 50, C = 100 }

local function BaseName(name)
	local _, _, base, numeral = string.find(name, "^(.-) ([IVXLC]+)$")
	if not base then
		return name, 1
	end
	local value, last = 0, 0
	for index = string.len(numeral), 1, -1 do
		local digit = ROMAN_VALUES[string.sub(numeral, index, index)]
		if digit < last then
			value = value - digit
		else
			value = value + digit
			last = digit
		end
	end
	return base, value
end

SurvivorUI_BaseName = BaseName
SurvivorUI_SpellName = SpellName
SurvivorUI_SpellSlot = SpellSlot

-- Every piece of this kind seen before and not worn now, once per piece
-- whatever its rank: by its name without the rank, in the color of the
-- highest rank seen.
local function GearPool(kind)
	local worn = {}
	for index = 1, table.getn(GEAR_SLOTS) do
		local link = GetInventoryItemLink and GetInventoryItemLink("player", GEAR_SLOTS[index][1])
		local _, _, name = string.find(link or "", "%[(.-)%]")
		if name then
			worn[BaseName(name)] = true
		end
	end
	local best = {}                 -- [base name] = { name, hex, rank }
	local seen = Settings().seenGear and Settings().seenGear[kind] or {}
	for name, hex in pairs(seen) do
		local base, rank = BaseName(name)
		if not worn[base] and (not best[base] or rank > best[base].rank) then
			best[base] = { name = base, hex = hex, rank = rank }
		end
	end
	local found = {}
	for _, entry in pairs(best) do
		table.insert(found, entry)
	end
	table.sort(found, function(a, b) return a.name < b.name end)
	return found
end

------------------------------------------------------------------------------
-- The card on hover: the name in its color, the rank, then each upgrade on a
-- line of its own ("Damage ... +35%"). On the build's right.

-- A spell's score: its upgrades added up as damage-equivalent points. A
-- percentage counts its value as shown ("+35% damage", "-14% cooldown", area,
-- duration, healing, absorb), since a pick's rarity shows in how big it is.
-- An extra target weighs far more, 24 points each: +1 target lands a little
-- above an uncommon pick, +2 near a rare to epic one. Upgrades combined on one
-- card add up.
local TARGET_POINTS = 24        -- placeholder

local function Score(entries)
	local score = 0
	for index = 1, table.getn(entries) do
		local text = entries[index]
		local _, _, targets = string.find(text, "^%+(%d+) targets?")
		local _, _, percent = string.find(text, "^[%+%-]?([%d%.]+)%%")
		if targets then
			score = score + tonumber(targets) * TARGET_POINTS
		elseif percent then
			score = score + (tonumber(percent) or 0)
		end
	end
	return score
end

-- The worn gear counts too: each stat its "Equip:" lines give the spell
-- (GearForSpell) adds its size as a percentage does, "+50% area" 50 and
-- "-10% cooldown" 10. Its other effects carry no number and add nothing.
local function GearScore(name)
	local gear = GearForSpell(name)
	local score = 0
	for index = 1, table.getn(gear.order) do
		local stat = gear.order[index]
		-- Extra targets from gear weigh as the upgrades' own do.
		local weight = stat == "targets" and TARGET_POINTS or 1
		score = score + math.abs(gear.stats[stat]) * weight
	end
	return score
end

-- Scores are read off the spell's tooltip and the worn gear, again when its
-- rank changes and every few seconds (so new gear shows within a few); while
-- the action bar is empty (the cards are up) the last score holds.
local SCORE_REFRESH = 5
local scores = {}               -- [spell name] = { score, rank, at }

local function SpellScore(name, slot, rank)
	local known = scores[name]
	if known and known.rank == rank and GetTime() - known.at < SCORE_REFRESH then
		return known.score
	end
	if not (slot and HasAction and HasAction(slot)) then
		return known and known.score
	end
	local score = Score(SpellUpgrades(slot)) + GearScore(name)
	scores[name] = { score = score, rank = rank, at = GetTime() }
	return score
end

local function Capital(text)
	return string.upper(string.sub(text, 1, 1))..string.sub(text, 2)
end

-- What the gear adds shows in its own color beside the upgrades.
local GEAR_HEX = "|cffffa040"

-- gear (optional, from GearForSpell): a stat the gear adds to sits beside the
-- upgrade's value ("+160%  +50%"), a stat only the gear touches gets a row of
-- its own, and the gear's other effects follow under "Gear Effects".
local function ShowCard(owner, title, color, rank, heading, entries, empty, score, gear)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, color[1], color[2], color[3])
	if rank then
		GameTooltip:AddDoubleLine("Rank", rank, 0.62, 0.62, 0.62, 1, 1, 1)
	end
	if score then
		GameTooltip:AddDoubleLine("Upgrade score", math.floor(score + 0.5), 0.62, 0.62, 0.62, color[1], color[2], color[3])
	end
	-- Thin rules part the card's sections: over the upgrades, and over the
	-- gear's effects. Each sits on a blank line of its own.
	local rules = {}
	local function Rule(rule)
		GameTooltip:AddLine(" ")
		table.insert(rules, { GameTooltip:NumLines(), rule })
	end
	Rule(color)
	local gearStats = gear and table.getn(gear.order) > 0
	if table.getn(entries) == 0 and not gearStats then
		GameTooltip:AddLine(empty, 0.55, 0.55, 0.55)
	else
		GameTooltip:AddLine(heading..(gearStats and "  "..GEAR_HEX.."+ gear|r" or ""), 1, 0.82, 0)
		local merged = {}
		for index = 1, table.getn(entries) do
			local text = entries[index]
			local _, _, value, label = string.find(text, "^([%+%-]?[%d%.]+%%?) (.+)$")
			if value then
				local stat = string.lower(label)
				if gear and gear.stats[stat] then
					value = value.."  "..GEAR_HEX..Signed(gear.stats[stat], gear.units[stat]).."|r"
					merged[stat] = true
				end
				GameTooltip:AddDoubleLine("  "..Capital(label), value, 0.8, 0.8, 0.8, 0.45, 1, 0.45)
			else
				GameTooltip:AddLine("  "..Capital(text), 0.8, 0.8, 0.8, 1)
			end
		end
		if gear then
			for index = 1, table.getn(gear.order) do
				local stat = gear.order[index]
				if not merged[stat] then
					GameTooltip:AddDoubleLine("  "..Capital(stat), GEAR_HEX..Signed(gear.stats[stat], gear.units[stat]).."|r", 0.8, 0.8, 0.8, 1, 1, 1)
				end
			end
		end
	end
	if gear and table.getn(gear.effects) > 0 then
		Rule({ 1, 0.63, 0.25 })
		GameTooltip:AddLine("Gear Effects", 1, 0.63, 0.25)
		for index = 1, table.getn(gear.effects) do
			-- Its percentages in the gear's orange, as in the upgrades.
			local effect = string.gsub(gear.effects[index], "([%+%-]?%d[%d%.]*%%)", GEAR_HEX.."%1|r")
			GameTooltip:AddLine("  "..effect, 0.8, 0.8, 0.8, 1)
		end
	end
	GameTooltip:AddLine("Click to open the Lexicon.", 0.45, 0.45, 0.45)
	GameTooltip:Show()
	if SurvivorUI_TooltipRules then
		SurvivorUI_TooltipRules(rules)
	end
end

-- What could fill an empty slot: a heading, one line per choice, and a note
-- on where the list comes from.
local function ShowPool(owner, title, entries, empty, note)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, 1, 0.82, 0)
	if table.getn(entries) == 0 then
		GameTooltip:AddLine(empty, 0.55, 0.55, 0.55, 1)
	else
		for index = 1, table.getn(entries) do
			local entry = entries[index]
			local color = entry.hex and HexColor(entry.hex) or { 0.9, 0.9, 0.9 }
			GameTooltip:AddLine("  "..entry.name, color[1], color[2], color[3])
		end
	end
	GameTooltip:AddLine(note, 0.55, 0.55, 0.55, 1)
	GameTooltip:AddLine("Click to open the Lexicon.", 0.45, 0.45, 0.45)
	GameTooltip:Show()
end

local function RowEnter()
	if this.gearSlot then
		if this.itemName then
			local rank, entries = ItemDetails(this.gearSlot)
			ShowCard(this, this.itemName, this.color, rank, "Gives", entries, "Nothing to read")
		else
			local kind = this.gearKind
			ShowPool(this, (KIND_NAMES[kind] or kind).." seen in your runs", GearPool(kind),
				"None seen yet.",
				"The game shares no list of what a cache can hold, so this one grows with every piece you wear.")
		end
	elseif this.ability then
		ShowCard(this, this.ability, this.color or { 1, 1, 1 }, this.rankValue or "-", "Upgrades",
			SpellUpgrades(this.actionSlot), "No upgrades yet", this.score, GearForSpell(this.ability))
	elseif this.emptySpell then
		ShowPool(this, "Spells you could learn", UnlearnedSpells(),
			"None left in your spellbook.",
			"Not learned yet: a level-up may offer them.")
	end
end

------------------------------------------------------------------------------
-- The frame.

local list = CreateFrame("Frame", "SurvivorUIBuild", UIParent)
list:SetWidth(WIDTH + 12)
list:SetHeight(100)
list:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -12, -260)
list:SetBackdrop({ bgFile = FLAT })
list:SetBackdropColor(0.03, 0.03, 0.05, 0.85)
list:SetMovable(true)
list:Hide()

local function SavePlace()
	local settings = Settings()
	settings.buildLeft = math.floor(list:GetLeft() + 0.5)
	settings.buildTop = math.floor(list:GetTop() + 0.5)
end

local function RestorePlace()
	local settings = Settings()
	list:ClearAllPoints()
	if settings.buildLeft then
		list:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", settings.buildLeft, settings.buildTop)
	elseif SurvivorUITracker then
		-- Under the run timer, right edges together.
		list:SetPoint("TOPRIGHT", SurvivorUITracker, "BOTTOMRIGHT", 8, -14)
	else
		list:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -12, -260)
	end
end

local Draw

-- A box's heading: its name on the left, a fold button in the right corner.
-- key is the setting that keeps it folded.
local function Heading(text, key)
	local heading = CreateFrame("Frame", nil, list)
	heading:SetWidth(WIDTH)
	heading:SetHeight(HEADER_HEIGHT)

	heading.title = heading:CreateFontString(nil, "OVERLAY")
	heading.title:SetFont(FONT, 11 + FONT_BUMP, "OUTLINE")
	heading.title:SetPoint("LEFT", heading, "LEFT", 1, 0)
	heading.title:SetTextColor(1, 0.82, 0)
	heading.title:SetText(text)

	-- A small boxed button: a dark square with a thin edge that brightens on
	-- hover, so it reads as a button.
	local fold = CreateFrame("Button", nil, heading)
	fold:SetWidth(14)
	fold:SetHeight(14)
	fold:SetPoint("RIGHT", heading, "RIGHT", -1, 0)
	fold.edge = fold:CreateTexture(nil, "BACKGROUND")
	fold.edge:SetTexture(FLAT)
	fold.edge:SetVertexColor(0.45, 0.45, 0.5, 1)
	fold.edge:SetPoint("TOPLEFT", fold, "TOPLEFT", -1, 1)
	fold.edge:SetPoint("BOTTOMRIGHT", fold, "BOTTOMRIGHT", 1, -1)
	fold.fill = fold:CreateTexture(nil, "BORDER")
	fold.fill:SetTexture(FLAT)
	fold.fill:SetVertexColor(0.08, 0.08, 0.11, 1)
	fold.fill:SetAllPoints(fold)
	SurvivorUI_PlusMinus(fold, 8)
	SurvivorUI_TintPlus(fold, 0.75, 0.75, 0.75)
	fold:SetScript("OnEnter", function()
		SurvivorUI_TintPlus(this, 1, 1, 1)
		this.edge:SetVertexColor(1, 0.82, 0, 1)
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText(Settings()[key] and "Unfold" or "Fold away", 1, 1, 1)
		GameTooltip:Show()
	end)
	fold:SetScript("OnLeave", function()
		SurvivorUI_TintPlus(this, 0.75, 0.75, 0.75)
		this.edge:SetVertexColor(0.45, 0.45, 0.5, 1)
		GameTooltip:Hide()
	end)
	fold:SetScript("OnClick", function()
		local settings = Settings()
		settings[key] = not settings[key]
		GameTooltip:Hide()
		Draw()
	end)
	heading.fold = fold
	heading.key = key
	return heading
end

local spellHeading = Heading("Build", "buildFolded")
spellHeading.count = spellHeading:CreateFontString(nil, "OVERLAY")
spellHeading.count:SetFont(FONT, 10 + FONT_BUMP, "OUTLINE")
spellHeading.count:SetPoint("CENTER", spellHeading, "CENTER", 0, 0)

local gearHeading = Heading("Gear", "gearFolded")

local function Row(pool, index)
	local row = pool[index]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, list)
	row:SetWidth(WIDTH)
	row:SetHeight(ROW_HEIGHT)

	row.wash = row:CreateTexture(nil, "BACKGROUND")
	row.wash:SetTexture(FLAT)
	row.wash:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
	row.wash:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 1)

	row.rule = row:CreateTexture(nil, "BORDER")
	row.rule:SetTexture(FLAT)
	row.rule:SetHeight(1)
	row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

	-- A border in the row's color, hidden on an empty one.
	row.edges = {}
	for _, side in pairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local line = row:CreateTexture(nil, "OVERLAY")
		line:SetTexture(FLAT)
		if side == "TOP" or side == "BOTTOM" then
			line:SetHeight(1)
			line:SetPoint(side.."LEFT", row, side.."LEFT", 0, 0)
			line:SetPoint(side.."RIGHT", row, side.."RIGHT", 0, 0)
		else
			line:SetWidth(1)
			line:SetPoint("TOP"..side, row, "TOP"..side, 0, 0)
			line:SetPoint("BOTTOM"..side, row, "BOTTOM"..side, 0, 0)
		end
		line:Hide()
		table.insert(row.edges, line)
	end

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetWidth(ROW_HEIGHT - 4)
	row.icon:SetHeight(ROW_HEIGHT - 4)
	row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.name = row:CreateFontString(nil, "OVERLAY")
	row.name:SetFont(FONT, 9 + FONT_BUMP, "OUTLINE")
	row.name:SetPoint("LEFT", row, "LEFT", ROW_HEIGHT + 2, 0)
	row.name:SetWidth(WIDTH - ROW_HEIGHT - 70)
	row.name:SetHeight(12)
	row.name:SetJustifyH("LEFT")

	row.share = row:CreateFontString(nil, "OVERLAY")
	row.share:SetFont(FONT, 8 + FONT_BUMP, "OUTLINE")
	row.share:SetPoint("RIGHT", row, "RIGHT", -44, 0)
	row.share:SetTextColor(0.6, 0.6, 0.6)

	row.rank = row:CreateFontString(nil, "OVERLAY")
	row.rank:SetFont(FONT, 10 + FONT_BUMP, "OUTLINE")
	row.rank:SetPoint("RIGHT", row, "RIGHT", -4, 0)

	row:EnableMouse(true)
	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- A click opens the Lexicon at this row's kind: the jewelry's own page,
	-- or the abilities for a spell.
	row:SetScript("OnMouseUp", function()
		if arg1 ~= "LeftButton" or not SurvivorUI_OpenLexicon then
			return
		end
		GameTooltip:Hide()
		if this.gearKind then
			SurvivorUI_OpenLexicon(this.gearKind)
		elseif this.ability or this.emptySpell then
			SurvivorUI_OpenLexicon("Ability", this.ability)
		end
	end)

	pool[index] = row
	return row
end

local spellRows, gearRows = {}, {}

local function Border(row, color, alpha)
	for index = 1, table.getn(row.edges) do
		local line = row.edges[index]
		if alpha and alpha > 0 then
			line:SetVertexColor(color[1], color[2], color[3], alpha)
			line:Show()
		else
			line:Hide()
		end
	end
end

-- Every row wears a thin black edge; a filled row's color is dulled a little
-- toward grey, so the rarities read without glaring.
local BLACK = { 0, 0, 0 }
local ROW_GAP = 3               -- the space between rows

local function Dull(color)
	return { color[1] * 0.65 + 0.08, color[2] * 0.65 + 0.08, color[3] * 0.65 + 0.08 }
end

-- A row filled with its (dulled) color, the text light over it; an empty slot
-- only a faint wash, the text in the color. wash, when given, is the fill's
-- strength.
local function Paint(row, color, alpha, filled, wash)
	if filled then
		local dull = Dull(color)
		row.name:SetTextColor(1, 1, 1)
		row.rank:SetTextColor(1, 1, 1)
		row.share:SetTextColor(0.9, 0.9, 0.9)
		row.wash:SetVertexColor(dull[1], dull[2], dull[3], wash or 0.5)
	else
		row.name:SetTextColor(color[1], color[2], color[3])
		row.rank:SetTextColor(color[1], color[2], color[3])
		row.share:SetTextColor(0.6, 0.6, 0.6)
		row.wash:SetVertexColor(color[1], color[2], color[3], 0.07 * alpha)
	end
	row.rule:SetVertexColor(0, 0, 0, 0)
	Border(row, BLACK, filled and 1 or 0.7)
end

local function Place(row, y)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", list, "TOPLEFT", 6, y)
	row:Show()
	return y - ROW_HEIGHT - ROW_GAP
end

local function HideAll(pool)
	for index = 1, table.getn(pool) do
		pool[index]:Hide()
	end
end

------------------------------------------------------------------------------
-- The spells.

local function FillSpell(row, entry, actionSlot)
	local key = Field(entry, "key", 1)
	local name = SpellName(key)
	local rank = tonumber(Field(entry, "rank", 3))
	local score = SpellScore(name, actionSlot, rank)
	local color, wash = SpellTier(name, score, rank)
	row.score = score
	row.ability, row.color = name, color
	row.actionSlot, row.rankValue = actionSlot, rank
	row.emptySpell = nil
	row.icon:SetTexture(GetActionTexture and GetActionTexture(actionSlot) or nil)
	row.icon:SetVertexColor(1, 1, 1)
	row.icon:SetAlpha(1)
	row.name:SetText(name)
	row.rank:SetText(rank or "")
	-- Its share of the damage: whole percents from 1%, one decimal under that
	-- ("0.4%"), and "Util" for a spell that deals none (a stun, a heal, a shield).
	local share = SurvivorUI_MeterShare and SurvivorUI_MeterShare(name)
	if not share or share <= 0 then
		row.share:SetText("Util")
	elseif share >= 0.01 then
		row.share:SetText(math.floor(share * 100 + 0.5).."%")
	else
		row.share:SetText(string.format("%.1f%%", share * 100))
	end
	Paint(row, color, 1, true, wash)
end

local function EmptySpell(row)
	row.ability, row.color = nil, nil
	row.actionSlot, row.rankValue, row.score = nil, nil, nil
	row.emptySpell = true
	row.icon:SetTexture(FLAT)
	row.icon:SetVertexColor(0.15, 0.15, 0.18)
	row.icon:SetAlpha(0.8)
	row.name:SetText("empty slot")
	row.rank:SetText("")
	row.share:SetText("")
	Paint(row, MUTED, 0.6)
end

local function DrawSpells(y)
	local spells = AZS_SPELLS or {}
	local count = table.getn(spells)
	-- The racial comes last in the game's list and takes no slot.
	local slotted = math.max(0, count - 1)
	spellHeading.count:SetText((slotted >= SLOTS and "|cffff8080" or "|cffd0d0d0")..math.min(slotted, SLOTS).." / "..SLOTS.."|r")
	-- The rarest first; within a rarity, the damage spells by their share of
	-- the damage, the most first, then the utility ones under them by rank.
	-- Ties go to the earlier slot. Each spell keeps its own action button for
	-- its icon and its tooltip. The tiers are worked out even while the box is
	-- folded, as the damage meter wears their colors too.
	local order, standing, slots = {}, {}, {}
	for name in pairs(spellColors) do
		spellColors[name] = nil
	end
	for index = 1, slotted do
		table.insert(order, index)
		local rank = tonumber(Field(spells[index], "rank", 3)) or 0
		local name = SpellName(Field(spells[index], "key", 1))
		slots[index] = SpellSlot(name) or index
		local score = SpellScore(name, slots[index], rank)
		local color, _, tier = SpellTier(name, score, rank)
		-- A spell with no damage on the meter is a utility one ("Util").
		local share = SurvivorUI_MeterShare and SurvivorUI_MeterShare(name)
		standing[index] = { tier = tier, rank = rank, share = share or 0, util = not share or share <= 0 }
		spellColors[string.lower(name)] = tier == table.getn(TIERS) and COMMON_BAR or color
	end
	if Settings().buildFolded then
		HideAll(spellRows)
		return y
	end
	table.sort(order, function(a, b)
		local sa, sb = standing[a], standing[b]
		if sa.tier ~= sb.tier then
			return sa.tier < sb.tier
		end
		-- Within a rarity, the damage spells first, the utility ones under them.
		if sa.util ~= sb.util then
			return sb.util
		end
		-- Damage spells by their share of the damage; utility ones by rank.
		if not sa.util and sa.share ~= sb.share then
			return sa.share > sb.share
		end
		if sa.util and sa.rank ~= sb.rank then
			return sa.rank > sb.rank
		end
		return a < b
	end)
	for place = 1, SLOTS do
		local row = Row(spellRows, place)
		local index = order[place]
		if index then
			FillSpell(row, spells[index], slots[index])
		else
			EmptySpell(row)
		end
		y = Place(row, y)
	end
	return y
end

------------------------------------------------------------------------------
-- The gear: neck, rings, trinkets, each in its quality's color.

local function DrawGear(y)
	if Settings().gearFolded then
		HideAll(gearRows)
		return y
	end
	for index = 1, table.getn(GEAR_SLOTS) do
		local slot, label = GEAR_SLOTS[index][1], GEAR_SLOTS[index][2]
		local row = Row(gearRows, index)
		row.gearSlot, row.gearKind = slot, label
		row.share:SetText("")
		local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
		if link then
			local _, _, name = string.find(link, "%[(.-)%]")
			local _, _, hex = string.find(link, "|c(%x%x%x%x%x%x%x%x)")
			local color = HexColor(hex)
			row.itemName, row.color = name or "?", color
			if name then
				RememberGear(label, name, hex)
			end
			row.icon:SetTexture(GetInventoryItemTexture("player", slot))
			row.icon:SetVertexColor(1, 1, 1)
			row.icon:SetAlpha(1)
			row.name:SetText(row.itemName)
			row.rank:SetText(label)
			Paint(row, color, 1, true)
			row.rank:SetTextColor(0.85, 0.85, 0.85)
		else
			row.itemName, row.color = nil, nil
			row.icon:SetTexture(FLAT)
			row.icon:SetVertexColor(0.15, 0.15, 0.18)
			row.icon:SetAlpha(0.8)
			row.name:SetText("empty")
			row.rank:SetText(label)
			Paint(row, MUTED, 0.6)
		end
		y = Place(row, y)
	end
	return y
end

------------------------------------------------------------------------------
-- Laying both boxes out, the frame sized to them.

local function Fold(heading)
	SurvivorUI_SetPlus(heading.fold, Settings()[heading.key])
end

Draw = function()
	local y = -4
	spellHeading:ClearAllPoints()
	spellHeading:SetPoint("TOPLEFT", list, "TOPLEFT", 6, y)
	Fold(spellHeading)
	y = DrawSpells(y - HEADER_HEIGHT)

	y = y - SECTION_GAP
	gearHeading:ClearAllPoints()
	gearHeading:SetPoint("TOPLEFT", list, "TOPLEFT", 6, y)
	Fold(gearHeading)
	y = DrawGear(y - HEADER_HEIGHT)

	-- The Lexicon's button, at the foot inside the box.
	local footer = SurvivorUI_BuildFooter
	if footer then
		y = y - SECTION_GAP
		footer:ClearAllPoints()
		footer:SetPoint("TOPLEFT", list, "TOPLEFT", 6, y)
		footer:SetPoint("TOPRIGHT", list, "TOPRIGHT", -6, y)
		y = y - footer:GetHeight() - 2
	end

	list:SetHeight(-y + 4)
end

local elapsed = 0
local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function()
	elapsed = elapsed + arg1
	if elapsed < 0.25 then
		return
	end
	elapsed = 0
	-- In preview (before the first step, or with Alt held) it shows anyway, so
	-- it can be placed.
	if Settings().buildList and (Running() or (SurvivorUI_Preview and SurvivorUI_Preview())) then
		Draw()
		if not list:IsShown() then
			list:Show()
		end
	elseif list:IsShown() then
		list:Hide()
	end
end)

function SurvivorUI_ToggleBuild()
	local settings = Settings()
	settings.buildList = not settings.buildList
	DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: build "..(settings.buildList and "shown." or "hidden."))
end

if SurvivorUI_RegisterOption then
	SurvivorUI_RegisterOption({
		section = "General",
		label = "Build",
		tip = "Your spells and the jewelry a run upgrades, in the right column. Hover one for its rank and upgrades; each box folds away with the button in its corner.",
		command = "/sui build",
		get = function() return Settings().buildList end,
		toggle = SurvivorUI_ToggleBuild,
	})
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", RestorePlace)

if SurvivorUI_RegisterMover then
	SurvivorUI_RegisterMover(list, "Build", SavePlace, nil, RestorePlace)
end
