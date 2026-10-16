-- Survivor UI: the options window, /sui opt.
--
-- Every switch the addon has, in one flat window, a tab per kind (General,
-- Ability Bar, Text & Numbers, Unit frames, Interface) along its top: click a
-- tab to show its switches. Each
-- file adds its own switch (SurvivorUI_RegisterOption, in SurvivorUI.lua), so
-- a new one shows here by itself. A click flips it just as its /sui command
-- does; hover a switch for what it does. Escape or the x closes the window;
-- drag it anywhere to move it.
--
-- An option with kind = "slider" is a number instead: min, max and step, get
-- returns it and set takes it, as the slider is dragged. One with kind =
-- "color" is a swatch opening the game's color wheel: get returns r, g, b and
-- set takes them.
--
-- An option with order = a number comes before those without one (1 first);
-- the rest keep the order they were added in.
--
-- An option with parent = another's label belongs to it: it is listed right
-- under it, indented on a thin guide line, and dimmed while the parent is off.
--
-- The window is as tall as its fullest tab, whichever tab shows, so it keeps
-- one size as you flick through; it only grows, when a new option needs room.

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local FONT = SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BUMP = SurvivorUI_FONT_BUMP or 0

local WIDTH = 540
local PAD = 14
local TITLE_HEIGHT = 34
local TAB_HEIGHT = 26
local TAB_GAP = 4
local ROW_HEIGHT = 22
local SLIDER_HEIGHT = 36
local BOX_SIZE = 14
local INDENT = 22               -- how far an option's children sit in
local RULE_GAP = 4              -- the space above and below a rule between options
local DIMMED = 0.45             -- a child's alpha while its parent is off
local TEXT_SIZE = 13            -- the switches' and sliders' names
local TAB_TEXT_SIZE = 12        -- the tabs' names, five to a row
local BUTTON_HEIGHT = 30
local FOOTER_HEIGHT = BUTTON_HEIGHT + 30   -- the hint line and the button under the options
local GOLD = { 1, 0.82, 0 }

-- Tabs in this order; one not named here comes after them.
local SECTION_ORDER = { "General", "Ability Bar", "Text & Numbers", "Unit frames", "Interface" }

------------------------------------------------------------------------------
-- The window.

local window = CreateFrame("Frame", "SurvivorUIOptions", UIParent)
window:SetWidth(WIDTH)
window:SetHeight(120)
window:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
window:SetFrameStrata("DIALOG")
window:SetBackdrop({
	bgFile = FLAT, edgeFile = FLAT, tile = false, edgeSize = 1,
	insets = { left = 1, right = 1, top = 1, bottom = 1 },
})
window:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
window:SetBackdropBorderColor(0, 0, 0, 1)
window:SetMovable(true)
if window.SetClampedToScreen then
	window:SetClampedToScreen(true)
end
window:EnableMouse(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", function() this:StartMoving() end)
window:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
window:Hide()

-- Escape closes it, as it closes the game's own windows.
table.insert(UISpecialFrames, "SurvivorUIOptions")

window.title = window:CreateFontString(nil, "OVERLAY")
window.title:SetFont(FONT, 15 + FONT_BUMP, "OUTLINE")
window.title:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -10)
window.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
window.title:SetText("Survivor UI")

-- The x in a gold-edged box, as the Reload UI button is drawn.
local close = CreateFrame("Button", nil, window)
close:SetWidth(26)
close:SetHeight(26)
close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -5)
close:SetBackdrop({
	bgFile = FLAT, edgeFile = FLAT, tile = false, edgeSize = 1,
	insets = { left = 1, right = 1, top = 1, bottom = 1 },
})
close:SetBackdropColor(0, 0, 0, 0)
close:SetBackdropBorderColor(0.62, 0.46, 0.22, 1)
close.fill = close:CreateTexture(nil, "BACKGROUND")
close.fill:SetTexture(FLAT)
close.fill:SetPoint("TOPLEFT", close, "TOPLEFT", 1, -1)
close.fill:SetPoint("BOTTOMRIGHT", close, "BOTTOMRIGHT", -1, 1)
close.fill:SetGradient("VERTICAL", 0.13, 0.03, 0.03, 0.26, 0.06, 0.05)
close.text = close:CreateFontString(nil, "OVERLAY")
close.text:SetFont(FONT, 17 + FONT_BUMP, "OUTLINE")
close.text:SetPoint("CENTER", close, "CENTER", 1, 1)
close.text:SetText("x")
close.text:SetTextColor(1, 0.84, 0.42)
close:SetScript("OnEnter", function()
	this.text:SetTextColor(1, 1, 1)
	this:SetBackdropBorderColor(1, 0.82, 0.4, 1)
end)
close:SetScript("OnLeave", function()
	this.text:SetTextColor(1, 0.84, 0.42)
	this:SetBackdropBorderColor(0.62, 0.46, 0.22, 1)
end)
close:SetScript("OnClick", function() window:Hide() end)

------------------------------------------------------------------------------
-- The footer: a standing hint on moving things, and a button that reloads the
-- interface (/sui reload), styled as the game's own menu buttons: a deep red
-- gradient, a thin gold edge, gold words.

local reload = CreateFrame("Button", nil, window)
reload:SetHeight(BUTTON_HEIGHT)
reload:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", PAD, PAD)
reload:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, PAD)
reload:SetBackdrop({
	bgFile = FLAT, edgeFile = FLAT, tile = false, edgeSize = 1,
	insets = { left = 1, right = 1, top = 1, bottom = 1 },
})
reload:SetBackdropColor(0, 0, 0, 0)
reload:SetBackdropBorderColor(0.62, 0.46, 0.22, 1)
reload.fill = reload:CreateTexture(nil, "BACKGROUND")
reload.fill:SetTexture(FLAT)
reload.fill:SetPoint("TOPLEFT", reload, "TOPLEFT", 1, -1)
reload.fill:SetPoint("BOTTOMRIGHT", reload, "BOTTOMRIGHT", -1, 1)
reload.fill:SetGradient("VERTICAL", 0.13, 0.03, 0.03, 0.26, 0.06, 0.05)
reload.text = reload:CreateFontString(nil, "OVERLAY")
reload.text:SetFont(FONT, 15 + FONT_BUMP)
reload.text:SetPoint("CENTER", reload, "CENTER", 0, 0)
reload.text:SetTextColor(1, 0.84, 0.42)
reload.text:SetShadowColor(0, 0, 0, 1)
reload.text:SetShadowOffset(1, -1)
reload.text:SetText("Reload UI")
reload:SetScript("OnEnter", function()
	this:SetBackdropBorderColor(1, 0.82, 0.35, 1)
	this.text:SetTextColor(1, 0.95, 0.7)
	GameTooltip:SetOwner(this, "ANCHOR_TOP")
	GameTooltip:SetText("Reload UI", 1, 1, 1)
	GameTooltip:AddLine("Reloads the whole interface, reading every addon's files afresh (/sui reload).", 0.7, 0.7, 0.7, 1)
	GameTooltip:Show()
end)
reload:SetScript("OnLeave", function()
	this:SetBackdropBorderColor(0.62, 0.46, 0.22, 1)
	this.text:SetTextColor(1, 0.84, 0.42)
	GameTooltip:Hide()
end)
reload:SetScript("OnClick", function() ReloadUI() end)

local hint = window:CreateFontString(nil, "OVERLAY")
hint:SetFont(FONT, 12 + FONT_BUMP)
hint:SetPoint("BOTTOM", reload, "TOP", 0, 8)
hint:SetTextColor(0.75, 0.68, 0.5)
hint:SetText("Hold ALT to edit layout")

------------------------------------------------------------------------------
-- Tabs: flat buttons side by side under the title, the open one lit with a
-- gold line under it. The open tab is kept between sessions.

local tabs = {}
local Draw

-- A closed tab's look between rest (0) and hovered (1): grey to white words,
-- the fill a shade lighter. The open tab keeps its own.
local function PaintTabHover(tab, fade)
	if tab.open then
		return
	end
	local grey = 0.6 + 0.4 * fade
	tab.text:SetTextColor(grey, grey, grey)
	local fill = 0.08 + 0.04 * fade
	tab.fill:SetVertexColor(fill, fill, fill + 0.02, 1)
end

local function OpenTab()
	SurvivorUIDB = SurvivorUIDB or {}
	return SurvivorUIDB.optionsTab
end

local function Tab(index)
	local tab = tabs[index]
	if tab then
		return tab
	end
	tab = CreateFrame("Button", nil, window)
	tab:SetHeight(TAB_HEIGHT)
	tab.fill = tab:CreateTexture(nil, "BACKGROUND")
	tab.fill:SetTexture(FLAT)
	tab.fill:SetAllPoints(tab)
	tab.mark = tab:CreateTexture(nil, "BORDER")
	tab.mark:SetTexture(FLAT)
	tab.mark:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	tab.mark:SetHeight(2)
	tab.mark:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
	tab.mark:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
	tab.text = tab:CreateFontString(nil, "OVERLAY")
	tab.text:SetFont(FONT, TAB_TEXT_SIZE + FONT_BUMP, "OUTLINE")
	tab.text:SetPoint("CENTER", tab, "CENTER", 0, 1)
	-- Hovered, a closed tab fades to white and its fill lifts a little.
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
		SurvivorUIDB = SurvivorUIDB or {}
		SurvivorUIDB.optionsTab = this.section
		Draw()
	end)
	tabs[index] = tab
	return tab
end

local function PaintTab(tab, open)
	tab.open = open
	if open then
		tab.fill:SetVertexColor(0.12, 0.12, 0.16, 1)
		tab.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		tab.mark:Show()
	else
		tab.mark:Hide()
		PaintTabHover(tab, tab.fade or 0)
	end
end

------------------------------------------------------------------------------
-- Switches and sliders, made as they are first needed and reused after.

local rows = {}

-- A thin vertical line left of an indented option, so its children read as
-- one group under their parent.
local function AddGuide(frame)
	frame.guide = frame:CreateTexture(nil, "BACKGROUND")
	frame.guide:SetTexture(FLAT)
	frame.guide:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
	frame.guide:SetWidth(1)
	frame.guide:SetPoint("TOPLEFT", frame, "TOPLEFT", -INDENT / 2, 0)
	frame.guide:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -INDENT / 2, 0)
	frame.guide:Hide()
end

-- A child option dimmed while its parent is off.
local function Dim(frame)
	if frame.parentOption and not frame.parentOption.get() then
		frame:SetAlpha(DIMMED)
	else
		frame:SetAlpha(1)
	end
end

-- A switch's look: a gold square in its box and white words when on, an
-- empty box and grey words when off.
local function Paint(row)
	if row.option.get() then
		row.mark:Show()
		row.label:SetTextColor(1, 1, 1)
	else
		row.mark:Hide()
		row.label:SetTextColor(0.55, 0.55, 0.55)
	end
	Dim(row)
end

local Refresh

local function ShowTip(owner, option)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(option.label, 1, 1, 1)
	if option.tip then
		GameTooltip:AddLine(option.tip, GOLD[1], GOLD[2], GOLD[3], 1)
	end
	if option.command then
		GameTooltip:AddLine(option.command, 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function RowEnter()
	this.hover:Show()
	ShowTip(this, this.option)
end

-- The rules between top-level options, made as needed.
local rules = {}

local function Rule(index)
	local rule = rules[index]
	if not rule then
		rule = window:CreateTexture(nil, "ARTWORK")
		rule:SetTexture(FLAT)
		rule:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
		rule:SetHeight(1)
		rules[index] = rule
	end
	return rule
end

-- Which options have their sub-options unfolded, by label, kept between
-- sessions; every group starts folded.
local function OpenGroups()
	SurvivorUIDB = SurvivorUIDB or {}
	SurvivorUIDB.optionsOpen = SurvivorUIDB.optionsOpen or {}
	return SurvivorUIDB.optionsOpen
end

local function Row(index)
	local row = rows[index]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, window)
	row:SetHeight(ROW_HEIGHT)

	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetTexture(FLAT)
	row.hover:SetVertexColor(1, 1, 1, 0.05)
	row.hover:SetAllPoints(row)
	row.hover:Hide()
	AddGuide(row)

	row.box = CreateFrame("Frame", nil, row)
	row.box:SetWidth(BOX_SIZE)
	row.box:SetHeight(BOX_SIZE)
	row.box:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.box.edge = row.box:CreateTexture(nil, "BACKGROUND")
	row.box.edge:SetTexture(FLAT)
	row.box.edge:SetVertexColor(0, 0, 0, 1)
	row.box.edge:SetPoint("TOPLEFT", row.box, "TOPLEFT", -1, 1)
	row.box.edge:SetPoint("BOTTOMRIGHT", row.box, "BOTTOMRIGHT", 1, -1)
	row.box.fill = row.box:CreateTexture(nil, "BORDER")
	row.box.fill:SetTexture(FLAT)
	row.box.fill:SetVertexColor(0.12, 0.12, 0.15, 1)
	row.box.fill:SetAllPoints(row.box)

	row.mark = row.box:CreateTexture(nil, "ARTWORK")
	row.mark:SetTexture(FLAT)
	row.mark:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	row.mark:SetPoint("TOPLEFT", row.box, "TOPLEFT", 3, -3)
	row.mark:SetPoint("BOTTOMRIGHT", row.box, "BOTTOMRIGHT", -3, 3)

	row.label = row:CreateFontString(nil, "OVERLAY")
	row.label:SetFont(FONT, TEXT_SIZE + FONT_BUMP)
	row.label:SetPoint("LEFT", row.box, "RIGHT", 9, 0)

	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", function()
		this.hover:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function()
		this.option.toggle()
		Refresh()
	end)

	-- The fold button of an option with sub-options, at its right end: a small
	-- boxed +/- as the build's. Shown only where there is something to fold.
	row.expand = CreateFrame("Button", nil, row)
	row.expand:SetWidth(16)
	row.expand:SetHeight(16)
	row.expand:SetPoint("RIGHT", row, "RIGHT", -2, 0)
	row.expand.edge = row.expand:CreateTexture(nil, "BACKGROUND")
	row.expand.edge:SetTexture(FLAT)
	row.expand.edge:SetVertexColor(0.45, 0.45, 0.5, 1)
	row.expand.edge:SetPoint("TOPLEFT", row.expand, "TOPLEFT", -1, 1)
	row.expand.edge:SetPoint("BOTTOMRIGHT", row.expand, "BOTTOMRIGHT", 1, -1)
	row.expand.fill = row.expand:CreateTexture(nil, "BORDER")
	row.expand.fill:SetTexture(FLAT)
	row.expand.fill:SetVertexColor(0.08, 0.08, 0.11, 1)
	row.expand.fill:SetAllPoints(row.expand)
	SurvivorUI_PlusMinus(row.expand, 8)
	SurvivorUI_TintPlus(row.expand, 0.75, 0.75, 0.75)
	row.expand:SetScript("OnEnter", function()
		this.edge:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
		SurvivorUI_TintPlus(this, 1, 1, 1)
	end)
	row.expand:SetScript("OnLeave", function()
		this.edge:SetVertexColor(0.45, 0.45, 0.5, 1)
		SurvivorUI_TintPlus(this, 0.75, 0.75, 0.75)
	end)
	row.expand:SetScript("OnClick", function()
		local label = this:GetParent().option.label
		local open = OpenGroups()
		open[label] = not open[label] or nil
		Draw()
	end)
	row.expand:Hide()

	rows[index] = row
	return row
end

-- A number: its name and value over a flat track with a gold thumb.
local sliders = {}

local function Slider(index)
	local holder = sliders[index]
	if holder then
		return holder
	end
	holder = CreateFrame("Frame", nil, window)
	holder:SetHeight(SLIDER_HEIGHT)
	holder:EnableMouse(true)
	holder:SetScript("OnEnter", function() ShowTip(this, this.option) end)
	holder:SetScript("OnLeave", function() GameTooltip:Hide() end)
	AddGuide(holder)

	holder.label = holder:CreateFontString(nil, "OVERLAY")
	holder.label:SetFont(FONT, TEXT_SIZE + FONT_BUMP)
	holder.label:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, -4)
	holder.label:SetTextColor(1, 1, 1)

	holder.value = holder:CreateFontString(nil, "OVERLAY")
	holder.value:SetFont(FONT, TEXT_SIZE + FONT_BUMP, "OUTLINE")
	holder.value:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -4, -4)
	holder.value:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

	local slider = CreateFrame("Slider", nil, holder)
	slider:SetOrientation("HORIZONTAL")
	slider:SetHeight(16)
	slider:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 4, 2)
	slider:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -4, 2)

	local edge = slider:CreateTexture(nil, "BACKGROUND")
	edge:SetTexture(FLAT)
	edge:SetVertexColor(0, 0, 0, 1)
	edge:SetHeight(6)
	edge:SetPoint("LEFT", slider, "LEFT", 0, 0)
	edge:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
	local track = slider:CreateTexture(nil, "BORDER")
	track:SetTexture(FLAT)
	track:SetVertexColor(0.16, 0.16, 0.2, 1)
	track:SetHeight(4)
	track:SetPoint("LEFT", edge, "LEFT", 1, 0)
	track:SetPoint("RIGHT", edge, "RIGHT", -1, 0)

	-- A flat gold thumb where the client can hand its texture back; the stock
	-- thumb where it cannot.
	slider:SetThumbTexture(FLAT)
	local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
	if thumb then
		thumb:SetWidth(9)
		thumb:SetHeight(16)
		thumb:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	else
		slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	end

	slider:SetScript("OnValueChanged", function()
		local owner = this:GetParent()
		if owner.filling or not owner.option then
			return
		end
		local value = math.floor(this:GetValue() + 0.5)
		owner.option.set(value)
		owner.value:SetText(value)
	end)
	slider:SetScript("OnEnter", function() ShowTip(this, this:GetParent().option) end)
	slider:SetScript("OnLeave", function() GameTooltip:Hide() end)

	holder.slider = slider
	sliders[index] = holder
	return holder
end

-- Its range and value from the option, without setting the option back.
local function FillSlider(holder, option)
	holder.option = option
	holder.label:SetText(option.label)
	holder.filling = true
	holder.slider:SetMinMaxValues(option.min or 0, option.max or 100)
	holder.slider:SetValueStep(option.step or 1)
	holder.slider:SetValue(option.get())
	holder.filling = nil
	holder.value:SetText(option.get())
end

-- A color: a swatch where a switch's box would be, its name beside it; a click
-- opens the game's own color wheel (ColorPickerFrame), above this window. The
-- option's get returns r, g, b; set takes them, as the wheel turns, and takes
-- the old ones back on Cancel.
local swatches = {}

local function PaintSwatch(holder)
	local r, g, b = holder.option.get()
	holder.color:SetVertexColor(r, g, b, 1)
	Dim(holder)
end

local function OpenWheel(option, holder)
	if not ColorPickerFrame then
		return
	end
	local r, g, b = option.get()
	ColorPickerFrame.hasOpacity = false
	ColorPickerFrame.previousValues = { r = r, g = g, b = b }
	ColorPickerFrame.func = function()
		local nr, ng, nb = ColorPickerFrame:GetColorRGB()
		option.set(nr, ng, nb)
		PaintSwatch(holder)
	end
	ColorPickerFrame.cancelFunc = function(previous)
		previous = previous or ColorPickerFrame.previousValues
		option.set(previous.r, previous.g, previous.b)
		PaintSwatch(holder)
	end
	ColorPickerFrame:SetColorRGB(r, g, b)
	ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
	ColorPickerFrame:Show()
end

local function Swatch(index)
	local holder = swatches[index]
	if holder then
		return holder
	end
	holder = CreateFrame("Button", nil, window)
	holder:SetHeight(ROW_HEIGHT)
	holder.hover = holder:CreateTexture(nil, "BACKGROUND")
	holder.hover:SetTexture(FLAT)
	holder.hover:SetVertexColor(1, 1, 1, 0.05)
	holder.hover:SetAllPoints(holder)
	holder.hover:Hide()
	AddGuide(holder)

	holder.box = CreateFrame("Frame", nil, holder)
	holder.box:SetWidth(BOX_SIZE)
	holder.box:SetHeight(BOX_SIZE)
	holder.box:SetPoint("LEFT", holder, "LEFT", 4, 0)
	holder.box.edge = holder.box:CreateTexture(nil, "BACKGROUND")
	holder.box.edge:SetTexture(FLAT)
	holder.box.edge:SetVertexColor(0, 0, 0, 1)
	holder.box.edge:SetPoint("TOPLEFT", holder.box, "TOPLEFT", -1, 1)
	holder.box.edge:SetPoint("BOTTOMRIGHT", holder.box, "BOTTOMRIGHT", 1, -1)
	holder.color = holder.box:CreateTexture(nil, "ARTWORK")
	holder.color:SetTexture(FLAT)
	holder.color:SetAllPoints(holder.box)

	holder.label = holder:CreateFontString(nil, "OVERLAY")
	holder.label:SetFont(FONT, TEXT_SIZE + FONT_BUMP)
	holder.label:SetPoint("LEFT", holder.box, "RIGHT", 9, 0)
	holder.label:SetTextColor(1, 1, 1)

	holder:SetScript("OnEnter", function()
		this.hover:Show()
		ShowTip(this, this.option)
	end)
	holder:SetScript("OnLeave", function()
		this.hover:Hide()
		GameTooltip:Hide()
	end)
	holder:SetScript("OnClick", function()
		GameTooltip:Hide()
		OpenWheel(this.option, this)
	end)
	swatches[index] = holder
	return holder
end

------------------------------------------------------------------------------
-- Laying it out: the tabs, the open tab's options, the window sized to the
-- fullest tab.

local shownRows, shownSliders, shownSwatches = 0, 0, 0
local tallest = 0               -- the most room any tab has needed, kept

-- A section's options in the order they show: each parent followed by its
-- children. A child whose parent is not in the section stands on its own.
local function Nest(list)
	local byLabel, children = {}, {}
	for index = 1, table.getn(list) do
		byLabel[list[index].label] = list[index]
	end
	for index = 1, table.getn(list) do
		local option = list[index]
		if option.parent and byLabel[option.parent] then
			children[option.parent] = children[option.parent] or {}
			table.insert(children[option.parent], option)
		end
	end
	local out = {}
	for index = 1, table.getn(list) do
		local option = list[index]
		if not (option.parent and byLabel[option.parent]) then
			table.insert(out, { option = option })
			local kids = children[option.label] or {}
			for kid = 1, table.getn(kids) do
				table.insert(out, { option = kids[kid], parent = option })
			end
		end
	end
	return out
end

local function Sections()
	local options = SurvivorUI_OPTIONS or {}
	local bySection, order = {}, {}
	for index = 1, table.getn(SECTION_ORDER) do
		bySection[SECTION_ORDER[index]] = {}
	end
	for index = 1, table.getn(options) do
		local option = options[index]
		local name = option.section or "Other"
		if not bySection[name] then
			bySection[name] = {}
		end
		table.insert(bySection[name], option)
	end
	-- Options with an order first, by it; the rest as they were added.
	for _, list in pairs(bySection) do
		for index = 1, table.getn(list) do
			list[index].added = list[index].added or index
		end
		table.sort(list, function(a, b)
			local ao, bo = a.order or 1000, b.order or 1000
			if ao ~= bo then
				return ao < bo
			end
			return a.added < b.added
		end)
	end
	for index = 1, table.getn(SECTION_ORDER) do
		if table.getn(bySection[SECTION_ORDER[index]]) > 0 then
			table.insert(order, SECTION_ORDER[index])
		end
	end
	for name, list in pairs(bySection) do
		local known = false
		for index = 1, table.getn(SECTION_ORDER) do
			if SECTION_ORDER[index] == name then
				known = true
			end
		end
		if not known and table.getn(list) > 0 then
			table.insert(order, name)
		end
	end
	return bySection, order
end

-- The room one tab's options take.
local function Height(list)
	local height, groups = 0, 0
	for _, entry in ipairs(Nest(list)) do
		height = height + (entry.option.kind == "slider" and SLIDER_HEIGHT or ROW_HEIGHT)
		if not entry.parent then
			groups = groups + 1
		end
	end
	-- The rules between the groups, with their space.
	return height + math.max(0, groups - 1) * 2 * RULE_GAP
end

-- A row or slider at its place: a child sits in by INDENT, on its guide line.
local function Seat(frame, y, parent)
	local indent = parent and INDENT or 0
	frame.parentOption = parent
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", window, "TOPLEFT", PAD + indent, y)
	frame:SetWidth(WIDTH - 2 * PAD - indent)
	if parent then
		frame.guide:Show()
	else
		frame.guide:Hide()
	end
	frame:Show()
end

Draw = function()
	local bySection, order = Sections()
	local open = OpenTab()
	if not bySection[open] or table.getn(bySection[open]) == 0 then
		open = order[1]
	end

	-- The tabs, sharing the width.
	local count = table.getn(order)
	local tabWidth = (WIDTH - 2 * PAD - (count - 1) * TAB_GAP) / math.max(1, count)
	for index = 1, count do
		local tab = Tab(index)
		tab.section = order[index]
		tab:SetWidth(tabWidth)
		tab:ClearAllPoints()
		tab:SetPoint("TOPLEFT", window, "TOPLEFT", PAD + (index - 1) * (tabWidth + TAB_GAP), -TITLE_HEIGHT)
		tab.text:SetText(order[index])
		PaintTab(tab, order[index] == open)
		tab:Show()
	end
	for index = count + 1, table.getn(tabs) do
		tabs[index]:Hide()
	end

	-- The open tab's options.
	local top = -TITLE_HEIGHT - TAB_HEIGHT - 10
	local y = top
	local rowCount, sliderCount, swatchCount = 0, 0, 0
	local entries = Nest(bySection[open] or {})
	local hasChildren = {}
	for _, entry in ipairs(entries) do
		if entry.parent then
			hasChildren[entry.parent.label] = true
		end
	end
	local unfolded = OpenGroups()
	local ruleCount = 0
	for _, entry in ipairs(entries) do
		local option = entry.option
		-- A thin rule over each top-level option but the first, so an option,
		-- its fold button and its sub-options read as one group.
		if not entry.parent and y ~= top then
			y = y - RULE_GAP
			ruleCount = ruleCount + 1
			local rule = Rule(ruleCount)
			rule:ClearAllPoints()
			rule:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, y)
			rule:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD, y)
			rule:Show()
			y = y - RULE_GAP
		end
		-- A folded group's sub-options stay out of sight.
		if entry.parent and not unfolded[entry.parent.label] then
			-- folded away
		elseif option.kind == "color" then
			swatchCount = swatchCount + 1
			local holder = Swatch(swatchCount)
			holder.option = option
			Seat(holder, y, entry.parent)
			holder.label:SetText(option.label)
			PaintSwatch(holder)
			y = y - ROW_HEIGHT
		elseif option.kind == "slider" then
			sliderCount = sliderCount + 1
			local holder = Slider(sliderCount)
			Seat(holder, y, entry.parent)
			FillSlider(holder, option)
			Dim(holder)
			y = y - SLIDER_HEIGHT
		else
			rowCount = rowCount + 1
			local row = Row(rowCount)
			row.option = option
			Seat(row, y, entry.parent)
			row.label:SetText(option.label)
			Paint(row)
			if hasChildren[option.label] then
				SurvivorUI_SetPlus(row.expand, not unfolded[option.label])
				row.expand:Show()
			else
				row.expand:Hide()
			end
			y = y - ROW_HEIGHT
		end
	end
	for index = rowCount + 1, table.getn(rows) do
		rows[index]:Hide()
	end
	for index = sliderCount + 1, table.getn(sliders) do
		sliders[index]:Hide()
	end
	for index = ruleCount + 1, table.getn(rules) do
		rules[index]:Hide()
	end
	for index = swatchCount + 1, table.getn(swatches) do
		swatches[index]:Hide()
	end
	shownRows, shownSliders, shownSwatches = rowCount, sliderCount, swatchCount

	-- As tall as the fullest tab, and never shorter than it has been.
	for _, name in ipairs(order) do
		tallest = math.max(tallest, Height(bySection[name]))
	end
	window:SetHeight(-top + tallest + 8 + FOOTER_HEIGHT + PAD)
end

-- Every switch painted again, and every child dimmed or not: one can change
-- another's state, and a /sui command typed while the window is open does too.
Refresh = function()
	for index = 1, shownRows do
		Paint(rows[index])
	end
	for index = 1, shownSliders do
		Dim(sliders[index])
	end
	for index = 1, shownSwatches do
		PaintSwatch(swatches[index])
	end
end

local elapsed = 0
window:SetScript("OnUpdate", function()
	elapsed = elapsed + arg1
	if elapsed >= 0.25 then
		elapsed = 0
		Refresh()
	end
end)

function SurvivorUI_ToggleOptions()
	if window:IsShown() then
		window:Hide()
	else
		Draw()
		window:Show()
	end
end

------------------------------------------------------------------------------
-- A round button by the minimap, "UI" on it: a click opens or closes this
-- window. The game's own round minimap ring around a dark middle; it follows
-- the minimap wherever it is moved. Drag it to slide it along the minimap's
-- edge (the minimap is square, so a square path EDGE_OUT pixels outside its
-- border); where it sits is kept as an angle from the minimap's middle. It
-- starts by the bottom left corner. A switch in the window hides it.

local function ButtonShown()
	SurvivorUIDB = SurvivorUIDB or {}
	return SurvivorUIDB.minimapButton ~= false
end

local mapButton
if Minimap then
	mapButton = CreateFrame("Button", "SurvivorUIMinimapButton", Minimap)
	mapButton:SetWidth(31)
	mapButton:SetHeight(31)
	-- Above the minimap and the panels around it, so nothing covers it.
	mapButton:SetFrameStrata("HIGH")
	mapButton:SetFrameLevel(Minimap:GetFrameLevel() + 8)

	-- The ring's art sits in the top left of its square, its middle at 17, -15.
	mapButton.fill = mapButton:CreateTexture(nil, "BACKGROUND")
	mapButton.fill:SetTexture(FLAT)
	mapButton.fill:SetVertexColor(0.05, 0.05, 0.07, 0.95)
	mapButton.fill:SetWidth(15)
	mapButton.fill:SetHeight(15)
	mapButton.fill:SetPoint("CENTER", mapButton, "TOPLEFT", 17, -15)

	mapButton.ring = mapButton:CreateTexture(nil, "OVERLAY")
	mapButton.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	mapButton.ring:SetWidth(53)
	mapButton.ring:SetHeight(53)
	mapButton.ring:SetPoint("TOPLEFT", mapButton, "TOPLEFT", 0, 0)

	mapButton.text = mapButton:CreateFontString(nil, "OVERLAY")
	mapButton.text:SetFont(FONT, 9 + FONT_BUMP, "OUTLINE")
	mapButton.text:SetPoint("CENTER", mapButton, "TOPLEFT", 17, -15)
	mapButton.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	mapButton.text:SetText("UI")

	mapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	-- Its place on the square path around the minimap: the angle from the
	-- minimap's middle (degrees, 0 east, counterclockwise), the path EDGE_OUT
	-- pixels outside the border. The ring's art is drawn a little off its
	-- frame's middle (17, -15 in a 31 square), which RING_X, RING_Y make up.
	local EDGE_OUT = 10
	local RING_X, RING_Y = 1.5, 0.5

	-- With no angle kept yet, where it has always stood: EDGE_OUT left of the
	-- minimap's left edge and EDGE_OUT above its bottom.
	local function ButtonAngle()
		SurvivorUIDB = SurvivorUIDB or {}
		if SurvivorUIDB.minimapAngle then
			return SurvivorUIDB.minimapAngle
		end
		local half = Minimap:GetWidth() / 2
		return math.deg(math.atan2(-(half - EDGE_OUT), -(half + EDGE_OUT)))
	end

	local function PlaceButton()
		local angle = math.rad(ButtonAngle())
		local c, s = math.cos(angle), math.sin(angle)
		local halfX = Minimap:GetWidth() / 2 + EDGE_OUT
		local halfY = Minimap:GetHeight() / 2 + EDGE_OUT
		-- Out from the middle along the angle until it meets the square path.
		local reach = math.min(halfX / math.max(math.abs(c), 0.0001), halfY / math.max(math.abs(s), 0.0001))
		mapButton:ClearAllPoints()
		mapButton:SetPoint("CENTER", Minimap, "CENTER", c * reach - RING_X, s * reach - RING_Y)
	end

	-- Dragged, it follows the cursor's angle around the minimap's middle.
	mapButton:RegisterForDrag("LeftButton")
	mapButton:SetScript("OnDragStart", function()
		this.dragging = true
		this.dragged = true
		GameTooltip:Hide()
	end)
	mapButton:SetScript("OnDragStop", function()
		this.dragging = nil
	end)
	mapButton:SetScript("OnUpdate", function()
		if not this.dragging then
			return
		end
		local scale = Minimap:GetEffectiveScale()
		local x, y = GetCursorPosition()
		local mx, my = Minimap:GetCenter()
		SurvivorUIDB = SurvivorUIDB or {}
		SurvivorUIDB.minimapAngle = math.deg(math.atan2(y / scale - my, x / scale - mx))
		PlaceButton()
	end)
	PlaceButton()

	mapButton:RegisterForClicks("LeftButtonUp")
	mapButton:SetScript("OnClick", function()
		-- The release that ends a drag is no click.
		if this.dragged then
			this.dragged = nil
			return
		end
		SurvivorUI_ToggleOptions()
	end)
	mapButton:SetScript("OnEnter", function()
		this.text:SetTextColor(1, 1, 1)
		GameTooltip:SetOwner(this, "ANCHOR_LEFT")
		GameTooltip:SetText("Survivor UI", GOLD[1], GOLD[2], GOLD[3])
		GameTooltip:AddLine("Click to open the options (/sui opt).", 1, 1, 1)
		GameTooltip:AddLine("Drag to move it along the minimap's edge.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	mapButton:SetScript("OnLeave", function()
		this.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		GameTooltip:Hide()
	end)

	local function ApplyButton()
		PlaceButton()
		if ButtonShown() then
			mapButton:Show()
		else
			mapButton:Hide()
		end
	end

	local loader = CreateFrame("Frame")
	loader:RegisterEvent("PLAYER_ENTERING_WORLD")
	loader:SetScript("OnEvent", ApplyButton)

	SurvivorUI_RegisterOption({
		section = "Interface",
		label = "Minimap button",
		tip = "The round \"UI\" button by the minimap that opens this window. Off, /sui opt still does.",
		get = ButtonShown,
		toggle = function()
			SurvivorUIDB = SurvivorUIDB or {}
			SurvivorUIDB.minimapButton = not ButtonShown()
			ApplyButton()
		end,
	})
end
