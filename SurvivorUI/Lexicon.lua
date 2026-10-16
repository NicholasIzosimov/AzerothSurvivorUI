-- Survivor UI: the Lexicon, a book of every piece of jewelry the hero has
-- worn, in any run, and of the hero's abilities. A wide button at the foot of
-- the build opens it, and so does a click on one of the build's rows, at its
-- kind; a bookmark per kind (amulets, rings, trinkets, then abilities) down
-- its left edge, the entries of that kind on the page, a few pages to a kind,
-- turned with the arrows at the foot.
--
-- Jewelry: each piece shows once, at the highest rank seen ("Quick Strike
-- Ring III"), in its quality's color, with the classes that wore it; hover it
-- for its tooltip. The book learns a piece the moment it is worn and keeps it
-- in SurvivorUIDB.lexicon, across runs, its tooltip's lines with it: a piece
-- no longer in the game's item cache still shows its description. The names
-- the build remembered before the book existed (seenGear) are read too; they
-- get their icon and tooltip once worn again. The book never asks the game
-- about items it is not holding: each such ask goes to the server, and a
-- flood of them pushed the worn jewelry out of the game's item cache, its
-- icons gone from the character pane and the build. On the amulets' page a
-- button in the corner keeps it to the ones your class has worn; rings and
-- trinkets suit every class, so their pages always show every piece.
--
-- Abilities: every spell of the hero's class (from the spellbook, the ones
-- not learned yet too) and the best average cast each has reached in a run
-- (from the damage meter's cards, CritCard.lua), with the highest rank it
-- reached and how many runs took it. Kept per class in
-- SurvivorUIDB.abilityBook.
--
-- What a spell can become is in no file the game shares, so the book learns
-- it from the spells' own tooltips (the spellbook's, and the action button's
-- while a run is on): whether the tooltip says it can cast twice or crit,
-- and every upgrade its "Upgrades:" line has ever named, with the best number
-- seen for each. /sui spells lists it all.

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local FONT = SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BUMP = SurvivorUI_FONT_BUMP or 0

local WIDTH = 520
local HEIGHT = 440
local PAD = 14
local TITLE_HEIGHT = 34
local TAB_WIDTH = 118
local TAB_HEIGHT = 26
local TAB_GAP = 4
local ROW_HEIGHT = 28
local ROW_GAP = 3
local ROWS = 10                 -- entries to a page
local BUTTON_HEIGHT = 24
local LINES_KEPT = 30           -- a tooltip's lines kept with its piece

local GOLD_EDGE = { 0.62, 0.46, 0.22 }
local GOLD_TEXT = { 1, 0.84, 0.42 }

-- The kinds, in the book's order: the slots that fill a kind of jewelry, and
-- the bookmark's name. The abilities come last.
local ABILITY = "Ability"
local KINDS = {
	{ kind = "Neck",    title = "Amulets",   slots = { 2 },      always = true },
	{ kind = "Ring",    title = "Rings",     slots = { 11, 12 }, always = true },
	{ kind = "Trinket", title = "Trinkets",  slots = { 13, 14 }, always = true },
	{ kind = ABILITY,   title = "Abilities", always = true },
}

-- An average cast counts from this many casts on, so one lucky blow early in
-- a run does not stand as the best.
local MIN_CASTS = 5

local function Settings()
	SurvivorUIDB = SurvivorUIDB or {}
	return SurvivorUIDB
end

-- The book, holding only the jewelry kinds above: anything else it once kept
-- (the armor and weapons of its first version) is let go.
local function Book()
	local settings = Settings()
	settings.lexicon = settings.lexicon or {}
	local keep = {}
	for index = 1, table.getn(KINDS) do
		if KINDS[index].slots then
			keep[KINDS[index].kind] = true
		end
	end
	for kind in pairs(settings.lexicon) do
		if not keep[kind] then
			settings.lexicon[kind] = nil
		end
	end
	return settings.lexicon
end

local function ClassToken()
	local _, class = UnitClass("player")
	return class or "UNKNOWN"
end

local function ClassName()
	return UnitClass("player") or "your class"
end

-- This class's abilities: { [name] = { icon, best, bestRank, rank, runs, inBook } }.
local function Abilities()
	local settings = Settings()
	settings.abilityBook = settings.abilityBook or {}
	local class = ClassToken()
	settings.abilityBook[class] = settings.abilityBook[class] or {}
	return settings.abilityBook[class]
end

local function Ability(name)
	local book = Abilities()
	book[name] = book[name] or { runs = 0 }
	return book[name]
end

local function HexColor(hex)
	if not hex or string.len(hex) ~= 8 then
		return { 1, 1, 1 }
	end
	return {
		tonumber(string.sub(hex, 3, 4), 16) / 255,
		tonumber(string.sub(hex, 5, 6), 16) / 255,
		tonumber(string.sub(hex, 7, 8), 16) / 255,
	}
end

local function BaseName(name)
	if SurvivorUI_BaseName then
		return SurvivorUI_BaseName(name)
	end
	return name, 1
end

-- 950, 1.2k, 3.4m
local function Short(value)
	local short, suffix
	if value >= 1000000 then
		short, suffix = value / 1000000, "m"
	elseif value >= 1000 then
		short, suffix = value / 1000, "k"
	else
		return math.floor(value + 0.5)
	end
	return (string.gsub(string.format("%.1f", short), "%.0$", ""))..suffix
end

-- A class token's name in its class color: "|cffc79c6eWarrior|r".
local CLASS_NAMES = {
	WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
local CLASS_OVERRIDES = { SHAMAN = { r = 0.00, g = 0.44, b = 0.87 } }

local function ClassText(token)
	local color = CLASS_OVERRIDES[token] or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token])
	local name = CLASS_NAMES[token] or token
	if not color then
		return name
	end
	return string.format("|cff%02x%02x%02x%s|r", math.floor(color.r * 255), math.floor(color.g * 255),
		math.floor(color.b * 255), name)
end

-- The class token for a class's name ("Rogue" is ROGUE), for "Classes:" lines.
local function TokenOf(name)
	for token, known in pairs(CLASS_NAMES) do
		if known == name then
			return token
		end
	end
end

------------------------------------------------------------------------------
-- Learning jewelry: every worn slot, whenever the gear changes, its tooltip
-- read with it while the game still holds it.

local scan = CreateFrame("GameTooltip", "SurvivorUILexiconScan", nil, "GameTooltipTemplate")

-- The lines of a worn piece's tooltip, as { text, r, g, b, right }, and the
-- class it is kept to ("Classes: Rogue"), if any.
local function ReadSlot(slot)
	scan:SetOwner(WorldFrame, "ANCHOR_NONE")
	scan:ClearLines()
	scan:SetInventoryItem("player", slot)
	local lines, only = {}, nil
	for index = 1, math.min(LINES_KEPT, scan:NumLines()) do
		local left = getglobal("SurvivorUILexiconScanTextLeft"..index)
		local right = getglobal("SurvivorUILexiconScanTextRight"..index)
		local text = left and left:GetText()
		if text then
			local r, g, b = left:GetTextColor()
			local rightText = right and right:IsShown() and right:GetText() or nil
			table.insert(lines, { text, r, g, b, rightText })
			local _, _, classes = string.find(text, "^Classes: (.+)$")
			if classes then
				only = classes
			end
		end
	end
	return lines, only
end

local function Learn()
	if not GetInventoryItemLink then
		return
	end
	local book = Book()
	local class = ClassToken()
	for index = 1, table.getn(KINDS) do
		local entry = KINDS[index]
		for slotIndex = 1, table.getn(entry.slots or {}) do
			local slot = entry.slots[slotIndex]
			local link = GetInventoryItemLink("player", slot)
			local _, _, name = string.find(link or "", "%[(.-)%]")
			if name then
				local _, _, hex = string.find(link, "|c(%x%x%x%x%x%x%x%x)")
				local _, _, item = string.find(link, "|H(item:[%-%d:]+)|h")
				book[entry.kind] = book[entry.kind] or {}
				local piece = book[entry.kind][name] or {}
				book[entry.kind][name] = piece
				piece.hex = hex or "ffffffff"
				piece.icon = GetInventoryItemTexture("player", slot) or piece.icon
				piece.classes = piece.classes or {}
				piece.classes[class] = true
				if piece.link ~= item or not piece.lines then
					local lines, only = ReadSlot(slot)
					if table.getn(lines) > 0 then
						piece.lines, piece.only = lines, only
					end
				end
				piece.link = item
			end
		end
	end
end

local function ClassOnly()
	return Settings().lexiconClassOnly == true
end

-- Whether a piece belongs on the page with the class filter as it stands.
-- The kinds whose pieces belong to classes: amulets. Rings and trinkets
-- suit every class alike, so their pages always show every piece and name
-- no classes.
local CLASS_KINDS = { Neck = true }

local function ForThisClass(piece)
	if not (ClassOnly() and CLASS_KINDS[piece.kind]) then
		return true
	end
	local class = ClassToken()
	if piece.only then
		return string.find(piece.only, CLASS_NAMES[class] or class, 1, true) ~= nil
	end
	return piece.classes[class] == true
end

-- A kind's pieces, once each by name without rank, at the highest rank seen,
-- by name; the classes that wore any rank of it together.
local function Pieces(kind)
	local best = {}
	local function Consider(name, info)
		local base, rank = BaseName(name)
		local known = best[base]
		local classes = known and known.classes or {}
		for class in pairs(info.classes or {}) do
			classes[class] = true
		end
		if not known or rank > known.rank or (rank == known.rank and info.icon and not known.icon) then
			best[base] = {
				base = base, name = name, rank = rank, hex = info.hex, link = info.link, icon = info.icon,
				lines = info.lines or (known and known.lines), only = info.only or (known and known.only),
				classes = classes,
			}
		else
			known.lines = known.lines or info.lines
			known.only = known.only or info.only
		end
	end
	local old = Settings().seenGear and Settings().seenGear[kind]
	if old then
		for name, hex in pairs(old) do
			Consider(name, { hex = hex })
		end
	end
	local book = Book()[kind]
	if book then
		for name, info in pairs(book) do
			Consider(name, info)
		end
	end
	local found = {}
	for _, piece in pairs(best) do
		piece.kind = kind
		if ForThisClass(piece) then
			table.insert(found, piece)
		end
	end
	table.sort(found, function(a, b) return a.base < b.base end)
	return found
end

------------------------------------------------------------------------------
-- Learning abilities: the spellbook when the book opens, the run's spells as
-- it goes, and each spell's average cast from the damage meter's cards.

-- The hidden tooltip's lines, each piece of a line with breaks on its own,
-- without colors.
local function ScanTexts()
	local texts = {}
	for index = 1, scan:NumLines() do
		local left = getglobal("SurvivorUILexiconScanTextLeft"..index)
		for piece in string.gfind((left and left:GetText() or "").."\n", "([^\n]*)\n") do
			local text = string.gsub(string.gsub(piece, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
			if text ~= "" then
				table.insert(texts, text)
			end
		end
	end
	return texts
end

-- An upgrade kept by its kind, its numbers as #: "+35% damage" is "+#%
-- damage", with the biggest number seen.
local function NoteUpgrade(ability, item)
	local kind = string.gsub(item, "[%d%.]+", "#")
	local _, _, number = string.find(item, "([%d%.]+)")
	number = tonumber(number) or 0
	ability.upgrades = ability.upgrades or {}
	if not ability.upgrades[kind] or number > ability.upgrades[kind] then
		ability.upgrades[kind] = number
	end
end

-- What the hidden tooltip says of a spell: whether it can cast twice or
-- crit, and its upgrades. A spell not learned yet says neither, so only a
-- learned one's lines count for those two.
local function ReadSpellTip(ability)
	local texts = ScanTexts()
	local learned, echo, crit = true, false, false
	for index = 1, table.getn(texts) do
		local text = texts[index]
		if string.find(text, "^Not learned") then
			learned = false
		elseif string.find(text, "chance to cast", 1, true) or string.find(text, "^Casts ") then
			echo = true
		elseif string.find(text, "chance to crit for", 1, true) then
			crit = true
		elseif string.sub(text, 1, 10) == "Upgrades: " then
			for item in string.gfind(string.sub(text, 11), "[^,]+") do
				item = string.gsub(string.gsub(item, "^%s+", ""), "%s+$", "")
				if item ~= "" then
					NoteUpgrade(ability, item)
				end
			end
		end
	end
	if learned and table.getn(texts) > 0 then
		ability.echoLine, ability.critLine = echo, crit
	end
end

local function ReadSpellbook()
	if not GetSpellName then
		return
	end
	local bookType = BOOKTYPE_SPELL or "spell"
	local index = 1
	while true do
		local name = GetSpellName(index, bookType)
		if not name then
			break
		end
		local ability = Ability(name)
		ability.inBook = true
		ability.icon = GetSpellTexture and GetSpellTexture(index, bookType) or ability.icon
		scan:SetOwner(WorldFrame, "ANCHOR_NONE")
		scan:ClearLines()
		scan:SetSpell(index, bookType)
		ReadSpellTip(ability)
		index = index + 1
	end
end

local function Field(entry, name, index)
	if entry[name] ~= nil then
		return entry[name]
	end
	return entry[index]
end

-- The run's spells (AZS_SPELLS): each one's highest rank, and one more run
-- for each spell the first time a run is seen to hold it.
local function LearnRun()
	if not (AZS_SPELLS and AZS_GetPhase and SurvivorUI_SpellName) then
		return
	end
	local phase = AZS_GetPhase()
	if not phase or phase == "ready" then
		return
	end
	local counted = SurvivorUI_RunMemory and SurvivorUI_RunMemory("lexicon") or {}
	for index = 1, table.getn(AZS_SPELLS) do
		local entry = AZS_SPELLS[index]
		local name = SurvivorUI_SpellName(Field(entry, "key", 1))
		local rank = tonumber(Field(entry, "rank", 3)) or 0
		if name and name ~= "?" then
			local ability = Ability(name)
			ability.rank = math.max(ability.rank or 0, rank)
			if not counted[name] then
				counted[name] = true
				ability.runs = (ability.runs or 0) + 1
			end
			-- Its action button's tooltip, which holds the run's upgrades.
			local slot = SurvivorUI_SpellSlot and SurvivorUI_SpellSlot(name)
			if slot and HasAction(slot) then
				scan:SetOwner(WorldFrame, "ANCHOR_NONE")
				scan:ClearLines()
				scan:SetAction(slot)
				ReadSpellTip(ability)
			end
		end
	end
end

-- The rank a run's spell stands at now, or nil.
local function RankNow(name)
	if not (AZS_SPELLS and SurvivorUI_SpellName) then
		return nil
	end
	for index = 1, table.getn(AZS_SPELLS) do
		local entry = AZS_SPELLS[index]
		if SurvivorUI_SpellName(Field(entry, "key", 1)) == name then
			return tonumber(Field(entry, "rank", 3))
		end
	end
end

-- From the damage meter's cards (CritCard.lua): an ability's average cast so
-- far this run, over this many casts.
function SurvivorUI_LexiconAverage(name, average, casts)
	if not (name and average and casts and casts >= MIN_CASTS) then
		return
	end
	local ability = Ability(name)
	if not ability.best or average > ability.best then
		ability.best = average
		ability.bestRank = RankNow(name) or ability.bestRank
	end
end

-- This class's abilities for the page: the best averages first, the most
-- first, then the rest by name.
local function AbilityList()
	local found = {}
	for name, info in pairs(Abilities()) do
		table.insert(found, {
			base = name, name = name, icon = info.icon, best = info.best, bestRank = info.bestRank,
			rank = info.rank, runs = info.runs or 0, ability = true,
		})
	end
	table.sort(found, function(a, b)
		if (a.best ~= nil) ~= (b.best ~= nil) then
			return a.best ~= nil
		end
		if a.best and a.best ~= b.best then
			return a.best > b.best
		end
		return a.name < b.name
	end)
	return found
end

local function Entries(kind)
	if kind == ABILITY then
		return AbilityList()
	end
	return Pieces(kind)
end

------------------------------------------------------------------------------
-- The button styled as the options window's Reload UI: gold edge, deep red.

local function GoldButton(parent, text, size)
	local button = CreateFrame("Button", nil, parent)
	button:SetBackdrop({
		bgFile = FLAT, edgeFile = FLAT, tile = false, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	button:SetBackdropColor(0, 0, 0, 0)
	button:SetBackdropBorderColor(GOLD_EDGE[1], GOLD_EDGE[2], GOLD_EDGE[3], 1)
	button.fill = button:CreateTexture(nil, "BACKGROUND")
	button.fill:SetTexture(FLAT)
	button.fill:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
	button.fill:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
	button.fill:SetGradient("VERTICAL", 0.13, 0.03, 0.03, 0.26, 0.06, 0.05)
	button.text = button:CreateFontString(nil, "OVERLAY")
	button.text:SetFont(FONT, (size or 14) + FONT_BUMP)
	button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
	button.text:SetTextColor(GOLD_TEXT[1], GOLD_TEXT[2], GOLD_TEXT[3])
	button.text:SetShadowColor(0, 0, 0, 1)
	button.text:SetShadowOffset(1, -1)
	button.text:SetText(text)
	button.hover = button:CreateTexture(nil, "HIGHLIGHT")
	button.hover:SetTexture(FLAT)
	button.hover:SetAllPoints(button.fill)
	button.hover:SetVertexColor(1, 0.8, 0.4, 0.08)
	return button
end

------------------------------------------------------------------------------
-- The book.

local book = CreateFrame("Frame", "SurvivorUILexicon", UIParent)
book:SetWidth(WIDTH)
book:SetHeight(HEIGHT)
book:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
book:SetFrameStrata("DIALOG")
book:SetBackdrop({
	bgFile = FLAT, edgeFile = FLAT, tile = false, edgeSize = 1,
	insets = { left = 1, right = 1, top = 1, bottom = 1 },
})
book:SetBackdropColor(0.07, 0.05, 0.04, 0.96)
book:SetBackdropBorderColor(GOLD_EDGE[1], GOLD_EDGE[2], GOLD_EDGE[3], 1)
book:SetMovable(true)
book:EnableMouse(true)
book:SetClampedToScreen(true)
book:RegisterForDrag("LeftButton")
book:SetScript("OnDragStart", function() this:StartMoving() end)
book:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
book:Hide()
table.insert(UISpecialFrames, "SurvivorUILexicon")

book.title = book:CreateFontString(nil, "OVERLAY")
book.title:SetFont(FONT, 18 + FONT_BUMP)
book.title:SetPoint("TOPLEFT", book, "TOPLEFT", PAD, -PAD + 2)
book.title:SetTextColor(GOLD_TEXT[1], GOLD_TEXT[2], GOLD_TEXT[3])
book.title:SetShadowColor(0, 0, 0, 1)
book.title:SetShadowOffset(1, -1)
book.title:SetText("Lexicon")

book.note = book:CreateFontString(nil, "OVERLAY")
book.note:SetFont(FONT, 11 + FONT_BUMP)
book.note:SetPoint("BOTTOMLEFT", book.title, "BOTTOMRIGHT", 10, 1)
book.note:SetTextColor(0.6, 0.55, 0.48)

local close = GoldButton(book, "x", 13)
close:SetWidth(20)
close:SetHeight(20)
close:SetPoint("TOPRIGHT", book, "TOPRIGHT", -8, -8)
close:SetScript("OnClick", function() book:Hide() end)

local Draw

-- The class filter, left of the close button: every piece, or only the ones
-- this class has worn (or is kept to).
local filter = GoldButton(book, "", 11)
filter:SetWidth(110)
filter:SetHeight(20)
filter:SetPoint("RIGHT", close, "LEFT", -6, 0)
filter:SetScript("OnClick", function()
	Settings().lexiconClassOnly = not ClassOnly()
	Draw()
end)
filter:SetScript("OnEnter", function()
	GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
	GameTooltip:SetText("Class filter", 1, 1, 1)
	GameTooltip:AddLine("Show every piece, or only those your "..ClassName().." has worn or is kept to. Pieces from before the Lexicon kept classes show only under every class.", 0.7, 0.7, 0.7, 1)
	GameTooltip:Show()
end)
filter:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- The spine: a gold line between the bookmarks and the page.
local spine = book:CreateTexture(nil, "ARTWORK")
spine:SetTexture(FLAT)
spine:SetVertexColor(GOLD_EDGE[1], GOLD_EDGE[2], GOLD_EDGE[3], 0.7)
spine:SetWidth(1)
spine:SetPoint("TOPLEFT", book, "TOPLEFT", PAD + TAB_WIDTH + 8, -TITLE_HEIGHT - 4)
spine:SetPoint("BOTTOMLEFT", book, "BOTTOMLEFT", PAD + TAB_WIDTH + 8, PAD)

-- The page: a slightly lighter leaf right of the spine.
local page = CreateFrame("Frame", nil, book)
page:SetPoint("TOPLEFT", book, "TOPLEFT", PAD + TAB_WIDTH + 16, -TITLE_HEIGHT - 4)
page:SetPoint("BOTTOMRIGHT", book, "BOTTOMRIGHT", -PAD, PAD)
page.leaf = page:CreateTexture(nil, "BACKGROUND")
page.leaf:SetTexture(FLAT)
page.leaf:SetAllPoints(page)
page.leaf:SetVertexColor(0.11, 0.08, 0.06, 0.9)

page.empty = page:CreateFontString(nil, "OVERLAY")
page.empty:SetFont(FONT, 12 + FONT_BUMP)
page.empty:SetPoint("CENTER", page, "CENTER", 0, 10)
page.empty:SetWidth(260)
page.empty:SetTextColor(0.55, 0.5, 0.45)

local chosen = KINDS[1].kind
local pageNumber = 1

------------------------------------------------------------------------------
-- The bookmarks down the left edge. Hovered, a bookmark's words fade to white
-- and its leaf lifts a little.

local tabs = {}

local function TabColors(tab)
	if tab.open then
		return { 1, 0.95, 0.75 }, { 1, 0.95, 0.75 }
	end
	return GOLD_TEXT, { 0.62, 0.55, 0.42 }
end

local function PaintTabHover(tab, fade)
	local text, count = TabColors(tab)
	tab.text:SetTextColor(text[1] + (1 - text[1]) * fade, text[2] + (1 - text[2]) * fade, text[3] + (1 - text[3]) * fade)
	tab.count:SetTextColor(count[1] + (1 - count[1]) * fade, count[2] + (1 - count[2]) * fade, count[3] + (1 - count[3]) * fade)
	tab.glow:SetAlpha(0.14 * fade)
end

local function Tab(index)
	local tab = tabs[index]
	if tab then
		return tab
	end
	tab = GoldButton(book, "", 12)
	tab:SetWidth(TAB_WIDTH)
	tab:SetHeight(TAB_HEIGHT)
	tab.text:ClearAllPoints()
	tab.text:SetPoint("LEFT", tab, "LEFT", 8, 0)
	tab.count = tab:CreateFontString(nil, "OVERLAY")
	tab.count:SetFont(FONT, 11 + FONT_BUMP)
	tab.count:SetPoint("RIGHT", tab, "RIGHT", -7, 0)
	tab.count:SetShadowColor(0, 0, 0, 1)
	tab.count:SetShadowOffset(1, -1)
	-- The fade's own lift in place of the stock highlight, which pops.
	tab.hover:SetVertexColor(1, 0.8, 0.4, 0)
	tab.glow = tab:CreateTexture(nil, "ARTWORK")
	tab.glow:SetTexture(FLAT)
	tab.glow:SetAllPoints(tab.fill)
	tab.glow:SetVertexColor(1, 0.85, 0.55, 1)
	tab.glow:SetAlpha(0)
	tab:SetScript("OnEnter", function()
		if SurvivorUI_Fade then
			SurvivorUI_Fade(this, 1, PaintTabHover)
		end
	end)
	tab:SetScript("OnLeave", function()
		if SurvivorUI_Fade then
			SurvivorUI_Fade(this, 0, PaintTabHover)
		end
	end)
	tab:SetScript("OnClick", function()
		chosen = this.kind
		pageNumber = 1
		Draw()
	end)
	tabs[index] = tab
	return tab
end

local function PaintTab(tab, open)
	tab.open = open
	if open then
		tab.fill:SetGradient("VERTICAL", 0.30, 0.10, 0.06, 0.50, 0.20, 0.10)
	else
		tab.fill:SetGradient("VERTICAL", 0.13, 0.03, 0.03, 0.26, 0.06, 0.05)
	end
	PaintTabHover(tab, tab.fade or 0)
end

------------------------------------------------------------------------------
-- The page's rows.

local rows = {}

-- A piece's tooltip: the game's own while it is worn or in the game's item
-- cache, else the lines the book kept when it was worn, else its name.
local function WornSlot(piece)
	for index = 1, table.getn(KINDS) do
		local slots = KINDS[index].slots or {}
		for slotIndex = 1, table.getn(slots) do
			local link = GetInventoryItemLink and GetInventoryItemLink("player", slots[slotIndex])
			local _, _, name = string.find(link or "", "%[(.-)%]")
			if name and name == piece.name then
				return slots[slotIndex]
			end
		end
	end
end

local function PieceTooltip(owner, piece)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local slot = WornSlot(piece)
	if slot then
		GameTooltip:SetInventoryItem("player", slot)
	elseif piece.lines and table.getn(piece.lines) > 0 then
		for index = 1, table.getn(piece.lines) do
			local line = piece.lines[index]
			if index == 1 then
				GameTooltip:SetText(line[1], line[2], line[3], line[4])
			elseif line[5] then
				GameTooltip:AddDoubleLine(line[1], line[5], line[2], line[3], line[4], line[2], line[3], line[4])
			else
				GameTooltip:AddLine(line[1], line[2], line[3], line[4], 1)
			end
		end
	elseif piece.link then
		GameTooltip:SetHyperlink(piece.link)
	else
		local color = HexColor(piece.hex)
		GameTooltip:SetText(piece.name, color[1], color[2], color[3])
		GameTooltip:AddLine("Seen before the Lexicon kept details. Wear it again for its tooltip.", 0.6, 0.6, 0.6, 1)
	end
	local worn = {}
	for class in pairs(CLASS_KINDS[piece.kind] and piece.classes or {}) do
		table.insert(worn, ClassText(class))
	end
	if table.getn(worn) > 0 then
		table.sort(worn)
		GameTooltip:AddLine("Worn as: "..table.concat(worn, ", "), 0.7, 0.7, 0.7, 1)
	end
	GameTooltip:Show()
end

-- An ability's upgrades seen, each with its best number: "+160% damage".
local function UpgradeKinds(info)
	local kinds = {}
	for kind, best in pairs(info.upgrades or {}) do
		local shown = math.floor(best) == best and tostring(best) or string.format("%.1f", best)
		table.insert(kinds, (string.gsub(kind, "#", shown, 1)))
	end
	table.sort(kinds)
	return kinds
end

local function AbilityTooltip(owner, ability)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(ability.name, 1, 1, 1)
	if ability.best then
		GameTooltip:AddDoubleLine("Best average cast", Short(ability.best)
			..(ability.bestRank and "  |cffa0a0a0at rank "..ability.bestRank.."|r" or ""),
			0.7, 0.7, 0.7, 1, 0.82, 0.3)
	else
		GameTooltip:AddLine("No average cast yet: it needs "..MIN_CASTS.." casts in a run.", 0.55, 0.55, 0.55, 1)
	end
	if ability.rank and ability.rank > 0 then
		GameTooltip:AddDoubleLine("Highest rank", ability.rank, 0.7, 0.7, 0.7, 1, 1, 1)
	end
	GameTooltip:AddDoubleLine("Runs taken", ability.runs or 0, 0.7, 0.7, 0.7, 1, 1, 1)
	local info = Abilities()[ability.name] or {}
	if info.echoLine ~= nil then
		GameTooltip:AddDoubleLine("Casts twice", info.echoLine and "|cff4dff4dyes|r" or "|cffff6060no line|r", 0.7, 0.7, 0.7, 1, 1, 1)
		GameTooltip:AddDoubleLine("Crits", info.critLine and "|cff4dff4dyes|r" or "|cffff6060no line|r", 0.7, 0.7, 0.7, 1, 1, 1)
	end
	local kinds = UpgradeKinds(info)
	if table.getn(kinds) > 0 then
		GameTooltip:AddLine("Upgrades seen (best)", 1, 0.82, 0)
		for index = 1, table.getn(kinds) do
			GameTooltip:AddLine("  "..kinds[index], 0.85, 0.85, 0.85)
		end
	end
	GameTooltip:AddLine("The average cast is the damage meter card's: what one cast dealt on average over a run.", 0.45, 0.45, 0.45, 1)
	GameTooltip:Show()
end

local function Row(index)
	local row = rows[index]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, page)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -6 - (index - 1) * (ROW_HEIGHT + ROW_GAP))
	row:SetPoint("TOPRIGHT", page, "TOPRIGHT", -6, -6 - (index - 1) * (ROW_HEIGHT + ROW_GAP))
	row:SetBackdrop({
		bgFile = FLAT, edgeFile = FLAT, tile = false, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	row:SetBackdropBorderColor(0, 0, 0, 1)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetWidth(ROW_HEIGHT - 4)
	row.icon:SetHeight(ROW_HEIGHT - 4)
	row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.name = row:CreateFontString(nil, "OVERLAY")
	row.name:SetFont(FONT, 12 + FONT_BUMP)
	row.name:SetPoint("LEFT", row, "LEFT", ROW_HEIGHT + 4, 0)
	row.name:SetHeight(14)
	row.name:SetJustifyH("LEFT")
	row.name:SetShadowColor(0, 0, 0, 1)
	row.name:SetShadowOffset(1, -1)
	row.rank = row:CreateFontString(nil, "OVERLAY")
	row.rank:SetFont(FONT, 11 + FONT_BUMP)
	row.rank:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	row.rank:SetJustifyH("RIGHT")
	row.rank:SetTextColor(0.75, 0.72, 0.66)
	-- The classes that wore a piece, small, left of its rank.
	row.classes = row:CreateFontString(nil, "OVERLAY")
	row.classes:SetFont(FONT, 9 + FONT_BUMP, "OUTLINE")
	row.classes:SetPoint("RIGHT", row, "RIGHT", -62, 0)
	row.classes:SetJustifyH("RIGHT")
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetTexture(FLAT)
	row.hover:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
	row.hover:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
	row.hover:SetVertexColor(1, 0.85, 0.5, 0.08)
	row:SetScript("OnEnter", function()
		local entry = this.entry
		if not entry then
			return
		end
		if entry.ability then
			AbilityTooltip(this, entry)
		else
			PieceTooltip(this, entry)
		end
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[index] = row
	return row
end

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

-- The classes as tags: one or two by name, more as a count.
local function ClassTags(piece)
	local tokens = {}
	if piece.only then
		for name in string.gfind(piece.only, "[^,]+") do
			local token = TokenOf((string.gsub(string.gsub(name, "^%s+", ""), "%s+$", "")))
			if token then
				table.insert(tokens, token)
			end
		end
	end
	if table.getn(tokens) == 0 then
		for class in pairs(piece.classes or {}) do
			table.insert(tokens, class)
		end
	end
	table.sort(tokens)
	if table.getn(tokens) > 2 then
		return "|cffb0b0b0"..table.getn(tokens).." classes|r"
	end
	local texts = {}
	for index = 1, table.getn(tokens) do
		table.insert(texts, ClassText(tokens[index]))
	end
	return table.concat(texts, " ")
end

local function FillPiece(row, piece)
	local color = HexColor(piece.hex)
	row:SetBackdropColor(color[1] * 0.18, color[2] * 0.18, color[3] * 0.18, 0.9)
	row.name:SetText(piece.base)
	row.name:SetTextColor(color[1], color[2], color[3])
	if piece.rank > 1 then
		row.rank:SetText("Rank "..(ROMAN[piece.rank] or piece.rank))
	else
		row.rank:SetText("")
	end
	row.classes:SetText(CLASS_KINDS[piece.kind] and ClassTags(piece) or "")
	if piece.icon then
		row.icon:SetTexture(piece.icon)
		row.icon:SetVertexColor(1, 1, 1)
	else
		row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		row.icon:SetVertexColor(0.6, 0.6, 0.6)
	end
end

-- An ability: white once a run has taken it, grey before; its best average
-- cast on the right in gold.
local function FillAbility(row, ability)
	local used = (ability.runs or 0) > 0 or ability.best
	row:SetBackdropColor(0.12, 0.10, 0.08, 0.9)
	row.name:SetText(ability.name)
	if used then
		row.name:SetTextColor(1, 1, 1)
	else
		row.name:SetTextColor(0.55, 0.55, 0.55)
	end
	if ability.best then
		row.rank:SetText("|cffffd24d"..Short(ability.best).."|r |cffa0a0a0avg|r")
	else
		row.rank:SetText("|cff6a6a6a-|r")
	end
	if ability.rank and ability.rank > 0 then
		row.classes:SetText("|cffa0a0a0rank "..ability.rank.."|r")
	else
		row.classes:SetText("")
	end
	if ability.icon then
		row.icon:SetTexture(ability.icon)
		row.icon:SetVertexColor(1, 1, 1)
	else
		row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		row.icon:SetVertexColor(0.6, 0.6, 0.6)
	end
end

local function FillRow(row, entry)
	row.entry = entry
	-- The name runs up to the tags on its right.
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row, "LEFT", ROW_HEIGHT + 4, 0)
	row.name:SetPoint("RIGHT", row, "RIGHT", entry.ability and -130 or -132, 0)
	if entry.ability then
		FillAbility(row, entry)
	else
		FillPiece(row, entry)
	end
	row:Show()
end

------------------------------------------------------------------------------
-- The foot: page arrows and the page count.

local back = GoldButton(page, "<", 13)
back:SetWidth(28)
back:SetHeight(20)
back:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 6, 6)
back:SetScript("OnClick", function()
	pageNumber = pageNumber - 1
	Draw()
end)

local forward = GoldButton(page, ">", 13)
forward:SetWidth(28)
forward:SetHeight(20)
forward:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -6, 6)
forward:SetScript("OnClick", function()
	pageNumber = pageNumber + 1
	Draw()
end)

local pageText = page:CreateFontString(nil, "OVERLAY")
pageText:SetFont(FONT, 11 + FONT_BUMP)
pageText:SetPoint("BOTTOM", page, "BOTTOM", 0, 10)
pageText:SetTextColor(0.62, 0.55, 0.42)

local function Enable(button, on)
	if on then
		button:Enable()
		button:SetAlpha(1)
	else
		button:Disable()
		button:SetAlpha(0.35)
	end
end

------------------------------------------------------------------------------
-- Drawing the book: the bookmarks with their counts, the chosen kind's page.

Draw = function()
	local y = -TITLE_HEIGHT - 4
	local chosenShown = false
	for index = 1, table.getn(KINDS) do
		local entry = KINDS[index]
		local count = table.getn(Entries(entry.kind))
		local tab = Tab(index)
		if count > 0 or entry.always then
			tab.kind = entry.kind
			tab.text:SetText(entry.title)
			tab.count:SetText(count)
			tab:ClearAllPoints()
			tab:SetPoint("TOPLEFT", book, "TOPLEFT", PAD, y)
			y = y - TAB_HEIGHT - TAB_GAP
			PaintTab(tab, entry.kind == chosen)
			tab:Show()
			chosenShown = chosenShown or entry.kind == chosen
		else
			tab:Hide()
		end
	end
	if not chosenShown then
		chosen = KINDS[1].kind
		PaintTab(Tab(1), true)
	end

	if chosen == ABILITY then
		book.note:SetText("Your "..ClassName().." abilities and their best average cast")
		page.empty:SetText("No abilities seen yet: open your spellbook once, or play a run.")
		filter:Hide()
	else
		book.note:SetText("Gear you have worn, in any run")
		local byClass = CLASS_KINDS[chosen] and ClassOnly()
		page.empty:SetText(byClass and "Nothing of this kind worn as "..ClassName().." yet."
			or "Nothing of this kind worn yet.")
		-- The class filter only where classes matter: the amulets.
		if CLASS_KINDS[chosen] then
			filter.text:SetText(ClassOnly() and ClassName().." only" or "Every class")
			filter:Show()
		else
			filter:Hide()
		end
	end

	local entries = Entries(chosen)
	local pages = math.max(1, math.ceil(table.getn(entries) / ROWS))
	pageNumber = math.max(1, math.min(pageNumber, pages))
	local first = (pageNumber - 1) * ROWS
	for index = 1, ROWS do
		local entry = entries[first + index]
		local row = Row(index)
		if entry then
			FillRow(row, entry)
		else
			row.entry = nil
			row:Hide()
		end
	end
	if table.getn(entries) == 0 then
		page.empty:Show()
	else
		page.empty:Hide()
	end
	pageText:SetText("Page "..pageNumber.." of "..pages)
	Enable(back, pageNumber > 1)
	Enable(forward, pageNumber < pages)
end

book:SetScript("OnShow", function()
	Learn()
	ReadSpellbook()
	LearnRun()
	Draw()
end)

-- /sui spells: every spell of this class with what its tooltip says: casts
-- twice, crits, and the upgrades seen on it so far.
function SurvivorUI_SpellReport()
	ReadSpellbook()
	LearnRun()
	local say = function(text) DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Survivor UI spells:|r "..text) end
	local names = {}
	for name, info in pairs(Abilities()) do
		if info.inBook then
			table.insert(names, name)
		end
	end
	table.sort(names)
	if table.getn(names) == 0 then
		say("no spells read yet; open the spellbook once or start a run.")
		return
	end
	local function Mark(value)
		if value == nil then
			return "|cff9a9a9a?|r"
		end
		return value and "|cff4dff4dyes|r" or "|cffff6060no|r"
	end
	for index = 1, table.getn(names) do
		local info = Abilities()[names[index]]
		local kinds = UpgradeKinds(info)
		say(names[index]..": casts twice "..Mark(info.echoLine)..", crits "..Mark(info.critLine)
			..(table.getn(kinds) > 0 and ", upgrades seen: "..table.concat(kinds, ", ") or ""))
	end
	say("? = not learned in any run read yet. Upgrades fill in as runs show them.")
end

function SurvivorUI_ToggleLexicon()
	if book:IsShown() then
		book:Hide()
	else
		book:Show()
	end
end

-- The book open at a kind ("Ring", "Ability"); for an ability, at the page
-- that holds the one named.
function SurvivorUI_OpenLexicon(kind, name)
	local known = false
	for index = 1, table.getn(KINDS) do
		known = known or KINDS[index].kind == kind
	end
	if not known then
		kind = KINDS[1].kind
	end
	chosen = kind
	pageNumber = 1
	if book:IsShown() then
		Draw()
	else
		book:Show()
	end
	if name then
		local entries = Entries(kind)
		for index = 1, table.getn(entries) do
			if entries[index].name == name then
				pageNumber = math.ceil(index / ROWS)
				Draw()
				break
			end
		end
	end
end

------------------------------------------------------------------------------
-- The button at the foot of the build, inside its box: the build lays it out
-- under the gear (SurvivorUI_BuildFooter).

local build = getglobal("SurvivorUIBuild")
if build then
	local open = GoldButton(build, "Lexicon", 14)
	open:SetHeight(BUTTON_HEIGHT)
	SurvivorUI_BuildFooter = open
	open:SetScript("OnClick", SurvivorUI_ToggleLexicon)
	open:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_LEFT")
		GameTooltip:SetText("Lexicon", 1, 1, 1)
		GameTooltip:AddLine("Every piece of gear you have worn, in any run, by kind, and your abilities with their best average cast (/sui lexicon).", 0.7, 0.7, 0.7, 1)
		GameTooltip:Show()
	end)
	open:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local learner = CreateFrame("Frame")
learner:RegisterEvent("PLAYER_ENTERING_WORLD")
learner:RegisterEvent("UNIT_INVENTORY_CHANGED")
learner:SetScript("OnEvent", function()
	if event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then
		return
	end
	Learn()
	if book:IsShown() then
		Draw()
	end
end)

-- The run's spells, every few seconds while one is on.
local learned = 0
learner:SetScript("OnUpdate", function()
	learned = learned + arg1
	if learned < 3 then
		return
	end
	learned = 0
	LearnRun()
end)
