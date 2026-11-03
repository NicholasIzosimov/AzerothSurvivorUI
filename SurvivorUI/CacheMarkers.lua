-- Survivor UI: cache markers.
--
-- A chest icon over every cache in the world, the yards to it under it, held
-- on the cache itself as the camera moves: the game's world anchors
-- (AZS_GetWorldAnchors) say where each cache is, and each world frame
-- (AZS_RegisterWorldAnchorFrameHandler, after the frame's camera) projects
-- them onto the screen. Faint and tinted red while the gold does not cover
-- the next cache.
-- A cache off the screen shows nothing here; the cache
-- arrow points to it. Needs the game's world anchors; without them nothing
-- shows. A switch in /sui opt ("Cache markers").

local FONT = SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BUMP = SurvivorUI_FONT_BUMP or 0
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"

local ICON = "Interface\\Icons\\INV_Box_02"
local ICON_SIZE = 22
local LIFT = 1.5                -- yards above the cache the marker floats
local LOOK_EVERY = 1            -- seconds between asks for the caches themselves
local MAX_MARKERS = 16
local GOLD = { 1, 0.82, 0 }
-- Placeholder: how faint a marker is while the run's gold does not cover the
-- next cache (SurvivorUI_CanAffordCache, CacheReminder.lua).
local POOR_ALPHA = 0.12
-- And tinted red: the icon and its edge.
local POOR_TINT = { 1, 0.8, 0.8 }
local POOR_EDGE = { 0.75, 0.5, 0.35 }

local function Settings()
	SurvivorUIDB = SurvivorUIDB or {}
	if SurvivorUIDB.cacheMarkers == nil then
		SurvivorUIDB.cacheMarkers = true
	end
	return SurvivorUIDB
end

local function Playing()
	if not AZS_GetPhase then
		return false
	end
	local phase = AZS_GetPhase()
	return phase == "playing" or phase == "choosing" or phase == "paused"
end

------------------------------------------------------------------------------
-- The markers: an icon in a gold edge, the yards under it.

local holder = CreateFrame("Frame", "SurvivorUICacheMarkers", UIParent)
holder:SetAllPoints(UIParent)
holder:SetFrameStrata("BACKGROUND")

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
	marker.edge:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	marker.edge:SetPoint("TOPLEFT", marker, "TOPLEFT", -1, 1)
	marker.edge:SetPoint("BOTTOMRIGHT", marker, "BOTTOMRIGHT", 1, -1)
	marker.icon = marker:CreateTexture(nil, "ARTWORK")
	marker.icon:SetTexture(ICON)
	marker.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	marker.icon:SetAllPoints(marker)
	marker.yards = marker:CreateFontString(nil, "OVERLAY")
	marker.yards:SetFont(FONT, 10 + FONT_BUMP, "OUTLINE")
	marker.yards:SetPoint("TOP", marker, "BOTTOM", 0, -2)
	marker.yards:SetTextColor(1, 1, 1)
	markers[index] = marker
	return marker
end

local function HideFrom(first)
	for index = first, table.getn(markers) do
		markers[index]:Hide()
	end
end

------------------------------------------------------------------------------
-- The caches, asked for every LOOK_EVERY seconds; the projection, every frame.

local requests = {}             -- { anchorId, attachment, offsetYards } per cache still there
local looked = LOOK_EVERY

local function Look()
	requests = {}
	local answer = AZS_GetWorldAnchors({ kinds = { "cache" } }, nil, MAX_MARKERS)
	local entries = type(answer) == "table" and answer.entries or {}
	for index = 1, table.getn(entries) do
		local entry = entries[index]
		if entry.state == "present" and entry.positionAvailable then
			table.insert(requests, { anchorId = entry.anchorId, attachment = "position", offsetYards = LIFT })
		end
	end
end

local function Frame()
	if not (Settings().cacheMarkers and Playing()) then
		HideFrom(1)
		return
	end
	if looked >= LOOK_EVERY then
		looked = 0
		Look()
	end
	if table.getn(requests) == 0 then
		HideFrom(1)
		return
	end
	local answer = AZS_ProjectWorldAnchors(requests)
	local entries = type(answer) == "table" and answer.entries or {}
	-- The game's x and y are offsets from WorldFrame's bottom left in
	-- WorldFrame's own scale; the markers live under UIParent, whose scale is
	-- the interface's.
	local ratio = WorldFrame:GetEffectiveScale() / holder:GetEffectiveScale()
	local afford = SurvivorUI_CanAffordCache and SurvivorUI_CanAffordCache()
	local alpha = afford and 1 or POOR_ALPHA
	local tint = afford and { 1, 1, 1 } or POOR_TINT
	local edge = afford and GOLD or POOR_EDGE
	local shown = 0
	for index = 1, table.getn(entries) do
		local entry = entries[index]
		if entry.state == "onScreen" and entry.entityState == "present" and entry.x and entry.y then
			shown = shown + 1
			local marker = Marker(shown)
			marker:ClearAllPoints()
			marker:SetPoint("BOTTOM", WorldFrame, "BOTTOMLEFT", entry.x * ratio, entry.y * ratio)
			marker.yards:SetText(entry.playerDistance and math.floor(entry.playerDistance + 0.5).." yd" or "")
			marker:SetAlpha(alpha)
			marker.icon:SetVertexColor(tint[1], tint[2], tint[3])
			marker.edge:SetVertexColor(edge[1], edge[2], edge[3], 1)
			marker:Show()
		end
	end
	HideFrom(shown + 1)
end

-- The frame handler runs after the frame's camera but gets no elapsed time,
-- so the asks for the caches are timed by an OnUpdate of their own.
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
		label = "Cache markers",
		tip = "A chest icon over every cache on the screen, held on the cache as the camera moves, with the yards to it under it.",
		get = function() return Settings().cacheMarkers end,
		toggle = function()
			local settings = Settings()
			settings.cacheMarkers = not settings.cacheMarkers
		end,
	})
end
