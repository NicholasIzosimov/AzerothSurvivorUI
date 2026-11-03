-- Survivor UI: elite markers.
--
-- A marker over every elite and guardian on the screen, held on it as it and
-- the camera move, the yards to it under it, as the cache markers sit on the
-- caches: the game's world anchors (AZS_GetWorldAnchors) say where each one
-- is, and each world frame (AZS_RegisterWorldAnchorFrameHandler) projects
-- them onto the screen. A marker fades as the hero closes in.
--
-- A guardian slain leaves its lair empty till it comes back: a grey marker
-- stays on the lair (where the guardian sleeps, not where it fell) with the
-- time till it does, the lair's own countdown from the game (AZS_LAIRS left).
--
-- The marker shows the unit's portrait. The game shares no picture of a unit
-- it names no unit token for, so the portraits of a name are taken the first
-- time one of that name is the target or under the mouse, and kept for the
-- session; till then a skull stands in.
--
-- Needs the game's world anchors; without them nothing shows. A switch in
-- /sui opt ("Elite markers").

local FONT = SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BUMP = SurvivorUI_FONT_BUMP or 0
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"

local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local ICON_SIZE = 24
local OVERHEAD_LIFT = 0.5       -- yards above a unit's head
local LAIR_LIFT = 1.5           -- yards above an empty lair
local LOOK_EVERY = 0.25         -- seconds between asks for the elites and lairs
local MAX_MARKERS = 24
local SAME_NAME = 6             -- markers of one name that can show its portrait at once
local LIVING = { 1, 0.45, 0.15 }
local WAITING = { 0.55, 0.55, 0.55 }
-- Placeholders: a marker is faintest (FADE_LOW) at FADE_NEAR yards or closer
-- and whole from FADE_FAR yards on.
local FADE_NEAR, FADE_FAR = 10, 60
local FADE_LOW = 0.15

local function Settings()
	SurvivorUIDB = SurvivorUIDB or {}
	-- The arrow these markers took the place of kept its switch here.
	if SurvivorUIDB.eliteMarkers == nil then
		SurvivorUIDB.eliteMarkers = SurvivorUIDB.eliteArrow ~= false
	end
	SurvivorUIDB.eliteArrow = nil
	return SurvivorUIDB
end

local function Playing()
	if not AZS_GetPhase then
		return false
	end
	local phase = AZS_GetPhase()
	return phase == "playing" or phase == "choosing" or phase == "paused"
end

local function Field(entry, name, index)
	if entry[name] ~= nil then
		return entry[name]
	end
	return entry[index]
end

local function Clock(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", math.floor(seconds / 60), math.mod(seconds, 60))
end

------------------------------------------------------------------------------
-- The markers: a colored edge, a skull in it, the yards and an empty lair's
-- time under it. The portraits lie in a layer above, each placed over its
-- marker (Portraits).

local holder = CreateFrame("Frame", "SurvivorUIEliteMarkers", UIParent)
holder:SetAllPoints(UIParent)
holder:SetFrameStrata("BACKGROUND")

local portraitLayer = CreateFrame("Frame", nil, holder)
portraitLayer:SetAllPoints(holder)
portraitLayer:SetFrameLevel(holder:GetFrameLevel() + 10)

local markers = {}

local function Marker(index)
	local marker = markers[index]
	if marker then
		return marker
	end
	marker = CreateFrame("Frame", nil, holder)
	marker:SetWidth(ICON_SIZE)
	marker:SetHeight(ICON_SIZE)
	marker.edge = marker:CreateTexture(nil, "BACKGROUND")
	marker.edge:SetTexture(FLAT)
	marker.edge:SetPoint("TOPLEFT", marker, "TOPLEFT", -1, 1)
	marker.edge:SetPoint("BOTTOMRIGHT", marker, "BOTTOMRIGHT", 1, -1)
	marker.fill = marker:CreateTexture(nil, "BORDER")
	marker.fill:SetTexture(FLAT)
	marker.fill:SetVertexColor(0.05, 0.05, 0.05, 1)
	marker.fill:SetAllPoints(marker)
	marker.skull = marker:CreateTexture(nil, "ARTWORK")
	marker.skull:SetTexture(SKULL)
	marker.skull:SetWidth(ICON_SIZE * 0.7)
	marker.skull:SetHeight(ICON_SIZE * 0.7)
	marker.skull:SetPoint("CENTER", marker, "CENTER", 0, 0)
	marker.yards = marker:CreateFontString(nil, "OVERLAY")
	marker.yards:SetFont(FONT, 10 + FONT_BUMP, "OUTLINE")
	marker.yards:SetPoint("TOP", marker, "BOTTOM", 0, -2)
	marker.yards:SetTextColor(1, 1, 1)
	marker.back = marker:CreateFontString(nil, "OVERLAY")
	marker.back:SetFont(FONT, 10 + FONT_BUMP, "OUTLINE")
	marker.back:SetPoint("TOP", marker.yards, "BOTTOM", 0, -1)
	marker.back:SetTextColor(1, 0.82, 0)
	markers[index] = marker
	return marker
end

------------------------------------------------------------------------------
-- The portraits: SAME_NAME of them for each name, all taken at once from the
-- target or the mouse's unit, lent out to the markers each frame.

local portraits = {}            -- [name] = { textures }
local lent = {}                 -- [name] = how many are out this frame

local function Take(unit)
	if not UnitExists(unit) or UnitIsPlayer(unit) then
		return
	end
	local class = UnitClassification and UnitClassification(unit)
	if not class or class == "normal" or class == "trivial" or class == "minus" then
		return
	end
	local name = UnitName(unit)
	if not name then
		return
	end
	if not portraits[name] then
		portraits[name] = {}
		for index = 1, SAME_NAME do
			local texture = portraitLayer:CreateTexture(nil, "ARTWORK")
			texture:SetWidth(ICON_SIZE - 2)
			texture:SetHeight(ICON_SIZE - 2)
			texture:Hide()
			portraits[name][index] = texture
		end
	end
	for index = 1, SAME_NAME do
		SetPortraitTexture(portraits[name][index], unit)
	end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
watcher:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
watcher:SetScript("OnEvent", function()
	Take(event == "PLAYER_TARGET_CHANGED" and "target" or "mouseover")
end)

-- A portrait of this name free this frame, or nil.
local function Borrow(name)
	local textures = name and portraits[name]
	if not textures then
		return nil
	end
	local count = (lent[name] or 0) + 1
	if count > SAME_NAME then
		return nil
	end
	lent[name] = count
	return textures[count]
end

local function PutAwayPortraits()
	for name, textures in pairs(portraits) do
		for index = (lent[name] or 0) + 1, SAME_NAME do
			textures[index]:Hide()
		end
	end
end

------------------------------------------------------------------------------
-- What to mark, asked for every LOOK_EVERY seconds: each living elite and
-- guardian over its head, each empty lair on its spot.

local requests = {}             -- the projection's requests
local targets = {}              -- per request: { name, lair }
local looked = LOOK_EVERY

-- Seconds till lair number index has its guardian back, from the game's lair
-- line (its "left" counted down from when the line came), or nil.
local function LairLeft(index)
	for position = 1, table.getn(AZS_LAIRS or {}) do
		local lair = AZS_LAIRS[position]
		if tonumber(Field(lair, "index", 1)) == index then
			local left = tonumber(Field(lair, "left", 5))
			if not left then
				return nil
			end
			return left - (GetTime() - (AZS_LAIRS_UPDATED or GetTime()))
		end
	end
end

local function Entries(kinds)
	local answer = AZS_GetWorldAnchors({ kinds = kinds }, nil, MAX_MARKERS)
	return type(answer) == "table" and answer.entries or {}
end

local function Look()
	requests, targets = {}, {}
	local living = Entries({ "elite", "guardian" })
	for index = 1, table.getn(living) do
		local entry = living[index]
		if entry.state == "alive" and entry.positionAvailable then
			table.insert(requests, { anchorId = entry.anchorId, attachment = "overhead", offsetYards = OVERHEAD_LIFT })
			table.insert(targets, { name = entry.name })
		end
	end
	local lairs = Entries({ "guardianLair" })
	for index = 1, table.getn(lairs) do
		local entry = lairs[index]
		if entry.state == "empty" and entry.positionAvailable then
			table.insert(requests, { anchorId = entry.anchorId, attachment = "position", offsetYards = LAIR_LIFT })
			table.insert(targets, { name = entry.name, lair = entry.lairIndex })
		end
	end
end

------------------------------------------------------------------------------
-- Each world frame: the markers onto the screen.

local function HideFrom(first)
	for index = first, table.getn(markers) do
		markers[index]:Hide()
	end
end

local function Fill(marker, target, entry)
	local distance = entry.playerDistance or FADE_FAR
	local share = math.max(0, math.min(1, (distance - FADE_NEAR) / (FADE_FAR - FADE_NEAR)))
	marker:SetAlpha(FADE_LOW + (1 - FADE_LOW) * share)
	marker.yards:SetText(entry.playerDistance and math.floor(entry.playerDistance + 0.5).." yd" or "")
	local color = target.lair and WAITING or LIVING
	marker.edge:SetVertexColor(color[1], color[2], color[3], 1)
	if target.lair then
		local left = LairLeft(target.lair)
		marker.back:SetText(left and (left > 0 and Clock(left) or "any moment") or "")
	else
		marker.back:SetText("")
	end
	local portrait = Borrow(target.name)
	if portrait then
		portrait:ClearAllPoints()
		portrait:SetPoint("CENTER", marker, "CENTER", 0, 0)
		portrait:SetAlpha(marker:GetAlpha())
		if portrait.SetDesaturated then
			portrait:SetDesaturated(target.lair ~= nil)
		end
		portrait:Show()
		marker.skull:Hide()
	else
		marker.skull:Show()
	end
end

local function Frame()
	lent = {}
	if not (Settings().eliteMarkers and Playing()) then
		HideFrom(1)
		PutAwayPortraits()
		return
	end
	if looked >= LOOK_EVERY then
		looked = 0
		Look()
	end
	local shown = 0
	if table.getn(requests) > 0 then
		local answer = AZS_ProjectWorldAnchors(requests)
		local entries = type(answer) == "table" and answer.entries or {}
		-- The game's x and y are offsets from WorldFrame's bottom left in
		-- WorldFrame's own scale; the markers live under UIParent.
		local ratio = WorldFrame:GetEffectiveScale() / holder:GetEffectiveScale()
		for index = 1, table.getn(entries) do
			local entry = entries[index]
			local target = targets[index]
			if target and entry.state == "onScreen" and entry.x and entry.y then
				shown = shown + 1
				local marker = Marker(shown)
				marker:ClearAllPoints()
				marker:SetPoint("BOTTOM", WorldFrame, "BOTTOMLEFT", entry.x * ratio, entry.y * ratio)
				Fill(marker, target, entry)
				marker:Show()
			end
		end
	end
	HideFrom(shown + 1)
	PutAwayPortraits()
end

-- The frame handler gets no elapsed time; an OnUpdate of its own keeps it.
local clock = CreateFrame("Frame")
clock:SetScript("OnUpdate", function()
	looked = looked + arg1
end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function()
	if AZS_RegisterWorldAnchorFrameHandler and AZS_GetWorldAnchors and AZS_ProjectWorldAnchors then
		AZS_RegisterWorldAnchorFrameHandler(Frame)
	end
end)

if SurvivorUI_RegisterOption then
	SurvivorUI_RegisterOption({
		section = "Interface",
		label = "Elite markers",
		tip = "A marker with the portrait over every elite and guardian on the screen, with the yards to it, fading as you close in. A slain guardian's lair keeps a grey marker with the time till it is back. Portraits come once you have targeted or moused over one of that name; a skull till then.",
		get = function() return Settings().eliteMarkers end,
		toggle = function()
			local settings = Settings()
			settings.eliteMarkers = not settings.eliteMarkers
		end,
	})
end
