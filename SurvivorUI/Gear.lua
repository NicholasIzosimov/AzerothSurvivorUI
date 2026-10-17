-- Survivor UI: the worn gear, as the game describes it and as the Codex
-- fills it in. Moved out of SurvivorUI.lua, whose main body reached the 200
-- locals Lua allows one function.
--
-- What is here: the watch over the worn slots (a piece the game has not
-- described is asked for again), the log of slot changes and /sui gear, the
-- one shared reader of worn tooltips (SurvivorUI_WornTooltip), the Codex's
-- guess for a blank slot (SurvivorUI_SlotGuess, shown in the build and the
-- character pane), and /sui logwatch.

local FLAT = "Interface\ChatFrame\ChatFrameBackground"

------------------------------------------------------------------------------
-- Worn gear the interface cannot name yet: the game hands the interface an
-- item's details only when asked. After a reload some worn pieces are not
-- there yet when the character pane and the build first draw; and a piece
-- that ranks up becomes a new item (each rank has its own), unknown until
-- asked for. Either way its slot stands empty. So every GEAR_CHECK seconds,
-- all the time, a slot that holds a piece the interface cannot name is asked
-- for again through a hidden tooltip, and the character pane's slots are
-- drawn again once one comes back. Nothing is asked while every worn piece is
-- known, and only the hero's own slots are ever asked for.

local GEAR_CHECK = 5            -- seconds between looks at the worn slots
local GEAR_SLOTS = {
	"Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands",
	"Finger0", "Finger1", "Trinket0", "Trinket1", "Back", "MainHand", "SecondaryHand", "Ranged", "Tabard",
}

local gearScan = CreateFrame("GameTooltip", "SurvivorUIGearScan", nil, "GameTooltipTemplate")
local gearWatch = CreateFrame("Frame")
local gearElapsed = 0
local gearMissing = {}          -- [slot] = true while it holds a piece the interface cannot name

local function RedrawGearSlots()
	if not PaperDollItemSlotButton_Update then
		return
	end
	local saved = this
	for index = 1, table.getn(GEAR_SLOTS) do
		local button = getglobal("Character"..GEAR_SLOTS[index].."Slot")
		if button then
			this = button
			pcall(PaperDollItemSlotButton_Update)
		end
	end
	this = saved
end

-- A log of the worn slots, for /sui gear: every time a slot's piece goes
-- from named to unnamed or back, or changes, with the last event before it.
-- Kept in the saved variables (the last GEAR_LOG_KEPT), so a loss at a
-- reload is in it too.
local GEAR_LOG_KEPT = 30
local lastGearEvent = "start"

-- Each slot's link at the last look (false for none), kept in the run's
-- memory: after a reload the first look compares with the run's last one,
-- so a piece lost at the reload is logged too.
local function GearLinks()
	if SurvivorUI_RunMemory then
		local memory = SurvivorUI_RunMemory("gear")
		memory.links = memory.links or {}
		return memory.links
	end
	return {}
end

-- Each slot's last named piece this run, kept with the links: a slot that
-- goes blank (the game never sent its new piece) is guessed from it.
local function GearNames()
	if SurvivorUI_RunMemory then
		local memory = SurvivorUI_RunMemory("gear")
		memory.names = memory.names or {}
		return memory.names
	end
	return {}
end

local function GearLog()
	SurvivorUIDB = SurvivorUIDB or {}
	SurvivorUIDB.gearLog = SurvivorUIDB.gearLog or {}
	return SurvivorUIDB.gearLog
end

local function ItemName(link)
	local _, _, name = string.find(link or "", "%[(.-)%]")
	return name
end

local function NoteGear(slot, link)
	local gearLinks = GearLinks()
	local before = gearLinks[slot]
	gearLinks[slot] = link or false
	if before == nil or before == (link or false) then
		return
	end
	local log = GearLog()
	table.insert(log, {
		at = date and date("%H:%M:%S") or "?",
		slot = slot,
		from = before and ItemName(before) or "-",
		to = link and ItemName(link) or "-",
		after = lastGearEvent,
	})
	while table.getn(log) > GEAR_LOG_KEPT do
		table.remove(log, 1)
	end
end

-- A change of gear or a new world is looked at right away.
gearWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
gearWatch:RegisterEvent("UNIT_INVENTORY_CHANGED")
gearWatch:SetScript("OnEvent", function()
	if event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then
		return
	end
	if SurvivorUI_ForgetWornTooltips then
		SurvivorUI_ForgetWornTooltips()
	end
	lastGearEvent = (event == "PLAYER_ENTERING_WORLD" and "entering the world (a reload)" or "a gear change")
		.." at "..(date and date("%H:%M:%S") or "?")
	gearElapsed = GEAR_CHECK
end)
gearWatch:SetScript("OnUpdate", function()
	gearElapsed = gearElapsed + arg1
	if gearElapsed < GEAR_CHECK then
		return
	end
	gearElapsed = 0
	-- A slot whose piece comes back, or goes blank, is drawn again: the
	-- character pane then shows the game's piece, or the Codex's guess.
	local changed = false
	for slot = 1, table.getn(GEAR_SLOTS) do
		local link = GetInventoryItemLink("player", slot)
		NoteGear(slot, link)
		if link then
			GearNames()[slot] = ItemName(link)
			if gearMissing[slot] then
				gearMissing[slot] = nil
				changed = true
			end
		else
			gearScan:SetOwner(WorldFrame, "ANCHOR_NONE")
			gearScan:ClearLines()
			-- True when the slot holds a piece: asked for, it comes in later.
			-- An empty slot answers false and asks nothing.
			local holds = gearScan:SetInventoryItem("player", slot) and true or nil
			if holds ~= gearMissing[slot] then
				changed = true
			end
			gearMissing[slot] = holds
		end
	end
	if changed then
		RedrawGearSlots()
	end
end)

-- Whether a slot holds a piece the game has not described to the interface
-- (no name, no icon, an empty tooltip), as of the last look: the piece is
-- worn and works, the interface just cannot show it.
function SurvivorUI_SlotUnloaded(slot)
	return gearMissing[slot] == true
end

------------------------------------------------------------------------------
-- A blank slot filled in from the Codex. When the game never sends a worn
-- piece's details, the slot is guessed from the piece it held before: a ring
-- or trinket only ranks up during a run, so it is that piece one rank higher;
-- a neck may have been swapped for another amulet, so its guess is always
-- marked unreliable, as is any guess whose rank the Codex has no description
-- of. The game's own piece always wins: a guess exists only while the slot
-- has no piece the game has described.

local GUESS_KINDS = { [2] = "Neck", [11] = "Ring", [12] = "Ring", [13] = "Trinket", [14] = "Trinket" }
local NUMERALS = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

-- { name, icon, hex, lines, unreliable }, or nil.
function SurvivorUI_SlotGuess(slot)
	if GetInventoryItemLink("player", slot) or not gearMissing[slot] then
		return nil
	end
	local kind = GUESS_KINDS[slot]
	local before = GearNames()[slot]
	if not (kind and before and SurvivorUI_BaseName) then
		return nil
	end
	local base, rank = SurvivorUI_BaseName(before)
	rank = math.floor(rank)
	-- The next rank's names as the game writes them: past IX it may be "X"
	-- or "X+".
	local names = {}
	if rank >= 10 then
		names = { base.." X+" }
	elseif rank == 9 then
		names = { base.." X", base.." X+" }
	else
		names = { base.." "..NUMERALS[rank + 1] }
	end
	local book = SurvivorUIDB and SurvivorUIDB.codex and SurvivorUIDB.codex[kind] or {}
	local exact, exactName
	for index = 1, table.getn(names) do
		if not exact and book[names[index]] then
			exact, exactName = book[names[index]], names[index]
		end
	end
	-- Its icon and color from any rank, every rank of a piece looks alike;
	-- with no description of this rank, the nearest rank's that is kept (the
	-- highest at or under it, else the lowest above), its numbers that rank's.
	local any, near, nearRank, nearName
	for name, info in pairs(book) do
		local otherBase, otherRank = SurvivorUI_BaseName(name)
		if otherBase == base then
			if not any or (info.icon and not any.icon) then
				any = info
			end
			if info.lines and table.getn(info.lines) > 1 then
				local better = not near
					or (otherRank <= rank + 1 and (nearRank > rank + 1 or otherRank > nearRank))
					or (otherRank > rank + 1 and nearRank > rank + 1 and otherRank < nearRank)
				if better then
					near, nearRank, nearName = info, otherRank, name
				end
			end
		end
	end
	local lines = exact and exact.lines
	local whole = lines and table.getn(lines) > 1
	return {
		name = exactName or names[1],
		icon = (exact and exact.icon) or (any and any.icon),
		hex = (exact and exact.hex) or (any and any.hex),
		lines = whole and lines or (near and near.lines) or nil,
		linesFrom = not whole and near and nearName or nil,
		unreliable = kind == "Neck" or not whole,
		before = before,
	}
end

-- A guess's tooltip, for the build and the character pane: its kept
-- description (or its name), and a note saying where it comes from.
function SurvivorUI_GuessTooltip(owner, guess)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local hex = guess.hex or "ffffffff"
	local r = (tonumber(string.sub(hex, 3, 4), 16) or 255) / 255
	local g = (tonumber(string.sub(hex, 5, 6), 16) or 255) / 255
	local b = (tonumber(string.sub(hex, 7, 8), 16) or 255) / 255
	local title = guess.name..(guess.unreliable and " (Unreliable)" or "")
	if guess.lines then
		for index = 1, table.getn(guess.lines) do
			local line = guess.lines[index]
			if index == 1 then
				GameTooltip:SetText(title, line[2], line[3], line[4])
			elseif line[5] then
				GameTooltip:AddDoubleLine(line[1], line[5], line[2], line[3], line[4], line[2], line[3], line[4])
			else
				GameTooltip:AddLine(line[1], line[2], line[3], line[4], 1)
			end
		end
	else
		GameTooltip:SetText(title, r, g, b)
	end
	GameTooltip:AddLine("From the Codex: the game has not sent this piece's details. "
		..(guess.unreliable and "Unreliable: guessed from "..guess.before.." worn before it." or "It is "
		..guess.before.." ranked up.")
		..(guess.linesFrom and " Description of "..guess.linesFrom..", its numbers that rank's." or ""),
		0.6, 0.6, 0.6, 1)
	GameTooltip:Show()
end

-- The character pane's slots: a blank one shows the guess's icon, and its
-- tooltip; a slot the game has described is left wholly to the game.
local stockSlotUpdate = PaperDollItemSlotButton_Update
if stockSlotUpdate then
	function PaperDollItemSlotButton_Update()
		stockSlotUpdate()
		local guess = this and this.GetID and SurvivorUI_SlotGuess(this:GetID())
		this.survivorGuess = guess
		if guess and guess.icon and SetItemButtonTexture then
			SetItemButtonTexture(this, guess.icon)
		end
	end
end

local stockSlotEnter = PaperDollItemSlotButton_OnEnter
if stockSlotEnter then
	function PaperDollItemSlotButton_OnEnter()
		stockSlotEnter()
		if this.survivorGuess and not GetInventoryItemLink("player", this:GetID()) then
			SurvivorUI_GuessTooltip(this, this.survivorGuess)
		end
	end
end

-- A worn piece's tooltip, read once and kept with its link: every part of
-- the addon that wants it (the build's gear and spell cards, the Codex) asks
-- here instead of reading the slot itself, so a slot is read when its piece
-- changes rather than many times a second. A tooltip the game had not yet
-- sent in full (the name alone) is read again every WORN_RETRY seconds until
-- it is. Lines are { text, r, g, b, right text }.
-- The game reuses an item's id for another copy of it (another rank, or the
-- same rank with other numbers), so the same link can stand for a new piece:
-- every change of gear forgets what was kept (SurvivorUI_ForgetWornTooltips).
local WORN_RETRY = 5
local wornTooltips = {}         -- [slot] = { link, lines, at }

function SurvivorUI_ForgetWornTooltips()
	wornTooltips = {}
end

function SurvivorUI_WornTooltip(slot)
	local link = GetInventoryItemLink("player", slot)
	if not link then
		wornTooltips[slot] = nil
		return nil
	end
	local kept = wornTooltips[slot]
	if kept and kept.link == link and (table.getn(kept.lines) > 1 or GetTime() - kept.at < WORN_RETRY) then
		return kept.lines
	end
	gearScan:SetOwner(WorldFrame, "ANCHOR_NONE")
	gearScan:ClearLines()
	gearScan:SetInventoryItem("player", slot)
	local lines = {}
	for index = 1, gearScan:NumLines() do
		local left = getglobal("SurvivorUIGearScanTextLeft"..index)
		local right = getglobal("SurvivorUIGearScanTextRight"..index)
		local text = left and left:GetText()
		if text then
			local r, g, b = left:GetTextColor()
			table.insert(lines, { text, r, g, b, right and right:IsShown() and right:GetText() or nil })
		end
	end
	wornTooltips[slot] = { link = link, lines = lines, at = GetTime() }
	return lines
end

-- /sui gear: how the game sees each jewelry slot now (the piece's name, its
-- icon, whether the slot holds something), and the log of slots that lost or
-- regained their piece, the newest last.
local JEWELRY_SLOTS = { 2, 11, 12, 13, 14 }

function SurvivorUI_GearReport()
	local say = function(text) DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Survivor UI gear:|r "..text) end
	for index = 1, table.getn(JEWELRY_SLOTS) do
		local slot = JEWELRY_SLOTS[index]
		local link = GetInventoryItemLink("player", slot)
		local texture = GetInventoryItemTexture("player", slot)
		gearScan:SetOwner(WorldFrame, "ANCHOR_NONE")
		gearScan:ClearLines()
		local holds = gearScan:SetInventoryItem("player", slot)
		local first = getglobal("SurvivorUIGearScanTextLeft1")
		first = first and first:GetText()
		say(GEAR_SLOTS[slot].." ("..slot.."): name "..(ItemName(link) or "|cffff6060none|r")
			..", icon "..(texture and "yes" or "|cffff6060no|r")
			..", holds "..(holds and "yes" or "|cffff6060no|r")
			..", tooltip "..(first or "|cffff6060empty|r")
			..(gearMissing[slot] and ", |cffffd24dasked for again|r" or ""))
	end
	local log = GearLog()
	if table.getn(log) == 0 then
		say("no slot has lost or regained its piece yet.")
		return
	end
	say("changes, newest last:")
	for index = math.max(1, table.getn(log) - 11), table.getn(log) do
		local entry = log[index]
		say("  "..entry.at.."  "..(GEAR_SLOTS[entry.slot] or entry.slot)..": "..entry.from.." -> "..entry.to
			.."  (after "..entry.after..")")
	end
end

------------------------------------------------------------------------------
-- /sui logwatch words: for a minute, every message the game sends the
-- interface whose text holds those words is printed with its event, so a
-- piece the addon cannot read yet (a proc whose hits the damage card never
-- sees) shows how the game words it.

local LOGWATCH_TIME = 60
local LOGWATCH_MAX = 15

local logWatch = CreateFrame("Frame")
local logWords, logUntil, logShown

logWatch:SetScript("OnEvent", function()
	if not logWords then
		return
	end
	if GetTime() > logUntil or logShown >= LOGWATCH_MAX then
		this:UnregisterAllEvents()
		DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Survivor UI logwatch:|r done ("..logShown.." found).")
		logWords = nil
		return
	end
	for _, value in pairs({ arg1, arg2, arg3, arg4, arg5 }) do
		if type(value) == "string" and string.find(string.lower(value), logWords, 1, true) then
			logShown = logShown + 1
			DEFAULT_CHAT_FRAME:AddMessage("|cffffd100"..event..":|r "..string.sub(value, 1, 200))
			return
		end
	end
end)

function SurvivorUI_LogWatch(words)
	logWords, logUntil, logShown = string.lower(words), GetTime() + LOGWATCH_TIME, 0
	logWatch:RegisterAllEvents()
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Survivor UI logwatch:|r for "..LOGWATCH_TIME.." sec, every game message holding \""
		..words.."\" is printed here (at most "..LOGWATCH_MAX..").")
end
