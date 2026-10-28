-- Survivor UI: talent timers.
--
-- The clocks the run's talents and jewelry keep (AZS_GetTimers): a proc's, a
-- heal's or a second life's wait, the next demon or Legion Gate wave; waits
-- shorter than MIN_WAIT are left out. A row of their icons just above the
-- buffs, at the buffs' size and growing from the middle as they do, so it
-- follows them wherever they are moved. Each is dimmed while it waits, a
-- shade over it shrinking away and the seconds left on it; bright with a gold
-- edge once it may go. A card on hover names it. Needs the game's addon API;
-- without it nothing shows.

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local FONT = SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BUMP = SurvivorUI_FONT_BUMP or 0

local MAX_TIMERS = 10
-- Placeholder: a clock whose whole wait is shorter than this (Nightfall's half
-- second between procs) only flickers, so it is left out.
local MIN_WAIT = 5
local READY = { 1, 0.82, 0 }
local WAITING = { 0, 0, 0 }

local function Settings()
	SurvivorUIDB = SurvivorUIDB or {}
	if SurvivorUIDB.timers == nil then
		SurvivorUIDB.timers = true
	end
	return SurvivorUIDB
end

-- The buffs' icon size and gap, so the two rows line up.
local function Size()
	if SurvivorUI_AuraSize then
		return SurvivorUI_AuraSize()
	end
	return 22, 3
end

local function Playing()
	if not (AZS_GetPhase and AZS_GetTimers) then
		return false
	end
	local phase = AZS_GetPhase()
	return phase == "playing" or phase == "choosing" or phase == "paused"
end

-- 4.2, 12, 1:05
local function TimeLeft(seconds)
	if seconds >= 60 then
		return string.format("%d:%02d", math.floor(seconds / 60), math.mod(math.floor(seconds), 60))
	elseif seconds >= 10 then
		return math.floor(seconds + 0.5)
	end
	return string.format("%.1f", seconds)
end

local function IconPath(icon)
	if not icon or icon == "" then
		return "Interface\\Icons\\INV_Misc_QuestionMark"
	end
	if string.find(icon, "\\", 1, true) then
		return icon
	end
	return "Interface\\Icons\\"..icon
end

------------------------------------------------------------------------------
-- The row, on top of the buffs' row.

local holder = CreateFrame("Frame", "SurvivorUITimers", UIParent)
holder:SetWidth(1)
holder:SetHeight(22)

local function Seat()
	local buffs = SurvivorUIBuffs
	local _, gap = Size()
	holder:ClearAllPoints()
	if buffs then
		holder:SetPoint("BOTTOM", buffs, "TOP", 0, gap)
	else
		holder:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
	end
end
Seat()

local icons = {}

local function Icon(index)
	local icon = icons[index]
	if icon then
		return icon
	end
	icon = CreateFrame("Button", nil, holder)
	icon.edge = icon:CreateTexture(nil, "BACKGROUND")
	icon.edge:SetTexture(FLAT)
	icon.edge:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
	icon.edge:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
	icon.texture = icon:CreateTexture(nil, "BORDER")
	icon.texture:SetAllPoints(icon)
	icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- The wait still to go, as a shade over the top of the icon that shrinks
	-- away as the clock runs down.
	icon.shade = icon:CreateTexture(nil, "ARTWORK")
	icon.shade:SetTexture(FLAT)
	icon.shade:SetVertexColor(0, 0, 0, 0.65)
	icon.shade:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
	icon.shade:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
	icon.time = icon:CreateFontString(nil, "OVERLAY")
	icon.time:SetPoint("CENTER", icon, "CENTER", 0, 0)
	icon.time:SetTextColor(1, 0.95, 0.6)
	icon:SetScript("OnEnter", function()
		local timer = this.timer
		if not timer then
			return
		end
		GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
		GameTooltip:SetText(timer.name or "?", 1, 0.82, 0)
		GameTooltip:AddLine(timer.kind == "summon" and "Next summon" or "Cooldown", 0.7, 0.7, 0.7)
		if timer.ready then
			GameTooltip:AddLine("Ready", 0.3, 1, 0.3)
		else
			GameTooltip:AddDoubleLine("Time left", TimeLeft(timer.remaining or 0).." sec", 0.7, 0.7, 0.7, 1, 1, 1)
		end
		if (tonumber(timer.duration) or 0) > 0 then
			GameTooltip:AddDoubleLine("Whole wait", TimeLeft(timer.duration).." sec", 0.7, 0.7, 0.7, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	icons[index] = icon
	return icon
end

local function Fill(icon, timer, size)
	icon.timer = timer
	icon:SetWidth(size)
	icon:SetHeight(size)
	icon.time:SetFont(FONT, math.max(8, math.floor(size * 0.45 + 0.5)) + FONT_BUMP, "OUTLINE")
	icon.texture:SetTexture(IconPath(timer.icon))
	local duration = tonumber(timer.duration) or 0
	local remaining = tonumber(timer.remaining) or 0
	if timer.ready or remaining <= 0 then
		icon.shade:Hide()
		icon.time:SetText("")
		icon.texture:SetVertexColor(1, 1, 1)
		icon.edge:SetVertexColor(READY[1], READY[2], READY[3], 1)
	else
		local share = duration > 0 and math.min(1, remaining / duration) or 1
		icon.shade:SetHeight(math.max(1, size * share))
		icon.shade:Show()
		icon.time:SetText(TimeLeft(remaining))
		icon.texture:SetVertexColor(0.8, 0.8, 0.8)
		icon.edge:SetVertexColor(WAITING[1], WAITING[2], WAITING[3], 1)
	end
	icon:Show()
end

local function Update()
	local settings = Settings()
	local list = {}
	if settings.timers and Playing() then
		for _, timer in ipairs(AZS_GetTimers() or {}) do
			if (tonumber(timer.duration) or 0) >= MIN_WAIT then
				table.insert(list, timer)
			end
		end
	end
	-- In preview, with no clock running, a sample stands in, so it shows
	-- where the row comes.
	if settings.timers and table.getn(list) == 0 and SurvivorUI_Preview and SurvivorUI_Preview() then
		list = { { name = "Talent timers", icon = "INV_Misc_PocketWatch_01", kind = "cooldown", duration = 10, remaining = 4 } }
	end
	local size, gap = Size()
	local count = math.min(MAX_TIMERS, table.getn(list))
	local step = size + gap
	holder:SetWidth(math.max(1, count * step - gap))
	holder:SetHeight(size)
	Seat()
	local left = -(count * step - gap) / 2
	for index = 1, count do
		local icon = Icon(index)
		icon:ClearAllPoints()
		icon:SetPoint("BOTTOMLEFT", holder, "BOTTOM", left + (index - 1) * step, 0)
		Fill(icon, list[index], size)
	end
	for index = count + 1, table.getn(icons) do
		icons[index]:Hide()
		icons[index].timer = nil
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

if SurvivorUI_RegisterOption then
	SurvivorUI_RegisterOption({
		section = "General",
		label = "Talent timers",
		tip = "A row above your buffs with your talents' and jewelry's clocks: a proc's or a second life's wait, the next demon or wave. Each counts down on its icon and lights up gold when ready.",
		get = function() return Settings().timers end,
		toggle = function()
			local settings = Settings()
			settings.timers = not settings.timers
			Update()
		end,
	})
end
