-- Survivor UI: the next cache reminder.
--
-- "Can Afford Next Cache!" in large green letters over the middle of the
-- screen, a little above the hero, while the run's gold covers the next
-- cache's price (both from the game's addon API, AZS_RUN), and under it the
-- gold against the price ("505 / 20"). It fades in when the gold gets there,
-- then breathes while it stays, fading well down and back; spending it below
-- the price puts it away. Its size never changes: the game draws a font only
-- at whole sizes, so any swell visibly steps.
--
-- A switch and its size in /sui opt ("Next Cache Reminder"); in edit mode (tap Alt), drag
-- it to move it, /sui layout puts it back.

local FONT = SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BUMP = SurvivorUI_FONT_BUMP or 0

local TEXT = "Can Afford Next Cache!"
local SIZE = 30                 -- the letters' size until one is chosen
local SIZE_MIN, SIZE_MAX = 14, 60
local DEFAULT_Y = 120           -- above the screen's middle, clear of the hero
local FADE_IN = 0.35            -- seconds to fade in
local PULSE = 2.2               -- seconds for one breath, down and back up
local PULSE_LOW = 0.4           -- the faintest it fades to in a breath
local RATIO_SHARE = 0.5         -- the gold / price line's size, against the main line's

local function Settings()
	SurvivorUIDB = SurvivorUIDB or {}
	if SurvivorUIDB.cacheReminder == nil then
		SurvivorUIDB.cacheReminder = true
	end
	if SurvivorUIDB.cacheArrow == nil then
		SurvivorUIDB.cacheArrow = true
	end
	if SurvivorUIDB.cachePins == nil then
		SurvivorUIDB.cachePins = true
	end
	-- The arrow points by the map unless asked otherwise: the game's camera
	-- does not turn with the hero, so north stays up on the screen.
	if SurvivorUIDB.cacheArrowByMap == nil then
		SurvivorUIDB.cacheArrowByMap = true
	end
	return SurvivorUIDB
end

local function TextSize()
	return math.max(SIZE_MIN, math.min(SIZE_MAX, tonumber(Settings().cacheReminderSize) or SIZE))
end

------------------------------------------------------------------------------
-- The text, in a frame sized to it so its edit-mode handle covers it.

local holder = CreateFrame("Frame", "SurvivorUICacheReminder", UIParent)
holder:SetFrameStrata("HIGH")
holder:SetWidth(300)
holder:SetHeight(SIZE + 8)
holder:SetMovable(true)
if holder.SetClampedToScreen then
	holder:SetClampedToScreen(true)
end

-- A dark box behind the lines, as the kills and gold box wears, so they read
-- over the fight. It fades in with them but holds steady while they breathe.
local box = CreateFrame("Frame", nil, holder)
box:SetBackdrop({
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
	tile = false, edgeSize = 1,
	insets = { left = 1, right = 1, top = 1, bottom = 1 },
})
box:SetBackdropColor(0, 0, 0, 0.75)
box:SetBackdropBorderColor(0, 0, 0, 1)
box:SetAllPoints(holder)
box:Hide()

-- The lines sit on an inner frame centered on the holder, above the box,
-- which fades them as a whole.
local inner = CreateFrame("Frame", nil, holder)
inner:SetWidth(300)
inner:SetHeight(SIZE + 8)
inner:SetPoint("CENTER", holder, "CENTER", 0, 0)
inner:SetFrameLevel(box:GetFrameLevel() + 1)
inner:Hide()

local text = inner:CreateFontString(nil, "OVERLAY")
text:SetFont(FONT, SIZE + FONT_BUMP, "THICKOUTLINE")
text:SetPoint("TOP", inner, "TOP", 0, -4)
text:SetTextColor(0.25, 1, 0.35)
text:SetText(TEXT)

local ratio = inner:CreateFontString(nil, "OVERLAY")
ratio:SetFont(FONT, math.floor(SIZE * RATIO_SHARE) + FONT_BUMP, "OUTLINE")
ratio:SetPoint("TOP", text, "BOTTOM", 0, -2)

-- With the reminder's words switched off, the gold against the price stands
-- alone, at the words' size: "505 / 20".
local function TextShown()
	return Settings().cacheReminderText ~= false
end

local function ApplySize()
	local size = TextSize()
	local width, height
	ratio:ClearAllPoints()
	if TextShown() then
		local small = math.max(9, math.floor(size * RATIO_SHARE + 0.5))
		text:SetFont(FONT, size + FONT_BUMP, "THICKOUTLINE")
		ratio:SetFont(FONT, small + FONT_BUMP, "OUTLINE")
		ratio:SetPoint("TOP", text, "BOTTOM", 0, -2)
		text:Show()
		width = text:GetStringWidth() + 16
		height = size + small + 2 * FONT_BUMP + 10
	else
		ratio:SetFont(FONT, size + FONT_BUMP, "THICKOUTLINE")
		ratio:SetPoint("CENTER", inner, "CENTER", 0, 0)
		text:Hide()
		-- Wide enough for a large gold and price, so the box holds its size.
		ratio:SetText("00,000 / 00,000")
		width = ratio:GetStringWidth() + 16
		height = size + FONT_BUMP + 10
	end
	holder:SetWidth(width)
	holder:SetHeight(height)
	inner:SetWidth(width)
	inner:SetHeight(height)
end

-- "505 / 20": with the words, the gold in gold and the price in the caches'
-- green; alone, the gold in green and the price in white.
local function ShowRatio()
	local run = AZS_RUN or {}
	local gold, price = tonumber(run.gold), tonumber(run.chest)
	if TextShown() then
		ratio:SetText("|cffffd24d"..(gold or "-").."|r |cff9a9a9a/|r |cff8cd98c"..(price or "-").."|r")
	else
		ratio:SetText("|cff40ff59"..(gold or "-").."|r |cff9a9a9a/|r |cffffffff"..(price or "-").."|r")
	end
end

-- Its place is kept by its center.
local function SavePlace()
	local x, y = holder:GetCenter()
	if not x then
		return
	end
	local settings = Settings()
	settings.cacheX = math.floor(x + 0.5)
	settings.cacheY = math.floor(y + 0.5)
	holder:ClearAllPoints()
	holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", settings.cacheX, settings.cacheY)
end

local function RestorePlace()
	local settings = Settings()
	holder:ClearAllPoints()
	if settings.cacheX then
		holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", settings.cacheX, settings.cacheY)
	else
		holder:SetPoint("CENTER", UIParent, "CENTER", 0, DEFAULT_Y)
	end
end
RestorePlace()

------------------------------------------------------------------------------
-- Watching the gold.

-- True while a run is on and its gold covers the next cache.
local function Affordable()
	if not (AZS_GetPhase and AZS_RUN) then
		return false
	end
	local phase = AZS_GetPhase()
	if phase ~= "playing" and phase ~= "paused" then
		return false
	end
	local gold, price = tonumber(AZS_RUN.gold), tonumber(AZS_RUN.chest)
	return gold ~= nil and price ~= nil and price > 0 and gold >= price
end

------------------------------------------------------------------------------
-- The arrow: over the reminder, pointing to the nearest cache (the game sends
-- where every cache is, AZS_CHESTS), with the distance under it, green when
-- near and turning red with distance. It points with north up (the game's
-- camera does not turn); switched off "by the map", it points relative to the
-- way the hero faces, as TomTom's does, read off the minimap's own player
-- arrow, or the way the hero last moved where that cannot be read.
--
-- It keeps to one cache: another has to be SWITCH_MARGIN yards nearer before
-- the arrow turns to it, so two caches at about the same distance do not
-- trade places every step. It turns toward its bearing smoothly rather than
-- in jumps, and looks again every few seconds even while the hero stands
-- still.

local ARROW = "Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW"
local ARROW_SIZE = 56           -- the arrow's size until one is chosen
local ARROW_MIN, ARROW_MAX = 24, 96
local NEAR, FAR = 15, 150       -- yards: green at NEAR, red from FAR, while no heading is known
local SWITCH_MARGIN = 10        -- yards another cache must be nearer by to take the arrow
local TURN_RATE = 16            -- how quickly the arrow catches up with its bearing
local AIM_EVERY = 0.05          -- seconds between readings of the hero and the caches
local REFRESH_EVERY = 2         -- seconds between full looks, standing still or not

local function ArrowSize()
	return math.max(ARROW_MIN, math.min(ARROW_MAX, tonumber(Settings().cacheArrowSize) or ARROW_SIZE))
end

local arrowFrame = CreateFrame("Frame", nil, holder)
arrowFrame:SetPoint("BOTTOM", holder, "TOP", 0, 2)
arrowFrame:Hide()

local arrow = arrowFrame:CreateTexture(nil, "OVERLAY")
arrow:SetTexture(ARROW)
arrow:SetPoint("TOP", arrowFrame, "TOP", 0, 0)

local distance = arrowFrame:CreateFontString(nil, "OVERLAY")
distance:SetPoint("TOP", arrow, "BOTTOM", 0, 2)

-- The arrow at its size, the distance under it in proportion.
local function ApplyArrowSize()
	local size = ArrowSize()
	local textSize = math.max(10, math.floor(size * 0.22 + 0.5))
	arrow:SetWidth(size)
	arrow:SetHeight(size)
	distance:SetFont(FONT, textSize + FONT_BUMP, "OUTLINE")
	arrowFrame:SetWidth(size)
	arrowFrame:SetHeight(size + textSize + 4)
end
ApplyArrowSize()

-- Turns the arrow's picture by an angle, clockwise, about its middle.
local function Turn(angle)
	local c, s = math.cos(angle), math.sin(angle)
	local function Corner(x, y)
		return 0.5 + c * x + s * y, 0.5 - s * x + c * y
	end
	local ulx, uly = Corner(-0.5, -0.5)
	local llx, lly = Corner(-0.5, 0.5)
	local urx, ury = Corner(0.5, -0.5)
	local lrx, lry = Corner(0.5, 0.5)
	arrow:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

-- The hero's facing, radians counterclockwise from north, from the minimap's
-- player arrow model; nil if it cannot be found.
local playerArrow
local function Facing()
	if not playerArrow and Minimap then
		local children = { Minimap:GetChildren() }
		for index = 1, table.getn(children) do
			local child = children[index]
			if child.GetObjectType and child:GetObjectType() == "Model" and not child:GetName()
				and child.GetModel and type(child:GetModel()) == "string"
				and string.find(string.lower(child:GetModel()), "minimaparrow", 1, true) then
				playerArrow = child
				break
			end
		end
	end
	local facing = playerArrow and playerArrow.GetFacing and playerArrow:GetFacing()
	-- A facing of exactly 0 is a model that does not turn with the hero (this
	-- client draws its arrow its own way): no facing to go by, the arrow then
	-- points by the map.
	if not facing or facing == 0 then
		return nil
	end
	return facing
end

local function Field(entry, name, index)
	if entry[name] ~= nil then
		return entry[name]
	end
	return entry[index]
end

-- A cache's map position, the map's 0 to 1 (a value past 1 is read as percent).
local function MapPoint(entry)
	local x, y = tonumber(Field(entry, "mx", 5)), tonumber(Field(entry, "my", 6))
	if not (x and y) then
		return nil
	end
	if x > 1.5 or y > 1.5 then
		x, y = x / 100, y / 100
	end
	return x, y
end

-- How many yards one whole map spans, east-west and north-south, learned from
-- every point the game sends with both a world and a map position: the caches
-- (AZS_CHESTS) and the guardians' lairs (AZS_LAIRS), so it knows the scale
-- even with no cache about. The world's axes may run either way against the
-- map's (WoW's own run x north, y west), so both readings are tried and the
-- one the points agree on best is kept. Till there are points enough, a
-- zone's usual size stands in.
local GUESS_ACROSS, GUESS_DOWN = 3000, 2000

-- The points with both positions: { wx, wy, mx, my } each.
local function Points()
	local points = {}
	for _, list in pairs({ AZS_CHESTS or {}, AZS_LAIRS or {} }) do
		for index = 1, table.getn(list) do
			local entry = list[index]
			local mx, my = tonumber(entry.mx), tonumber(entry.my)
			local wx, wy = tonumber(entry.x), tonumber(entry.y)
			if mx and my and wx and wy then
				if mx > 1.5 or my > 1.5 then
					mx, my = mx / 100, my / 100
				end
				table.insert(points, { wx = wx, wy = wy, mx = mx, my = my })
			end
		end
	end
	return points
end

local function Median(list)
	local count = table.getn(list)
	if count == 0 then
		return nil
	end
	table.sort(list)
	return list[math.floor((count + 1) / 2)]
end

-- How far apart the estimates lie, against their middle: the smaller, the
-- better a reading fits.
local function Spread(list)
	local middle = Median(list)
	if not middle or middle == 0 then
		return 1000000
	end
	local total = 0
	for index = 1, table.getn(list) do
		total = total + math.abs(list[index] - middle)
	end
	return total / table.getn(list) / middle
end

local function ReadMapSpan()
	local points = Points()
	-- Each reading: world axis for the map's x, world axis for its y.
	local readings = { { "wy", "wx" }, { "wx", "wy" } }
	local best
	for _, reading in pairs(readings) do
		local across, down = {}, {}
		for a = 1, table.getn(points) do
			for b = a + 1, table.getn(points) do
				local p, q = points[a], points[b]
				local dmx, dmy = math.abs(p.mx - q.mx), math.abs(p.my - q.my)
				if dmx > 0.02 then
					table.insert(across, math.abs(p[reading[1]] - q[reading[1]]) / dmx)
				end
				if dmy > 0.02 then
					table.insert(down, math.abs(p[reading[2]] - q[reading[2]]) / dmy)
				end
			end
		end
		if table.getn(across) > 0 and table.getn(down) > 0 then
			local spread = Spread(across) + Spread(down)
			if not best or spread < best.spread then
				best = { spread = spread, across = Median(across), down = Median(down) }
			end
		end
	end
	if best and best.across > 0 and best.down > 0 then
		return best.across, best.down, true
	end
	return GUESS_ACROSS, GUESS_DOWN, false
end

-- The span, read again every few seconds rather than for every cache on
-- every frame: it takes every pair of points, and a fresh reading each frame
-- as the caches come and go also made the arrow shake.
local spanAcross, spanDown, spanLearned, spanAt

local function MapSpan()
	local now = GetTime()
	if not spanAt or now - spanAt >= REFRESH_EVERY then
		spanAt = now
		spanAcross, spanDown, spanLearned = ReadMapSpan()
	end
	return spanAcross, spanDown, spanLearned
end

-- Yards east and north from the hero to a map point.
local function Offset(cx, cy, px, py)
	local across, down = MapSpan()
	return (cx - px) * across, (py - cy) * down
end

-- The way the hero last moved, radians clockwise from north: where the game
-- gives no facing to read, a hero faces the way it moves. Read from where
-- the hero stood HEADING_WINDOW seconds ago to where it stands now, so a
-- turn shows within a step rather than after the old way has been walked
-- off; standing still (under HEADING_MIN yards in that time) keeps the last
-- heading.
local HEADING_WINDOW = 0.15     -- seconds of movement the heading is read over
local HEADING_MIN = 0.3         -- yards moved in that time before it counts
local trail = {}                -- { x, y, t, world } of the hero's position, oldest first
local heading

-- The hero's map position, or nil where the map gives none (0, 0: a zone
-- with no map, as Naxxramas). The map is set back to the hero's zone first,
-- unless the world map is open.
local function HeroMap()
	local px, py = GetPlayerMapPosition("player")
	if (not px or (px == 0 and py == 0)) and SetMapToCurrentZone and not (WorldMapFrame and WorldMapFrame:IsVisible()) then
		SetMapToCurrentZone()
		px, py = GetPlayerMapPosition("player")
	end
	if not px or (px == 0 and py == 0) then
		return nil
	end
	return px, py
end

-- The hero's world position, in yards, from the game's run line (AZS_RUN px
-- and py), or nil.
local function HeroWorld()
	local run = AZS_RUN or {}
	local px, py = tonumber(run.px), tonumber(run.py)
	if px and py then
		return px, py
	end
end

-- Yards east and north between two world positions. The world runs as WoW's
-- does: x to the north, y to the west.
local function WorldOffset(x, y, fromX, fromY)
	return fromY - y, x - fromX
end

local function MovementHeading()
	-- By the map where it gives a position, else by the world.
	local px, py = HeroMap()
	local world = false
	if not px then
		px, py = HeroWorld()
		world = true
	end
	if not px then
		return heading
	end
	local now = GetTime()
	if trail[1] and trail[1].world ~= world then
		trail = {}
	end
	table.insert(trail, { x = px, y = py, t = now, world = world })
	-- The oldest kept is the newest at least HEADING_WINDOW old.
	while table.getn(trail) > 2 and now - trail[2].t >= HEADING_WINDOW do
		table.remove(trail, 1)
	end
	local old = trail[1]
	local east, north
	if world then
		east, north = WorldOffset(px, py, old.x, old.y)
	else
		east, north = Offset(px, py, old.x, old.y)
	end
	if east * east + north * north >= HEADING_MIN * HEADING_MIN then
		heading = math.atan2(east, north)
	end
	return heading
end

-- A cache's key, by where it stands (its map or world position).
local function CacheKey(cx, cy)
	return string.format("%.3f:%.3f", cx, cy)
end

-- Each cache's place from the hero: { east, north, key } in yards, by the
-- map where both have a map position, else by the world (a zone whose map
-- gives none: the caches come with map -1, -1 there).
local function CacheOffsets()
	local found = {}
	local mapX, mapY = HeroMap()
	local worldX, worldY = HeroWorld()
	for index = 1, table.getn(AZS_CHESTS or {}) do
		local entry = AZS_CHESTS[index]
		local cx, cy = MapPoint(entry)
		if cx and cx >= 0 and cy >= 0 and mapX then
			local east, north = Offset(cx, cy, mapX, mapY)
			table.insert(found, { east = east, north = north, key = CacheKey(cx, cy) })
		else
			local wx, wy = tonumber(Field(entry, "x", 2)), tonumber(Field(entry, "y", 3))
			if wx and wy and worldX then
				local east, north = WorldOffset(wx, wy, worldX, worldY)
				table.insert(found, { east = east, north = north, key = CacheKey(wx, wy) })
			end
		end
	end
	return found
end

-- The cache the arrow keeps to, by where it stands.
local lockedKey

-- The cache to point at: its direction (radians clockwise from north) and
-- its distance in yards; nil without the hero's or any cache's position. The
-- one already pointed at, unless another is SWITCH_MARGIN yards nearer.
local function NearestCache()
	if not AZS_CHESTS or table.getn(AZS_CHESTS) == 0 then
		lockedKey = nil
		return nil
	end
	local near, locked
	local offsets = CacheOffsets()
	for index = 1, table.getn(offsets) do
		local found = offsets[index]
		found.yards = math.sqrt(found.east * found.east + found.north * found.north)
		if not near or found.yards < near.yards then
			near = found
		end
		if found.key == lockedKey then
			locked = found
		end
	end
	if not near then
		return nil
	end
	local target = near
	if locked and locked.yards - near.yards < SWITCH_MARGIN then
		target = locked
	end
	lockedKey = target.key
	-- Clockwise from north.
	return math.atan2(target.east, target.north), target.yards
end

------------------------------------------------------------------------------
-- The caches on the minimap: a small chest icon at each, placed from the
-- hero's position and the minimap's zoom (the minimap shows a fixed number of
-- yards across at each zoom, north up). A cache beyond the minimap's edge sits
-- on the edge, fainter, toward it. Shown whenever the game sends caches, the
-- gold or not; a switch in /sui opt.

-- A chest: the game's own box icon, its edges trimmed so its frame does not
-- show, with no border of its own.
local PIN_ICON = "Interface\\Icons\\INV_Box_02"
local PIN_SIZE = 11
-- The minimap draws the hero's arrow beneath anything set on it, so a pin
-- over the arrow (within PIN_UNDER pixels of the middle) fades to
-- PIN_UNDER_ALPHA, letting the arrow show through.
local PIN_UNDER = 9
local PIN_UNDER_ALPHA = 0.3
-- Yards across the minimap at each zoom level, outdoors.
local MINIMAP_YARDS = { [0] = 466.67, [1] = 400, [2] = 333.33, [3] = 266.67, [4] = 200, [5] = 133.33 }

local pins = {}

local function Pin(index)
	local pin = pins[index]
	if pin then
		return pin
	end
	pin = CreateFrame("Frame", nil, Minimap)
	pin:SetWidth(PIN_SIZE)
	pin:SetHeight(PIN_SIZE)
	pin:SetFrameLevel(Minimap:GetFrameLevel() + 6)
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetTexture(PIN_ICON)
	pin.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
	pin.icon:SetAllPoints(pin)
	pins[index] = pin
	return pin
end

local function HidePins(from)
	for index = from, table.getn(pins) do
		pins[index]:Hide()
	end
end

local function DrawPins()
	if not (Minimap and Settings().cachePins and AZS_CHESTS and table.getn(AZS_CHESTS) > 0) then
		HidePins(1)
		return
	end
	local across = MINIMAP_YARDS[Minimap:GetZoom()] or MINIMAP_YARDS[0]
	local half = Minimap:GetWidth() / 2
	local reach = half - PIN_SIZE / 2
	local shown = 0
	local offsets = CacheOffsets()
	for index = 1, table.getn(offsets) do
		do
			-- Yards east and north of the hero, then pixels on the minimap.
			local east, north = offsets[index].east, offsets[index].north
			local x = east / (across / 2) * half
			local y = north / (across / 2) * half
			local outside = math.abs(x) > reach or math.abs(y) > reach
			if outside then
				-- On the square's edge, along the way to it.
				local scale = reach / math.max(math.abs(x), math.abs(y))
				x, y = x * scale, y * scale
			end
			shown = shown + 1
			local pin = Pin(shown)
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", Minimap, "CENTER", x, y)
			local overArrow = math.abs(x) < PIN_UNDER and math.abs(y) < PIN_UNDER
			pin:SetAlpha(overArrow and PIN_UNDER_ALPHA or outside and 0.55 or 1)
			pin:Show()
		end
	end
	HidePins(shown + 1)
end

-- /sui caches: the numbers the arrow and the minimap's chests are made from,
-- to tell which of them is off: the hero's map position, the minimap's zoom
-- and the yards it reckons, the facing read, and each cache as the game sends
-- it (world x, y, z and map mx, my) with where the addon makes it.
function SurvivorUI_DebugCaches()
	local say = function(text) DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Survivor UI caches:|r "..text) end
	local px, py = GetPlayerMapPosition("player")
	say(string.format("hero map %.4f, %.4f in %s", px or -1, py or -1, (GetRealZoneText and GetRealZoneText()) or "?"))
	if Minimap then
		say(string.format("minimap zoom %d, %.0f px wide, %.1f yd across", Minimap:GetZoom(), Minimap:GetWidth(),
			MINIMAP_YARDS[Minimap:GetZoom()] or -1))
	end
	local facing = Facing()
	local across, down, learned = MapSpan()
	say("facing "..(facing and string.format("%.0f deg", math.deg(facing)) or "not found (the arrow points by the map)"))
	say(string.format("map spans %.0f yd across, %.0f yd down (%s, from %d points)", across, down,
		learned and "learned" or "a guess", table.getn(Points())))
	local list = AZS_CHESTS or {}
	say(table.getn(list).." caches sent")
	for index = 1, math.min(8, table.getn(list)) do
		local entry = list[index]
		local cx, cy = MapPoint(entry)
		local line = string.format("#%d  world %s, %s, %s  map %s, %s", index,
			tostring(Field(entry, "x", 2)), tostring(Field(entry, "y", 3)), tostring(Field(entry, "z", 4)),
			tostring(Field(entry, "mx", 5)), tostring(Field(entry, "my", 6)))
		if cx and px and px ~= 0 then
			local east, north = Offset(cx, cy, px, py)
			line = line..string.format("  ->  %.0f yd east, %.0f yd north, bearing %.0f deg",
				east, north, math.deg(math.atan2(east, north)))
		end
		say(line)
	end
	local lairs = AZS_LAIRS or {}
	say(table.getn(lairs).." lairs sent")
	for index = 1, math.min(6, table.getn(lairs)) do
		local entry = lairs[index]
		say(string.format("lair %s  world %s, %s  map %s, %s", tostring(entry.name or index),
			tostring(entry.x), tostring(entry.y), tostring(entry.mx), tostring(entry.my)))
	end
	-- Where the hero's own world position could come from, for a zone whose
	-- map gives none (Naxxramas): a call some clients have, and the fields of
	-- the game's zone, target and run feeds.
	if UnitPosition then
		local wx, wy = UnitPosition("player")
		say("UnitPosition: "..tostring(wx)..", "..tostring(wy))
	else
		say("UnitPosition: none in this client")
	end
	for _, feed in pairs({ { "AZS_ZONE", AZS_ZONE }, { "AZS_TARGET", AZS_TARGET }, { "AZS_RUN", AZS_RUN } }) do
		local fields = {}
		for key, value in pairs(feed[2] or {}) do
			table.insert(fields, tostring(key).."="..tostring(value))
		end
		table.sort(fields)
		say(feed[1]..": "..(table.getn(fields) > 0 and table.concat(fields, " ") or "empty"))
	end
end

local pinTicker = CreateFrame("Frame")
local pinElapsed = 0
pinTicker:SetScript("OnUpdate", function()
	pinElapsed = pinElapsed + arg1
	if pinElapsed >= 0.1 then
		pinElapsed = 0
		DrawPins()
	end
end)

-- Green through yellow to red as t runs from 0 to 1.
local function Ramp(t)
	t = math.max(0, math.min(1, t))
	if t < 0.5 then
		return t * 2, 1, 0.1
	end
	return 1, 1 - (t - 0.5) * 2, 0.1
end

-- The arrow's color: by the way the hero faces, green heading straight for
-- the cache, yellow side on, red heading away (offset: the cache's angle off
-- the hero's heading, -pi to pi); where no heading is known yet, by how far
-- the cache is.
local function ArrowColor(offset, yards)
	if offset then
		return Ramp(math.abs(offset) / math.pi)
	end
	return Ramp((yards - NEAR) / (FAR - NEAR))
end

-- The way to point and how far, read every AIM_EVERY seconds; the arrow
-- itself turns toward it every frame. Every REFRESH_EVERY seconds the map is
-- set back to the hero's zone (the world map can leave it on another), so the
-- arrow keeps up even while the hero stands still.
local aimAngle, aimYards
local aimOffset                 -- the cache's angle off the hero's heading, for the color
local shownAngle

-- An angle brought into -pi to pi.
local function Wrap(angle)
	return angle - 2 * math.pi * math.floor((angle + math.pi) / (2 * math.pi))
end
local aimElapsed, refreshElapsed = AIM_EVERY, 0

local function Aim()
	local bearing, yards = NearestCache()
	if not bearing then
		aimAngle, aimYards, aimOffset = nil, nil, nil
		return
	end
	-- The cache's angle off the way the hero faces, whichever way the arrow
	-- points: it colors the arrow either way.
	local offset
	local facing = Facing()
	if facing then
		-- Facing turns counterclockwise; the hero's heading clockwise is its negative.
		offset = Wrap(bearing + facing)
	else
		-- No facing to read: the way the hero last moved stands in for it.
		local heading = MovementHeading()
		if heading then
			offset = Wrap(bearing - heading)
		end
	end
	local angle = bearing
	if not Settings().cacheArrowByMap and offset then
		angle = offset
	end
	aimAngle, aimYards, aimOffset = angle, yards, offset
end

local function DrawArrow(preview, elapsed)
	if not Settings().cacheArrow then
		arrowFrame:Hide()
		return
	end
	refreshElapsed = refreshElapsed + elapsed
	if refreshElapsed >= REFRESH_EVERY then
		refreshElapsed = 0
		local mapOpen = WorldMapFrame and WorldMapFrame:IsVisible()
		if SetMapToCurrentZone and not mapOpen then
			SetMapToCurrentZone()
		end
		aimElapsed = AIM_EVERY
	end
	aimElapsed = aimElapsed + elapsed
	if aimElapsed >= AIM_EVERY then
		aimElapsed = 0
		Aim()
	end
	if not aimAngle then
		shownAngle = nil
		if preview then
			-- Somewhere to place it from: pointing up, in grey.
			Turn(0)
			arrow:SetVertexColor(0.6, 0.6, 0.6)
			distance:SetText("|cff9a9a9a-- yd|r")
			arrowFrame:Show()
		else
			arrowFrame:Hide()
		end
		return
	end
	-- The shorter way round toward the bearing, eased: quick for a big turn,
	-- gentle as it closes in.
	if not shownAngle then
		shownAngle = Wrap(aimAngle)
	else
		local turn = Wrap(aimAngle - shownAngle)
		shownAngle = Wrap(shownAngle + turn * (1 - math.exp(-elapsed * TURN_RATE)))
	end
	Turn(shownAngle)
	local r, g, b = ArrowColor(aimOffset, aimYards)
	arrow:SetVertexColor(r, g, b)
	distance:SetText(math.floor(aimYards + 0.5).." yd")
	distance:SetTextColor(r, g, b)
	arrowFrame:Show()
end

local shownFor = 0              -- seconds the text has been up
local checked = 0

holder:SetScript("OnUpdate", function()
	checked = checked + arg1
	if checked >= 0.2 then
		checked = 0
		-- In preview (before the first step, or in edit mode) it shows anyway,
		-- so it can be placed and sized.
		local wanted = Settings().cacheReminder
			and (Affordable() or (SurvivorUI_Preview and SurvivorUI_Preview()))
		if wanted then
			ShowRatio()
		end
		if wanted and not inner:IsShown() then
			shownFor = 0
			inner:SetAlpha(0)
			box:SetAlpha(0)
			inner:Show()
			box:Show()
		elseif not wanted and inner:IsShown() then
			inner:Hide()
			box:Hide()
			arrowFrame:Hide()
		end
	end
	if not inner:IsShown() then
		return
	end
	-- The arrow follows every frame, so it turns smoothly with the hero.
	DrawArrow(not Affordable(), arg1)
	-- Fades in (eased, so it neither pops nor stops short), then breathes:
	-- down to PULSE_LOW and back to full, starting from full.
	shownFor = shownFor + arg1
	if shownFor < FADE_IN then
		local t = shownFor / FADE_IN
		inner:SetAlpha(t * t * (3 - 2 * t))
		box:SetAlpha(t * t * (3 - 2 * t))
	else
		box:SetAlpha(1)
		local phase = math.mod(shownFor - FADE_IN, PULSE) / PULSE
		local breath = 0.5 + 0.5 * math.cos(phase * 6.2832)
		inner:SetAlpha(PULSE_LOW + (1 - PULSE_LOW) * breath)
	end
end)

------------------------------------------------------------------------------
-- Its switch, its size, and its handle.

if SurvivorUI_RegisterOption then
	SurvivorUI_RegisterOption({
		section = "General",
		label = "Next Cache Reminder",
		tip = "\""..TEXT.."\" in large letters over the middle of the screen while your gold covers the next cache.",
		get = function() return Settings().cacheReminder end,
		toggle = function()
			local settings = Settings()
			settings.cacheReminder = not settings.cacheReminder
		end,
	})
	SurvivorUI_RegisterOption({
		section = "General",
		kind = "slider",
		label = "Next Cache Reminder size",
		parent = "Next Cache Reminder",
		tip = "The size of the reminder's letters.",
		min = SIZE_MIN,
		max = SIZE_MAX,
		step = 1,
		get = TextSize,
		set = function(size)
			Settings().cacheReminderSize = size
			ApplySize()
		end,
	})
	SurvivorUI_RegisterOption({
		section = "Interface",
		label = "Caches on the minimap",
		tip = "A chest icon on the minimap at every cache the game knows of; one past the minimap's edge sits on the edge, fainter, toward it.",
		get = function() return Settings().cachePins end,
		toggle = function()
			local settings = Settings()
			settings.cachePins = not settings.cachePins
		end,
	})
	SurvivorUI_RegisterOption({
		section = "General",
		label = "Reminder text",
		parent = "Next Cache Reminder",
		tip = "The words \"Can Afford Next Cache!\". Off, only your gold against the price shows (\"505 / 20\"), in their place and size.",
		get = TextShown,
		toggle = function()
			Settings().cacheReminderText = not TextShown()
			ApplySize()
		end,
	})
	SurvivorUI_RegisterOption({
		section = "General",
		label = "Cache arrow",
		parent = "Next Cache Reminder",
		tip = "An arrow over the reminder pointing to the nearest cache, with the distance under it: green when near, red when far. It keeps to one cache until another is "..SWITCH_MARGIN.." yards nearer.",
		get = function() return Settings().cacheArrow end,
		toggle = function()
			local settings = Settings()
			settings.cacheArrow = not settings.cacheArrow
		end,
	})
	SurvivorUI_RegisterOption({
		section = "General",
		kind = "slider",
		label = "Cache arrow size",
		parent = "Next Cache Reminder",
		tip = "The size of the arrow to the nearest cache, in pixels.",
		min = ARROW_MIN,
		max = ARROW_MAX,
		step = 2,
		get = ArrowSize,
		set = function(size)
			Settings().cacheArrowSize = size
			ApplyArrowSize()
		end,
	})
	SurvivorUI_RegisterOption({
		section = "General",
		label = "Arrow points by the map",
		parent = "Next Cache Reminder",
		tip = "On (the default), the arrow points with north up, which suits the game's camera, as it never turns. Off, it points relative to the way your hero faces, as TomTom's does (taken from the way you last moved, as the game shares no facing).",
		get = function() return Settings().cacheArrowByMap end,
		toggle = function()
			local settings = Settings()
			settings.cacheArrowByMap = not settings.cacheArrowByMap
		end,
	})
end

if SurvivorUI_RegisterMover then
	SurvivorUI_RegisterMover(holder, "Cache reminder", SavePlace, nil, RestorePlace)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function()
	ApplySize()
	RestorePlace()
end)
