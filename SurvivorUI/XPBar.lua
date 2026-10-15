-- Survivor UI: the run's level bar, an element of its own.
--
-- A flat purple bar with the level on it, filling toward the next; hover it
-- for the experience in numbers. It shows during a run, in place of the
-- game's own experience bar, which is put away meanwhile.
--
-- It sits under the action bar and follows it until it is moved on its own:
-- hold Alt and drag it. /sui layout puts it back; /sui xp hides it.

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local FONT = SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BUMP = SurvivorUI_FONT_BUMP or 0

local WIDTH = 360
local HEIGHT = 10
local FILL = { 0.58, 0.30, 0.85 }

local row = getglobal("SurvivorUIRow")

local function Settings()
	SurvivorUIDB = SurvivorUIDB or {}
	if SurvivorUIDB.xpBar == nil then
		SurvivorUIDB.xpBar = true
	end
	if SurvivorUIDB.xpEstimate == nil then
		SurvivorUIDB.xpEstimate = true
	end
	return SurvivorUIDB
end

local function Num(value)
	return tonumber(value) or 0
end

-- The game's run, while one is on.
local function Game()
	if AZS_GetPhase and AZS_RUN then
		local phase = AZS_GetPhase()
		if phase and phase ~= "ready" then
			return AZS_RUN
		end
	end
end

------------------------------------------------------------------------------
-- The bar.

local bar = CreateFrame("StatusBar", "SurvivorUIXP", UIParent)
bar:SetWidth(WIDTH)
bar:SetHeight(HEIGHT)
bar:SetFrameStrata("LOW")
bar:SetStatusBarTexture(FLAT)
bar:SetStatusBarColor(FILL[1], FILL[2], FILL[3], 1)
bar:SetMinMaxValues(0, 1)
bar:SetMovable(true)
if bar.SetClampedToScreen then
	bar:SetClampedToScreen(true)
end
bar:Hide()

bar.edge = bar:CreateTexture(nil, "BACKGROUND")
bar.edge:SetTexture(FLAT)
bar.edge:SetVertexColor(0, 0, 0, 1)
bar.edge:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
bar.edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)

bar.backing = bar:CreateTexture(nil, "BORDER")
bar.backing:SetTexture(FLAT)
bar.backing:SetVertexColor(0.09, 0.09, 0.11, 1)
bar.backing:SetAllPoints(bar)

bar.label = bar:CreateFontString(nil, "OVERLAY")
bar.label:SetFont(FONT, 9 + FONT_BUMP, "OUTLINE")
bar.label:SetPoint("CENTER", bar, "CENTER", 0, 0)

bar:EnableMouse(true)
bar:SetScript("OnEnter", function()
	local game = Game()
	if not game then
		return
	end
	local xp, needed = Num(game.xp), Num(game.xpn)
	GameTooltip:SetOwner(this, "ANCHOR_TOP")
	GameTooltip:SetText("Level "..Num(game.lvl), FILL[1] + 0.2, FILL[2] + 0.25, 1)
	GameTooltip:AddDoubleLine("Experience", xp.." / "..needed, 0.7, 0.7, 0.7, 1, 1, 1)
	if needed > 0 then
		GameTooltip:AddDoubleLine("To the next level", (needed - xp).."  ("..math.floor((1 - xp / needed) * 100 + 0.5).."%)", 0.7, 0.7, 0.7, 1, 1, 1)
	end
	GameTooltip:Show()
end)
bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Its place is kept by its center.
local function SavePlace()
	local x, y = bar:GetCenter()
	if not x then
		return
	end
	local settings = Settings()
	settings.xpX = math.floor(x + 0.5)
	settings.xpY = math.floor(y + 0.5)
	bar:ClearAllPoints()
	bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", settings.xpX, settings.xpY)
end

-- The saved place, or under the action bar, following it.
local function RestorePlace()
	local settings = Settings()
	bar:ClearAllPoints()
	if settings.xpX then
		bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", settings.xpX, settings.xpY)
	elseif row then
		bar:SetPoint("TOP", getglobal("SurvivorUIRowBlock") or row, "BOTTOM", 0, -5)
	else
		bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 60)
	end
end
RestorePlace()

------------------------------------------------------------------------------
-- Keeping it current, and the game's own bar out of the way while it shows.

local function StockBar(shown)
	local stock = getglobal("MainMenuExpBar")
	if not stock then
		return
	end
	local want = shown and 1 or 0
	if stock:GetAlpha() ~= want then
		stock:SetAlpha(want)
		if stock.EnableMouse then
			stock:EnableMouse(shown)
		end
	end
end

------------------------------------------------------------------------------
-- The next level, foretold: "Next level in 1:24 min" under the bar (over it
-- when the bar sits at the screen's bottom edge), from the experience gained
-- over the last minute of the run's clock. That clock stops for a pause or a
-- card choice, so neither drags the estimate down.

local WINDOW = 60               -- run seconds the rate is taken over
local MIN_SPAN = 5              -- run seconds of experience before any estimate
local EDGE = 20                 -- closer than this to the screen's bottom, it goes over the bar

local ESTIMATE_SIZE = 10        -- its text size until one is chosen in /sui opt
local ESTIMATE_MIN, ESTIMATE_MAX = 8, 24

local estimate = bar:CreateFontString(nil, "OVERLAY")
estimate:SetFont(FONT, ESTIMATE_SIZE + FONT_BUMP, "OUTLINE")
estimate:SetTextColor(0.85, 0.75, 1)

local function EstimateSize()
	return math.max(ESTIMATE_MIN, math.min(ESTIMATE_MAX, tonumber(Settings().xpEstimateSize) or ESTIMATE_SIZE))
end

local function ApplyEstimateSize()
	estimate:SetFont(FONT, EstimateSize() + FONT_BUMP, "OUTLINE")
end

local samples = {}              -- { t = run second, gained = experience so far }, a second apart
local gained = 0                -- experience gained this run, across level ups
local lastLevel, lastXp, lastNeeded, lastClock

-- Keeps count of the experience gained; returns the seconds to the next
-- level, or nil while there is too little to go on.
local function Track(game)
	local clock = (AZS_GetRunTime and AZS_GetRunTime()) or Num(game.t)
	local level, xp, needed = Num(game.lvl), Num(game.xp), Num(game.xpn)
	-- The clock going back means a new run: count afresh.
	if lastClock and clock + 3 < lastClock then
		samples, gained, lastLevel = {}, 0, nil
	end
	if lastLevel then
		if level > lastLevel then
			gained = gained + math.max(0, lastNeeded - lastXp) + xp
		elseif xp > lastXp then
			gained = gained + xp - lastXp
		end
	end
	lastLevel, lastXp, lastNeeded, lastClock = level, xp, needed, clock

	local newest = samples[table.getn(samples)]
	if not newest or clock - newest.t >= 1 then
		table.insert(samples, { t = clock, gained = gained })
	end
	while table.getn(samples) > 1 and clock - samples[1].t > WINDOW do
		table.remove(samples, 1)
	end

	local first = samples[1]
	local span = clock - first.t
	if span < MIN_SPAN then
		return nil
	end
	local rate = (gained - first.gained) / span
	if rate <= 0 then
		return nil
	end
	return (needed - xp) / rate
end

-- 45 sec, 1:24 min
local function Until(seconds)
	seconds = math.ceil(seconds)
	if seconds >= 60 then
		return string.format("%d:%02d min", math.floor(seconds / 60), math.mod(seconds, 60))
	end
	return seconds.." sec"
end

local function PlaceEstimate()
	local bottom = bar:GetBottom()
	local above = bottom ~= nil and bottom < EDGE
	if above ~= estimate.above then
		estimate.above = above
		estimate:ClearAllPoints()
		if above then
			estimate:SetPoint("BOTTOM", bar, "TOP", 0, 3)
		else
			estimate:SetPoint("TOP", bar, "BOTTOM", 0, -3)
		end
	end
end

local elapsed = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function()
	elapsed = elapsed + arg1
	if elapsed < 0.2 then
		return
	end
	elapsed = 0
	local game = Game()
	-- In preview (before the first step, or with Alt held) it shows anyway,
	-- with whatever the game has shared so far, so it can be placed.
	if not game and SurvivorUI_Preview and SurvivorUI_Preview() then
		game = AZS_RUN or {}
	end
	if not (game and Settings().xpBar) then
		bar:Hide()
		StockBar(not game)
		return
	end
	local xp, needed = Num(game.xp), Num(game.xpn)
	bar:SetValue(needed > 0 and xp / needed or 0)
	bar.label:SetText("Level "..math.max(1, Num(game.lvl)))
	bar:Show()
	StockBar(false)

	local left = Track(game)
	if Settings().xpEstimate then
		PlaceEstimate()
		estimate:SetText("Next level in "..(left and Until(left) or "|cff8a8a8a...|r"))
		estimate:Show()
	else
		estimate:Hide()
	end
end)

function SurvivorUI_ToggleXP()
	local settings = Settings()
	settings.xpBar = not settings.xpBar
	DEFAULT_CHAT_FRAME:AddMessage("Survivor UI: level bar "..(settings.xpBar and "shown." or "hidden."))
end

if SurvivorUI_RegisterOption then
	SurvivorUI_RegisterOption({
		section = "Panels",
		label = "Level bar",
		tip = "The run's level and its experience, in a bar of its own that moves with Alt.",
		command = "/sui xp",
		get = function() return Settings().xpBar end,
		toggle = SurvivorUI_ToggleXP,
	})
	SurvivorUI_RegisterOption({
		section = "Panels",
		label = "Next level estimate",
		parent = "Level bar",
		tip = "\"Next level in 1:24 min\" under the level bar, from the experience you gained over the last minute of the run.",
		get = function() return Settings().xpEstimate end,
		toggle = function()
			local settings = Settings()
			settings.xpEstimate = not settings.xpEstimate
		end,
	})
	SurvivorUI_RegisterOption({
		section = "Panels",
		kind = "slider",
		label = "Next level text size",
		parent = "Level bar",
		tip = "The size of the \"Next level in ...\" text.",
		min = ESTIMATE_MIN,
		max = ESTIMATE_MAX,
		step = 1,
		get = EstimateSize,
		set = function(size)
			Settings().xpEstimateSize = size
			ApplyEstimateSize()
		end,
	})
end

if SurvivorUI_RegisterMover then
	SurvivorUI_RegisterMover(bar, "XP bar", SavePlace, nil, RestorePlace)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function()
	ApplyEstimateSize()
	RestorePlace()
end)
