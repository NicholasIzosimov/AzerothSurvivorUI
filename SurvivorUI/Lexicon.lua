-- Survivor UI: the Lexicon, a book of every piece of jewelry the hero has
-- worn, in any run. A wide button at the foot of the build opens it; a
-- bookmark per kind (amulets, rings, trinkets) down its left edge, the pieces
-- of that kind on the page, a few pages to a kind, turned with the arrows at
-- the foot.
--
-- Each piece shows once, at the highest rank seen ("Quick Strike Ring III"),
-- in its quality's color; hover it for its tooltip. The book learns a piece
-- the moment it is worn and keeps it in SurvivorUIDB.lexicon, across runs.
-- The names the build remembered before the book existed (seenGear) are
-- read too, their icon and tooltip found among the game's jewelry items.

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local FONT = SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BUMP = SurvivorUI_FONT_BUMP or 0

local WIDTH = 480
local HEIGHT = 440
local PAD = 14
local TITLE_HEIGHT = 34
local TAB_WIDTH = 118
local TAB_HEIGHT = 26
local TAB_GAP = 4
local ROW_HEIGHT = 28
local ROW_GAP = 3
local ROWS = 10                 -- pieces to a page
local FOOT_HEIGHT = 26
local BUTTON_HEIGHT = 24

local GOLD_EDGE = { 0.62, 0.46, 0.22 }
local GOLD_TEXT = { 1, 0.84, 0.42 }

-- The kinds a run upgrades, in the book's order: the slots that fill them,
-- and the bookmark's name.
local KINDS = {
	{ kind = "Neck",    title = "Amulets",  slots = { 2 },      always = true },
	{ kind = "Ring",    title = "Rings",    slots = { 11, 12 }, always = true },
	{ kind = "Trinket", title = "Trinkets", slots = { 13, 14 }, always = true },
}

-- The game's run jewelry sits in one block of item numbers, read through for
-- the icons and tooltips of pieces remembered by name only.
local JEWELRY_FIRST = 900000
local JEWELRY_LAST = 900999

local function Settings()
	SurvivorUIDB = SurvivorUIDB or {}
	return SurvivorUIDB
end

-- The book, holding only the kinds above: anything else it once kept (the
-- armor and weapons of its first version) is let go.
local function Book()
	local settings = Settings()
	settings.lexicon = settings.lexicon or {}
	local keep = {}
	for index = 1, table.getn(KINDS) do
		keep[KINDS[index].kind] = true
	end
	for kind in pairs(settings.lexicon) do
		if not keep[kind] then
			settings.lexicon[kind] = nil
		end
	end
	return settings.lexicon
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

------------------------------------------------------------------------------
-- Learning: every worn slot, whenever the gear changes.

local function Learn()
	if not GetInventoryItemLink then
		return
	end
	local book = Book()
	for index = 1, table.getn(KINDS) do
		local entry = KINDS[index]
		for slotIndex = 1, table.getn(entry.slots) do
			local slot = entry.slots[slotIndex]
			local link = GetInventoryItemLink("player", slot)
			local _, _, name = string.find(link or "", "%[(.-)%]")
			if name then
				local _, _, hex = string.find(link, "|c(%x%x%x%x%x%x%x%x)")
				local _, _, item = string.find(link, "|H(item:[%-%d:]+)|h")
				book[entry.kind] = book[entry.kind] or {}
				book[entry.kind][name] = {
					hex = hex or "ffffffff",
					link = item,
					icon = GetInventoryItemTexture("player", slot),
				}
			end
		end
	end
end

-- The pieces known by name only (seenGear, from before the book) given
-- their icon and item from the game's jewelry items, once a session.
local filled = false

local function FillFromItems()
	if filled or not GetItemInfo then
		return
	end
	filled = true
	local seen = Settings().seenGear
	if not seen then
		return
	end
	local book = Book()
	local wanted, any = {}, false
	for index = 1, table.getn(KINDS) do
		local kind = KINDS[index].kind
		for name, hex in pairs(seen[kind] or {}) do
			if not (book[kind] and book[kind][name]) then
				wanted[name] = { kind = kind, hex = hex }
				any = true
			end
		end
	end
	if not any then
		return
	end
	for id = JEWELRY_FIRST, JEWELRY_LAST do
		local name, item, _, _, _, _, _, _, icon = GetItemInfo(id)
		local want = name and wanted[name]
		if want then
			book[want.kind] = book[want.kind] or {}
			book[want.kind][name] = { hex = want.hex, link = item, icon = icon }
			wanted[name] = nil
		end
	end
end

-- A kind's pieces, once each by name without rank, at the highest rank seen,
-- by name.
local function Pieces(kind)
	local best = {}
	local function Consider(name, info)
		local base, rank = BaseName(name)
		local known = best[base]
		if not known or rank > known.rank or (rank == known.rank and info.icon and not known.icon) then
			best[base] = { base = base, name = name, rank = rank, hex = info.hex, link = info.link, icon = info.icon }
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
		table.insert(found, piece)
	end
	table.sort(found, function(a, b) return a.base < b.base end)
	return found
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
book.note:SetText("Gear you have worn, in any run")

local close = GoldButton(book, "x", 13)
close:SetWidth(20)
close:SetHeight(20)
close:SetPoint("TOPRIGHT", book, "TOPRIGHT", -8, -8)
close:SetScript("OnClick", function() book:Hide() end)

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
page.empty:SetWidth(240)
page.empty:SetTextColor(0.55, 0.5, 0.45)
page.empty:SetText("Nothing of this kind worn yet.")

local chosen = KINDS[1].kind
local pageNumber = 1
local Draw

------------------------------------------------------------------------------
-- The bookmarks down the left edge.

local tabs = {}

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
	tab:SetScript("OnClick", function()
		chosen = this.kind
		pageNumber = 1
		Draw()
	end)
	tabs[index] = tab
	return tab
end

local function PaintTab(tab, open)
	if open then
		tab.fill:SetGradient("VERTICAL", 0.30, 0.10, 0.06, 0.50, 0.20, 0.10)
		tab.text:SetTextColor(1, 0.95, 0.75)
		tab.count:SetTextColor(1, 0.95, 0.75)
	else
		tab.fill:SetGradient("VERTICAL", 0.13, 0.03, 0.03, 0.26, 0.06, 0.05)
		tab.text:SetTextColor(GOLD_TEXT[1], GOLD_TEXT[2], GOLD_TEXT[3])
		tab.count:SetTextColor(0.62, 0.55, 0.42)
	end
end

------------------------------------------------------------------------------
-- The page's rows.

local rows = {}

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
	row.name:SetPoint("RIGHT", row, "RIGHT", -60, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetShadowColor(0, 0, 0, 1)
	row.name:SetShadowOffset(1, -1)
	row.rank = row:CreateFontString(nil, "OVERLAY")
	row.rank:SetFont(FONT, 11 + FONT_BUMP)
	row.rank:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	row.rank:SetTextColor(0.75, 0.72, 0.66)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetTexture(FLAT)
	row.hover:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
	row.hover:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
	row.hover:SetVertexColor(1, 0.85, 0.5, 0.08)
	row:SetScript("OnEnter", function()
		local piece = this.piece
		if not piece then
			return
		end
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		if piece.link then
			GameTooltip:SetHyperlink(piece.link)
		else
			local color = HexColor(piece.hex)
			GameTooltip:SetText(piece.name, color[1], color[2], color[3])
			GameTooltip:AddLine("Seen before the Lexicon kept details. Wear it again for its tooltip.", 0.6, 0.6, 0.6, 1)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[index] = row
	return row
end

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

local function FillRow(row, piece)
	row.piece = piece
	local color = HexColor(piece.hex)
	row:SetBackdropColor(color[1] * 0.18, color[2] * 0.18, color[3] * 0.18, 0.9)
	row.name:SetText(piece.base)
	row.name:SetTextColor(color[1], color[2], color[3])
	if piece.rank > 1 then
		row.rank:SetText("Rank "..(ROMAN[piece.rank] or piece.rank))
	else
		row.rank:SetText("")
	end
	if piece.icon then
		row.icon:SetTexture(piece.icon)
		row.icon:SetVertexColor(1, 1, 1)
	else
		row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		row.icon:SetVertexColor(0.6, 0.6, 0.6)
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
	local shown, chosenShown = 0, false
	for index = 1, table.getn(KINDS) do
		local entry = KINDS[index]
		local count = table.getn(Pieces(entry.kind))
		local tab = Tab(index)
		if count > 0 or entry.always then
			shown = shown + 1
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

	local pieces = Pieces(chosen)
	local pages = math.max(1, math.ceil(table.getn(pieces) / ROWS))
	pageNumber = math.max(1, math.min(pageNumber, pages))
	local first = (pageNumber - 1) * ROWS
	for index = 1, ROWS do
		local piece = pieces[first + index]
		local row = Row(index)
		if piece then
			FillRow(row, piece)
		else
			row.piece = nil
			row:Hide()
		end
	end
	if table.getn(pieces) == 0 then
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
	FillFromItems()
	Draw()
end)

function SurvivorUI_ToggleLexicon()
	if book:IsShown() then
		book:Hide()
	else
		book:Show()
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
		GameTooltip:AddLine("Every piece of gear you have worn, in any run, by kind (/sui lexicon).", 0.7, 0.7, 0.7, 1)
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
