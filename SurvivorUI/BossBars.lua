-- Survivor UI: boss bars.
--
-- A column of flat bars at the top of the screen, one for every boss alive,
-- the final boss on top, then every lair guardian that is awake (and, on
-- request, every elite). Each shows the whole name on the left and the health
-- left on the right, in the color of its kind; an enraged boss's name turns red. The game sends these to
-- addons for the whole map, so a bar stays live at any distance, unlike a
-- nameplate.
--
-- Right of each bar, its debuffs (AZS_GetDebuffs): icon, stacks and the time
-- left, a card on hover; switched with "Debuffs on the boss bars".
--
-- Click a bar to target that enemy. In edit mode (tap Alt), drag a bar to move the column.
-- The game's own boss bars are put away while these are on, and come back with
-- /sui bosses. Needs the game's addon API (AZS_UNITS); without it nothing shows.

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local FONT = SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BUMP = SurvivorUI_FONT_BUMP or 0

local BAR_WIDTH = 220
local BAR_HEIGHT = 18
local BAR_GAP = 4
local MAX_BARS = 8

local KINDS = {
	final    = { order = 1, color = { 0.95, 0.25, 0.55 }, tag = "Final" },
	boss     = { order = 2, color = { 0.72, 0.32, 1.00 } },
	guardian = { order = 3, color = { 0.20, 0.75, 0.95 }, tag = "Guardian" },
	elite    = { order = 4, color = { 1.00, 0.55, 0.10 } },
}

local MAX_DEBUFFS = 8
local DEBUFF_GAP = 2

local function Settings()
	SurvivorUIDB = SurvivorUIDB or {}
	if SurvivorUIDB.bossBars == nil then
		SurvivorUIDB.bossBars = true
	end
	if SurvivorUIDB.bossDebuffs == nil then
		SurvivorUIDB.bossDebuffs = true
	end
	return SurvivorUIDB
end

local function Field(entry, name, index)
	if entry[name] ~= nil then
		return entry[name]
	end
	return entry[index]
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

local function Playing()
	if not (AZS_GetPhase and AZS_UNITS) then
		return false
	end
	local phase = AZS_GetPhase()
	return phase == "playing" or phase == "choosing" or phase == "paused"
end

------------------------------------------------------------------------------
-- The column.

local holder = CreateFrame("Frame", "SurvivorUIBosses", UIParent)
holder:SetWidth(BAR_WIDTH)
-- Room for four bars: the area edit mode outlines, though only the bars show.
holder:SetHeight(4 * (BAR_HEIGHT + BAR_GAP))
holder:SetPoint("TOP", UIParent, "TOP", 0, -90)
holder:SetMovable(true)

local function SavePlace()
	local settings = Settings()
	settings.bossLeft = math.floor(holder:GetLeft() + 0.5)
	settings.bossTop = math.floor(holder:GetTop() + 0.5)
end

local function RestorePlace()
	local settings = Settings()
	if settings.bossLeft then
		holder:ClearAllPoints()
		holder:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", settings.bossLeft, settings.bossTop)
	end
end

local bars = {}

-- 4.2, 12, 1:05
local function TimeLeft(seconds)
	if seconds >= 60 then
		return string.format("%d:%02d", math.floor(seconds / 60), math.mod(math.floor(seconds), 60))
	elseif seconds >= 10 then
		return math.floor(seconds + 0.5)
	end
	return string.format("%.1f", seconds)
end

-- An icon the game names bare ("Spell_Shadow_Curse") lives in Interface\Icons.
local function IconPath(icon)
	if not icon or icon == "" then
		return "Interface\\Icons\\INV_Misc_QuestionMark"
	end
	if string.find(icon, "\\", 1, true) then
		return icon
	end
	return "Interface\\Icons\\"..icon
end

-- A debuff's square on a bar: its icon in an edge of its dispel type's color
-- (black for none), its stacks in the corner, its time left under it.
local function DebuffIcon(bar, index)
	local icon = bar.debuffs[index]
	if icon then
		return icon
	end
	icon = CreateFrame("Button", nil, bar)
	icon:SetWidth(BAR_HEIGHT)
	icon:SetHeight(BAR_HEIGHT)
	icon:SetPoint("LEFT", bar, "RIGHT", 4 + (index - 1) * (BAR_HEIGHT + DEBUFF_GAP), 0)
	icon.edge = icon:CreateTexture(nil, "BACKGROUND")
	icon.edge:SetTexture(FLAT)
	icon.edge:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
	icon.edge:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetAllPoints(icon)
	icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon.stacks = icon:CreateFontString(nil, "OVERLAY")
	icon.stacks:SetFont(FONT, 8 + FONT_BUMP, "OUTLINE")
	icon.stacks:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, 0)
	icon.stacks:SetTextColor(1, 1, 1)
	icon.time = icon:CreateFontString(nil, "OVERLAY")
	icon.time:SetFont(FONT, 8 + FONT_BUMP, "OUTLINE")
	icon.time:SetPoint("TOP", icon, "BOTTOM", 0, -1)
	icon.time:SetTextColor(1, 0.82, 0)
	icon:SetScript("OnEnter", function()
		local debuff = this.debuff
		if not debuff then
			return
		end
		GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText(debuff.name or "?", 1, 0.3, 0.3)
		if debuff.dispelType then
			GameTooltip:AddLine(debuff.dispelType, 0.7, 0.7, 0.7)
		end
		if (tonumber(debuff.stacks) or 0) > 1 then
			GameTooltip:AddDoubleLine("Stacks", debuff.stacks, 0.7, 0.7, 0.7, 1, 1, 1)
		end
		if debuff.permanent then
			GameTooltip:AddLine("Lasts until it dies", 0.7, 0.7, 0.7)
		elseif debuff.remaining then
			GameTooltip:AddDoubleLine("Time left", TimeLeft(debuff.remaining).." sec", 0.7, 0.7, 0.7, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	bar.debuffs[index] = icon
	return icon
end

local function FillDebuffs(bar, id)
	local list = {}
	if Settings().bossDebuffs and id and AZS_GetDebuffs then
		list = AZS_GetDebuffs(tonumber(id) or id) or {}
	end
	local count = math.min(MAX_DEBUFFS, table.getn(list))
	for index = 1, count do
		local debuff = list[index]
		local icon = DebuffIcon(bar, index)
		icon.debuff = debuff
		icon.texture:SetTexture(IconPath(debuff.icon))
		local color = debuff.dispelType and DebuffTypeColor and DebuffTypeColor[debuff.dispelType]
		if color then
			icon.edge:SetVertexColor(color.r, color.g, color.b, 1)
		else
			icon.edge:SetVertexColor(0, 0, 0, 1)
		end
		local stacks = tonumber(debuff.stacks) or 0
		icon.stacks:SetText(stacks > 1 and stacks or "")
		icon.time:SetText((not debuff.permanent and debuff.remaining) and TimeLeft(debuff.remaining) or "")
		icon:Show()
	end
	for index = count + 1, table.getn(bar.debuffs) do
		bar.debuffs[index]:Hide()
		bar.debuffs[index].debuff = nil
	end
end

local function Bar(index)
	local bar = bars[index]
	if bar then
		return bar
	end

	bar = CreateFrame("Button", nil, holder)
	bar:SetWidth(BAR_WIDTH)
	bar:SetHeight(BAR_HEIGHT)
	bar:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(index - 1) * (BAR_HEIGHT + BAR_GAP))
	bar.debuffs = {}

	bar.border = bar:CreateTexture(nil, "BACKGROUND")
	bar.border:SetTexture(FLAT)
	bar.border:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
	bar.border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)

	bar.backing = bar:CreateTexture(nil, "BORDER")
	bar.backing:SetTexture(FLAT)
	bar.backing:SetVertexColor(0.08, 0.08, 0.10, 0.92)
	bar.backing:SetAllPoints(bar)

	bar.health = CreateFrame("StatusBar", nil, bar)
	bar.health:SetAllPoints(bar)
	bar.health:SetStatusBarTexture(FLAT)
	bar.health:SetMinMaxValues(0, 1)

	bar.name = bar.health:CreateFontString(nil, "OVERLAY")
	bar.name:SetFont(FONT, 10 + FONT_BUMP, "OUTLINE")
	bar.name:SetPoint("LEFT", bar, "LEFT", 5, 0)
	bar.name:SetWidth(BAR_WIDTH - 50)
	bar.name:SetHeight(12)
	bar.name:SetJustifyH("LEFT")
	bar.name:SetTextColor(1, 1, 1)

	-- A boss's skull, the game's own, just left of the bar; elites and
	-- guardians go without (the game has no small elite mark to show).
	bar.skull = bar:CreateTexture(nil, "OVERLAY")
	bar.skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
	bar.skull:SetWidth(BAR_HEIGHT)
	bar.skull:SetHeight(BAR_HEIGHT)
	bar.skull:SetPoint("RIGHT", bar, "LEFT", -3, 0)
	bar.skull:Hide()

	bar.value = bar.health:CreateFontString(nil, "OVERLAY")
	bar.value:SetFont(FONT, 10 + FONT_BUMP, "OUTLINE")
	bar.value:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
	bar.value:SetTextColor(1, 1, 1)

	bar:RegisterForClicks("LeftButtonUp")
	bar:SetScript("OnClick", function()
		if this.unitName and TargetByName then
			TargetByName(this.unitName, true)
		end
	end)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function()
		if SurvivorUI_EditMode and SurvivorUI_EditMode() then
			holder:StartMoving()
		end
	end)
	bar:SetScript("OnDragStop", function()
		holder:StopMovingOrSizing()
		SavePlace()
	end)
	bar:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_LEFT")
		GameTooltip:SetText(this.unitName or "", 1, 1, 1)
		if this.kindLabel then
			GameTooltip:AddLine(this.kindLabel, this.color[1], this.color[2], this.color[3])
		end
		GameTooltip:AddDoubleLine("Health", (this.hp or 0).." / "..(this.hpm or 0), 0.7, 0.7, 0.7, 1, 1, 1)
		GameTooltip:AddLine("Click to target. In edit mode (tap Alt), drag to move.", 0.7, 0.7, 0.7, 1)
		GameTooltip:Show()
	end)
	bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

	bars[index] = bar
	return bar
end

local KIND_LABELS = { final = "Final boss", boss = "Boss", guardian = "Lair guardian", elite = "Elite" }

local function Fill(bar, unit)
	local kind = Field(unit, "kind", 1) or "elite"
	local style = KINDS[kind] or KINDS.elite
	local name = Field(unit, "name", 3) or "?"
	local hp = tonumber(Field(unit, "hp", 4)) or 0
	local hpm = tonumber(Field(unit, "hpm", 5)) or 0
	local state = tonumber(Field(unit, "state", 6)) or 0
	local share = hpm > 0 and hp / hpm or 0

	bar.unitName, bar.hp, bar.hpm = name, hp, hpm
	bar.color = style.color
	bar.kindLabel = KIND_LABELS[kind]
	bar.health:SetStatusBarColor(style.color[1], style.color[2], style.color[3], 0.9)
	bar.health:SetValue(share)

	-- An enraged boss (state 1) wears its name in red.
	bar.name:SetText(name)
	if state == 1 and (kind == "boss" or kind == "final") then
		bar.name:SetTextColor(1, 0.35, 0.35)
	else
		bar.name:SetTextColor(1, 1, 1)
	end
	bar.value:SetText(math.floor(share * 100 + 0.5).."%")
	if kind == "boss" or kind == "final" then
		bar.skull:Show()
	else
		bar.skull:Hide()
	end

	-- The target wears a white border.
	if UnitExists("target") and UnitName("target") == name then
		bar.border:SetVertexColor(1, 1, 1, 1)
	else
		bar.border:SetVertexColor(0, 0, 0, 1)
	end
	FillDebuffs(bar, Field(unit, "id", 2))
	bar:Show()
end

local function Wanted(unit, elites)
	local kind = Field(unit, "kind", 1)
	if kind == "final" or kind == "boss" then
		return true
	elseif kind == "guardian" then
		-- A guardian asleep in its lair is not a fight yet.
		return (tonumber(Field(unit, "state", 6)) or 0) == 1
	end
	return elites and kind == "elite"
end

local function Update()
	local settings = Settings()
	local shown = 0
	if settings.bossBars and Playing() then
		local picked = {}
		for index = 1, table.getn(AZS_UNITS) do
			local unit = AZS_UNITS[index]
			if Wanted(unit, settings.bossBarsElites) then
				table.insert(picked, unit)
			end
		end
		table.sort(picked, function(a, b)
			local ka = KINDS[Field(a, "kind", 1)] or KINDS.elite
			local kb = KINDS[Field(b, "kind", 1)] or KINDS.elite
			return ka.order < kb.order
		end)
		for index = 1, math.min(MAX_BARS, table.getn(picked)) do
			Fill(Bar(index), picked[index])
			shown = index
		end
	end
	-- In preview (before the first step, or in edit mode), with no boss up, a
	-- sample bar stands in so the column can be placed.
	if settings.bossBars and shown == 0 and SurvivorUI_Preview and SurvivorUI_Preview() then
		Fill(Bar(1), { kind = "boss", name = "Boss bars", hp = 1, hpm = 1, state = 0 })
		shown = 1
	end
	for index = shown + 1, table.getn(bars) do
		bars[index]:Hide()
		bars[index].unitName = nil
	end
end

local elapsed = 0
holder:SetScript("OnUpdate", function()
	elapsed = elapsed + arg1
	if elapsed >= 0.1 then
		elapsed = 0
		Update()
	end
end)

------------------------------------------------------------------------------
-- The game's own boss bars: away while these are on. The setting is the game's
-- and is saved, so the addon remembers that it was the one to turn it off.

local function ApplyGameHud()
	if not (AZS_SetHudShown and AZS_IsHudShown) then
		return
	end
	local settings = Settings()
	if settings.bossBars then
		if AZS_IsHudShown("bosses") then
			AZS_SetHudShown("bosses", false)
			settings.hidGameBosses = true
		end
	elseif settings.hidGameBosses then
		AZS_SetHudShown("bosses", true)
		settings.hidGameBosses = nil
	end
end

function SurvivorUI_BossBars(argument)
	local settings = Settings()
	if argument == "elites" then
		settings.bossBarsElites = not settings.bossBarsElites
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: boss bars "..(settings.bossBarsElites and "list elites too." or "leave elites out."))
	else
		settings.bossBars = not settings.bossBars
		ApplyGameHud()
		DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: "..(settings.bossBars and "boss bars on; the game's own are put away." or "boss bars off; the game's own are back."))
	end
	Update()
end

if SurvivorUI_RegisterOption then
	SurvivorUI_RegisterOption({
		section = "General",
		label = "Boss bars",
		tip = "A bar at the top of the screen for every boss alive and every lair guardian awake, in place of the game's own.",
		command = "/sui bosses",
		get = function() return Settings().bossBars end,
		toggle = function() SurvivorUI_BossBars() end,
	})
	SurvivorUI_RegisterOption({
		section = "General",
		label = "Elites on the boss bars",
		parent = "Boss bars",
		tip = "The boss bars list every elite too.",
		command = "/sui bosses elites",
		get = function() return Settings().bossBarsElites end,
		toggle = function() SurvivorUI_BossBars("elites") end,
	})
	SurvivorUI_RegisterOption({
		section = "General",
		label = "Debuffs on the boss bars",
		parent = "Boss bars",
		tip = "Right of each boss and guardian bar, the debuffs on it: stacks, time left, and its dispel type's color around it.",
		get = function() return Settings().bossDebuffs end,
		toggle = function()
			local settings = Settings()
			settings.bossDebuffs = not settings.bossDebuffs
			Update()
		end,
	})
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function()
	RestorePlace()
	ApplyGameHud()
end)

if SurvivorUI_RegisterMover then
	SurvivorUI_RegisterMover(holder, "Boss bars", SavePlace, nil, function()
		holder:ClearAllPoints()
		holder:SetPoint("TOP", UIParent, "TOP", 0, -90)
	end)
end

------------------------------------------------------------------------------
-- Important nameplates only: with the switch on, an enemy's nameplate shows
-- only for a boss, a lair guardian or an elite, told by name against the
-- game's list of them (AZS_UNITS: the whole map's, asleep or awake). Every
-- other plate is put away as it comes into view; switched off, the game's
-- plates are set out afresh. The game's own "Enemy Name Plates" must be on.

local function Plates()
	local found = {}
	if SurvivorPlatesRegistry then
		for index = 1, table.getn(SurvivorPlatesRegistry) do
			local overlay = SurvivorPlatesRegistry[index]
			if overlay.plate and overlay.stock and overlay.stock.name then
				table.insert(found, { plate = overlay.plate, name = overlay.stock.name })
			end
		end
		return found
	end
	local children = { WorldFrame:GetChildren() }
	for index = 1, table.getn(children) do
		local plate = children[index]
		local border = plate:GetRegions()
		if border and border.GetObjectType and border:GetObjectType() == "Texture"
			and border:GetTexture() == "Interface\\Tooltips\\Nameplate-Border" then
			local regions = { plate:GetRegions() }
			for region = 1, table.getn(regions) do
				if regions[region]:GetObjectType() == "FontString" then
					table.insert(found, { plate = plate, name = regions[region] })
					break
				end
			end
		end
	end
	return found
end

local function ImportantNames()
	local names = {}
	for index = 1, table.getn(AZS_UNITS or {}) do
		local name = Field(AZS_UNITS[index], "name", 3)
		if name then
			names[name] = true
		end
	end
	return names
end

local RECHECK = 2               -- seconds a plate put away may still come back
local putAway = {}              -- [plate] = { name, at }
local plateElapsed = 0
local plateWatch = CreateFrame("Frame")
plateWatch:SetScript("OnUpdate", function()
	plateElapsed = plateElapsed + arg1
	if plateElapsed < 0.1 then
		return
	end
	plateElapsed = 0
	if not (Settings().importantPlates and AZS_UNITS) then
		return
	end
	local names = ImportantNames()
	local now = GetTime()
	-- The game's list can name a new elite a moment after its plate shows: a
	-- plate put away lately comes back once its name is on the list.
	for plate, put in pairs(putAway) do
		if now - put.at > RECHECK then
			putAway[plate] = nil
		elseif names[put.name] then
			putAway[plate] = nil
			plate:Show()
		end
	end
	local plates = Plates()
	for index = 1, table.getn(plates) do
		local plate = plates[index].plate
		local name = plates[index].name:GetText() or ""
		if plate:IsVisible() and not names[name] then
			plate:Hide()
			putAway[plate] = { name = name, at = now }
		end
	end
end)

if SurvivorUI_RegisterOption then
	SurvivorUI_RegisterOption({
		section = "General",
		label = "Important nameplates only",
		tip = "Enemy nameplates only on bosses, lair guardians and elites; the rest are put away. Needs the game's Enemy Name Plates on. A plain enemy that shares an elite's name keeps its plate too.",
		get = function() return Settings().importantPlates end,
		toggle = function()
			local settings = Settings()
			settings.importantPlates = not settings.importantPlates
			-- Off, the plates put away come back: the game sets them all out again.
			if not settings.importantPlates and HideNameplates and ShowNameplates then
				HideNameplates()
				ShowNameplates()
			end
		end,
	})
end
