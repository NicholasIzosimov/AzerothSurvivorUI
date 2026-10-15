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
-- On the action bar every spell also says its chance to cast twice (the
-- hero's Echo, AZS_STATS.echo), as the game itself writes on some of them;
-- where the game already wrote it, its own line stands.
--
-- The game rewrites the tooltip a few times a second while the mouse stays,
-- so the layout is redone whenever its text changes. A tooltip it cannot read
-- is left as the game wrote it.

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

local function Spacer(color)
	GameTooltip:AddLine(" ")
	Rule(GameTooltip:NumLines(), color)
end

local function Write(ability)
	HideRules()
	GameTooltip:ClearLines()
	local school, tint = School(ability)

	if ability.rank then
		GameTooltip:AddDoubleLine(ability.title, ability.rank, tint[1], tint[2], tint[3], MUTED[1], MUTED[2], MUTED[3])
	else
		GameTooltip:AddLine(ability.title, tint[1], tint[2], tint[3])
	end
	-- "3.4 sec" cooldown, "28 yd" range, "7%" crit "204%".
	local cooldown = string.gsub(ability.cooldown or " ", "^([%d%.]+ sec)", COOLDOWN_HEX.."%1|r")
	GameTooltip:AddDoubleLine(ability.cast, cooldown, MUTED[1], MUTED[2], MUTED[3], MUTED[1], MUTED[2], MUTED[3])
	if table.getn(ability.stats) > 0 or ability.crit then
		local reach = string.gsub(table.concat(ability.stats, DOT), "([%d%.]+ yd)", REACH_HEX.."%1|r")
		local crit = string.gsub(ability.crit or " ", "(%d+%%)", CRIT_HEX.."%1|r")
		GameTooltip:AddDoubleLine(reach, crit, MUTED[1], MUTED[2], MUTED[3], MUTED[1], MUTED[2], MUTED[3])
	end

	if table.getn(ability.description) > 0 then
		Spacer(tint)
		for index = 1, table.getn(ability.description) do
			GameTooltip:AddLine(Highlight(ability.description[index], school, tint),
				DESCRIPTION_COLOR[1], DESCRIPTION_COLOR[2], DESCRIPTION_COLOR[3], 1)
		end
	end

	-- The upgrades, bonuses and talents are left out: the card stays short,
	-- and the build's own card lists a spell's upgrades.

	if table.getn(ability.other) > 0 then
		Spacer(MUTED)
		for index = 1, table.getn(ability.other) do
			local other = ability.other[index]
			GameTooltip:AddLine(other.text, other.color[1], other.color[2], other.color[3], 1)
		end
	end

	-- Shown again to fit the new lines, where the game placed it.
	GameTooltip:Show()
end

------------------------------------------------------------------------------
-- The chance to cast twice, for the action bar's tooltips.

local ECHO_COLOR = { 1, 0.82, 0 }
local TIMES = { "once", "twice" }

-- The action button whose tooltip is up, from the game's own opener.
local actionOwner
local stockSetTooltip = ActionButton_SetTooltip
if stockSetTooltip then
	function ActionButton_SetTooltip()
		actionOwner = this
		stockSetTooltip()
	end
end

local function FromActionBar()
	return actionOwner and GameTooltip:IsOwned(actionOwner)
end

local function GameWroteEcho(ability)
	for index = 1, table.getn(ability.other) do
		local text = ability.other[index].text
		if string.find(text, "chance to cast", 1, true) or string.find(text, "^Casts ") then
			return true
		end
	end
end

-- "52% chance to cast twice"; past 100%, "Casts twice, 30% chance to cast
-- more", as the game words it.
local function EchoLine()
	local echo = AZS_STATS and tonumber(AZS_STATS.echo) or 0
	if echo <= 0 then
		return nil
	end
	local sure = math.floor(echo)
	local chance = math.floor((echo - sure) * 100 + 0.5)
	if sure == 0 then
		return chance.."% chance to cast twice"
	end
	local times = TIMES[sure + 1] or (sure + 1).." times"
	if chance == 0 then
		return "Casts "..times
	end
	return "Casts "..times..", "..chance.."% chance to cast more"
end

local function AddEcho(ability)
	if ability.cast == "Passive" or not FromActionBar() or GameWroteEcho(ability) then
		return
	end
	local line = EchoLine()
	if line then
		table.insert(ability.other, { text = line, color = ECHO_COLOR })
	end
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
		pcall(AddEcho, ability)
		if pcall(Write, ability) then
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
