-- Core.lua : EPGP data, JSON import/export, roster, events
SkullEPGP = {}
local X = SkullEPGP
local J = SkullEPGP_Json

X.VERSION = "1.2.0"
X.PREFIX = "SKULLEPGP"                     -- addon message prefix (officer -> players protocol)
X.TIERS = { MAX = 4, NEED = 3, MIN = 2, ROLL = 1 }
X.QUALITIES = {                          -- item quality names / colours (index = quality id)
	[0] = { "Poor", "|cff9d9d9d" }, [1] = { "Common", "|cffffffff" }, [2] = { "Uncommon", "|cff1eff00" },
	[3] = { "Rare", "|cff0070dd" }, [4] = { "Epic", "|cffa335ee" }, [5] = { "Legendary", "|cffff8000" },
}
function X:QualityLabel(q)
	local e = self.QUALITIES[q] or self.QUALITIES[4]
	return e[2] .. e[1] .. "|r"
end
X.COUNTDOWN_MARKS = { 10, 2, 1 } -- seconds left at which a reminder is posted in raid chat (10 = text, the rest = bare number)

X.lootItems = {}
X.roster = {}                            -- [lowercase name] = name
X.rosterCount = 0

local DEFAULTS = {
	duration = 30,
	minGP = 1,                           -- minimum denominator, avoids dividing by 0
	rev = 0,                             -- revision counter of the players data (officer sync)
	cfgRev = 0,                          -- revision of costs / base GP
	baseGP = 0,                          -- PR = EP / (GP + baseGP)  (the Google Sheet uses 10)
	minQuality = 4,                      -- minimum quality of listed items (4 = epic)
	autoLoot = true,                     -- auto-loot items below minQuality (except bind-on-pickup) when master looter
	autoOpen = true,
	costs = { MIN = 5, NEED = 15, MAX = 45 },
	players = {},
	log = {},
	logStart = 1,
	classes = {},
	nextId = 0,
	minimapAngle = 200,
	minimapHidden = false,
	disabled = false,                    -- addon switched off by hand (minimap button right-click, /epgp off)
	trades = {},                         -- awarded items waiting for the trade (GP applied when it is done)
	pending = {},                        -- items taken into the master looter's bags, not distributed yet
}

local function copyDefaults(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			if type(v) == "table" then
				dst[k] = {}
				copyDefaults(dst[k], v)
			else
				dst[k] = v
			end
		elseif type(v) == "table" and type(dst[k]) == "table" then
			copyDefaults(dst[k], v)
		end
	end
end

function X:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff49C0C0[SkullEPGP]|r " .. tostring(msg))
end

function X:Round(n, d)
	local m = 10 ^ (d or 0)
	return math.floor(n * m + 0.5) / m
end

local function trim(s)
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	return s
end
X.Trim = trim

-------------------------------------------------------------------------------
-- Database
-------------------------------------------------------------------------------
function X:InitDB()
	SkullEPGP_DB = SkullEPGP_DB or {}
	self.db = SkullEPGP_DB
	copyDefaults(self.db, DEFAULTS)
	self:RebuildIndex()
end

function X:RebuildIndex()
	self.index = {}
	for main, d in pairs(self.db.players) do
		self.index[string.lower(main)] = main
		if d.alts then
			for i = 1, table.getn(d.alts) do
				self.index[string.lower(d.alts[i])] = main
			end
		end
	end
end

-- Returns the "main" name (table key) for a character name (main or alt)
function X:FindMain(name)
	if not name or not self.index then return nil end
	return self.index[string.lower(name)]
end

function X:GetPR(main)
	local d = self.db.players[main]
	if not d then return 0 end
	local gp = d.gp + (self.db.baseGP or 0)
	if gp < self.db.minGP then gp = self.db.minGP end
	return d.ep / gp
end

function X:PlayerName(main)
	local d = self.db.players[main]
	if d and d.alts and table.getn(d.alts) > 0 then
		return main .. "/" .. table.concat(d.alts, "/")
	end
	return main
end

-------------------------------------------------------------------------------
-- Log
-------------------------------------------------------------------------------
function X:AddLog(entry)
	entry.t = entry.t or date("%Y-%m-%d %H:%M:%S")
	table.insert(self.db.log, entry)
	local max = 1000
	local n = table.getn(self.db.log)
	if n > max then
		local remove = n - max
		for i = 1, remove do table.remove(self.db.log, 1) end
		self.db.logStart = self.db.logStart - remove
		if self.db.logStart < 1 then self.db.logStart = 1 end
	end
	if self.UI then self.UI:RefreshLog() end
	self:SendLog(entry)
end

local function itemInfo(link)
	if not link then return nil, nil end
	local _, _, id = string.find(link, "|Hitem:(%d+):")
	local _, _, name = string.find(link, "%[(.-)%]")
	return name, tonumber(id)
end
X.ItemInfo = itemInfo

-------------------------------------------------------------------------------
-- Editing values
-------------------------------------------------------------------------------
function X:SetPlayer(name, ep, gp)
	local main = self:FindMain(name) or name
	local d = self.db.players[main]
	if not d then
		d = { ep = 0, gp = 0 }
		self.db.players[main] = d
	end
	d.ep = ep
	d.gp = gp
	self:RebuildIndex()
	self:Touch(main)
	self:Publish(nil, main)
	self:AddLog({ type = "SET", player = main, ep = ep, gp = gp })
	return main
end

function X:AddEP(name, delta)
	local main = self:FindMain(name)
	if not main then return nil end
	local d = self.db.players[main]
	d.ep = d.ep + delta
	self:Touch(main)
	self:Publish(nil, main)
	self:AddLog({ type = "EP", player = main, ep = delta })
	return main, d.ep
end

function X:AddGP(name, delta, reason)
	local main = self:FindMain(name)
	if not main then return nil end
	local d = self.db.players[main]
	d.gp = d.gp + delta
	self:Touch(main)
	self:Publish(nil, main)
	self:AddLog({ type = "GP", player = main, gp = delta, reason = reason })
	return main, d.gp
end

function X:RemovePlayer(name)
	local main = self:FindMain(name)
	if not main then return nil end
	self.db.players[main] = nil
	self:RebuildIndex()
	self:TouchRemoved(main)
	self:AddLog({ type = "REMOVE", player = main })
	return main
end

-- EP to the whole raid (once per "main", even if several of their characters are present)
function X:AwardRaidEP(amount)
	if self.rosterCount == 0 then
		self:Print("You are not in a group/raid.")
		return 0
	end
	local seen, count, missing = {}, 0, {}
	for lname, name in pairs(self.roster) do
		local main = self:FindMain(name)
		if main then
			if not seen[main] then
				seen[main] = true
				self.db.players[main].ep = self.db.players[main].ep + amount
				self:Touch(main)
				count = count + 1
			end
		else
			table.insert(missing, name)
		end
	end
	self:Publish()
	self:AddLog({ type = "RAIDEP", ep = amount, count = count })
	self:Print(string.format("%+d EP awarded to %d player(s).", amount, count))
	if table.getn(missing) > 0 then
		table.sort(missing)
		self:Print("|cffff8080Not on the EPGP list (not credited):|r " .. table.concat(missing, ", "))
	end
	return count
end

-------------------------------------------------------------------------------
-- Import JSON
-------------------------------------------------------------------------------
local function pick(t, keys)
	for i = 1, table.getn(keys) do
		local v = t[keys[i]]
		if v ~= nil then return v end
	end
	return nil
end

local function splitNames(s)
	local out = {}
	for part in string.gfind(s, "[^/,;]+") do
		part = trim(part)
		if part ~= "" then table.insert(out, part) end
	end
	return out
end

local function makeEntry(fallbackName, item)
	if type(item) ~= "table" then return nil end
	local name = pick(item, { "name", "Name", "player", "Player", "joueur", "Joueur" }) or fallbackName
	local ep, gp
	if item.ep ~= nil or item.EP ~= nil or item.Ep ~= nil then
		ep = tonumber(pick(item, { "ep", "EP", "Ep" }))
		gp = tonumber(pick(item, { "gp", "GP", "Gp" }))
	else
		ep, gp = tonumber(item[1]), tonumber(item[2])
	end
	if type(name) ~= "string" or not ep or not gp then return nil end
	local names = splitNames(name)          -- also accepts "Main/Alt1/Alt2"
	if table.getn(names) == 0 then return nil end
	local alts = {}
	for i = 2, table.getn(names) do table.insert(alts, names[i]) end
	local a = pick(item, { "alts", "Alts", "alt", "Alt" })
	if type(a) == "string" then
		a = splitNames(a)
	end
	if type(a) == "table" then
		for i = 1, table.getn(a) do
			if type(a[i]) == "string" and trim(a[i]) ~= "" then table.insert(alts, trim(a[i])) end
		end
	end
	return { name = names[1], ep = ep, gp = gp, alts = alts }
end

-- Returns (list, costs, skipped) or (nil, error)
function X:ParseImport(text)
	text = trim(text or "")
	if text == "" then return nil, "empty field" end
	local ok, data = pcall(J.Decode, text)
	if not ok then return nil, "Invalid JSON: " .. tostring(data) end
	if type(data) ~= "table" then return nil, "unexpected format" end

	local src, costs = data, nil
	if data.players ~= nil then
		src = data.players
		costs = data.costs
	end
	if type(src) ~= "table" then return nil, "'players' must be a list or an object" end

	local list, skipped = {}, 0
	if table.getn(src) > 0 then
		for i = 1, table.getn(src) do
			local e = makeEntry(nil, src[i])
			if e then table.insert(list, e) else skipped = skipped + 1 end
		end
	else
		for k, v in pairs(src) do
			if type(v) == "table" then
				local e = makeEntry(k, v)
				if e then table.insert(list, e) else skipped = skipped + 1 end
			end
		end
	end
	if table.getn(list) == 0 then return nil, "no valid player found" end
	list.baseGP = tonumber(data.baseGP)     -- optional: PR = EP / (GP + baseGP)
	return list, costs, skipped
end

-- mode: "replace" (replaces everything) or "merge" (updates the players present in the JSON)
function X:ApplyImport(list, costs, mode)
	if mode == "replace" then self.db.players = {} end
	self:RebuildIndex()
	for i = 1, table.getn(list) do
		local e = list[i]
		local main = (mode == "merge") and self:FindMain(e.name) or e.name
		local d = self.db.players[main]
		if not d then
			d = {}
			self.db.players[main] = d
		end
		d.ep, d.gp = e.ep, e.gp
		if table.getn(e.alts) > 0 or mode == "replace" then d.alts = e.alts end
		self:RebuildIndex()
	end
	if type(costs) == "table" then
		for _, k in ipairs({ "MIN", "NEED", "MAX" }) do
			local v = tonumber(costs[k])
			if v and v > 0 then self.db.costs[k] = v end
		end
	end
	if list.baseGP and list.baseGP >= 0 then self.db.baseGP = list.baseGP end
	-- The Google Doc is the new reference: the exported log starts from scratch
	self.db.lastImport = date("%Y-%m-%d %H:%M:%S")
	self:SyncAfterImport(mode == "replace")
	self:Publish()                      -- the player addons get their new priorities
	self:AddLog({ type = "IMPORT", count = table.getn(list), reason = mode })
	self.db.logStart = table.getn(self.db.log) + 1
	return table.getn(list)
end

-------------------------------------------------------------------------------
-- Export JSON
-------------------------------------------------------------------------------
function X:SortedPlayers()
	local list = {}
	for main, d in pairs(self.db.players) do
		table.insert(list, { name = main, ep = d.ep, gp = d.gp, pr = self:GetPR(main), alts = d.alts })
	end
	table.sort(list, function(a, b)
		if a.pr ~= b.pr then return a.pr > b.pr end
		return a.name < b.name
	end)
	return list
end

function X:Export()
	local players = {}
	for _, p in ipairs(self:SortedPlayers()) do
		local o = { name = p.name, ep = self:Round(p.ep, 2), gp = self:Round(p.gp, 2), pr = self:Round(p.pr, 4) }
		if p.alts and table.getn(p.alts) > 0 then o.alts = p.alts end
		table.insert(players, o)
	end
	local log = {}
	for i = self.db.logStart, table.getn(self.db.log) do
		local e = self.db.log[i]
		local o = {}
		for k, v in pairs(e) do
			if k ~= "link" then o[k] = v end
		end
		table.insert(log, o)
	end
	local out = {
		version = 1,
		exported = date("%Y-%m-%d %H:%M:%S"),
		costs = self.db.costs,
		baseGP = self.db.baseGP or 0,
		players = players,
		log = log,
	}
	return J.Encode(out)
end

-------------------------------------------------------------------------------
-- Roster / classes
-------------------------------------------------------------------------------
function X:UpdateRoster()
	self.roster = {}
	self.rosterCount = 0
	local function add(unit)
		local name = UnitName(unit)
		if name then
			self.roster[string.lower(name)] = name
			self.rosterCount = self.rosterCount + 1
			local _, class = UnitClass(unit)
			if class and self.db then self.db.classes[string.lower(name)] = class end
		end
	end
	local nr = GetNumRaidMembers()
	if nr > 0 then
		for i = 1, nr do add("raid" .. i) end
	else
		local np = GetNumPartyMembers()
		if np > 0 then
			add("player")
			for i = 1, np do add("party" .. i) end
		end
	end
end

function X:ClassColor(name)
	local class = self.db and self.db.classes[string.lower(name or "")]
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then
		return string.format("|cff%02x%02x%02x", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
	end
	return "|cffffffff"
end

-- Colour of a "main" (first known character among main + alts)
function X:MainColor(main)
	local d = self.db.players[main]
	local names = { main }
	if d and d.alts then
		for i = 1, table.getn(d.alts) do table.insert(names, d.alts[i]) end
	end
	for i = 1, table.getn(names) do
		if self.db.classes[string.lower(names[i])] then return self:ClassColor(names[i]) end
	end
	return "|cffffffff"
end

-------------------------------------------------------------------------------
-- Chat / communication
-------------------------------------------------------------------------------
function X:Channel()
	if GetNumRaidMembers() > 0 then return "RAID" end
	if GetNumPartyMembers() > 0 then return "PARTY" end
	return nil
end

function X:SendChat(msg)
	-- a lone "|" (not part of a color / link code) is an "invalid escape code" for SendChatMessage in 1.12
	msg = string.gsub(msg, "|([^cChHrRTtnN|])", "/%1")
	local ch = self:Channel()
	if ch then SendChatMessage(msg, ch) else self:Print(msg) end
end

function X:SendWarning(msg)
	msg = string.gsub(msg, "|([^cChHrRTtnN|])", "/%1")
	local ch = self:Channel()
	if ch == "RAID" and (IsRaidLeader() or IsRaidOfficer()) then
		SendChatMessage(msg, "RAID_WARNING")
	elseif ch then
		SendChatMessage(msg, ch)
	else
		self:Print(msg)
	end
end

-- Addon message to the group (protocol read by the player addon)
-- (1.12 has no WHISPER addon channel: everything goes to the group; the "target" argument is only kept for
-- readability, the messages themselves name the player they are about, the others ignore them)
function X:Comm(text, target)
	local ch = self:Channel()
	if ch then SendAddonMessage(self.PREFIX, text, ch) end
end

-- "P;Main/Alt,ep,gp;Main2,ep,gp" -- split into messages < 240 characters
-- "Synchronize" button / /epgp sync: sends everybody's priority (and the prices) to the group
function X:SyncPlayers()
	if not self:Grouped() then
		self:Print("You are not in a group: players get their priority when they join (their addon asks for it).")
		return 0
	end
	local n = self:Publish()
	self:Print("Priorities sent to the group (" .. n .. " message(s)). Players who connect later ask for theirs automatically.")
	return n
end

-- costs and base GP, so the player addon can compute priorities and show the prices
function X:CfgString()
	local c = self.db.costs
	return string.format("CFG;%s;%s;%s;%s", c.MIN, c.NEED, c.MAX, self.db.baseGP or 0)
end

function X:Publish(target, onlyMain)
	local chunks, cur = {}, "P"
	local names = {}
	if onlyMain then
		names = { { name = onlyMain } }
	else
		names = self:SortedPlayers()
	end
	for _, p in ipairs(names) do
		local d = self.db.players[p.name]
		if d then
			local piece = ";" .. self:PlayerName(p.name) .. "," .. self:Round(d.ep, 2) .. "," .. self:Round(d.gp, 2)
			if string.len(cur) + string.len(piece) > 240 then
				table.insert(chunks, cur)
				cur = "P"
			end
			cur = cur .. piece
		end
	end
	if cur ~= "P" then table.insert(chunks, cur) end
	for i = 1, table.getn(chunks) do self:Comm(chunks[i], target) end
	if not onlyMain then self:Comm(self:CfgString(), target) end
	return table.getn(chunks)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
function X:Debug(msg)
	if self.db and self.db.debug then self:Print("|cff888888[debug]|r " .. tostring(msg)) end
end

-- True if the player is the master looter (works in party and in raid)
function X:PlayerIsML()
	local method, partyID, raidID = GetLootMethod()
	if method ~= "master" then return false end
	if partyID == 0 then return true end
	if raidID and raidID > 0 and UnitIsUnit("raid" .. raidID, "player") then return true end
	return false
end

local QUALITY_BY_COLOR = {
	["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5,
}

local function qualityFromLink(link)
	local _, _, hex = string.find(link, "|c%x%x(%x%x%x%x%x%x)|H")
	return hex and QUALITY_BY_COLOR[string.lower(hex)] or nil
end

-- Bind-on-pickup detection through the loot slot tooltip (same method as RollFor).
-- Returns true (BoP / soulbound / quest item), false (not bound: safe to take) or nil (tooltip empty: unknown).
-- Note: a plain grey/white item can have a one-line tooltip (name only), which is "not bound", not "unknown".
function X:IsBindOnPickup(slot)
	if not self.tip then
		self.tip = CreateFrame("GameTooltip", "SkullEPGPScanTip", nil, "GameTooltipTemplate")
	end
	self.tip:SetOwner(WorldFrame, "ANCHOR_NONE")
	self.tip:ClearLines()
	self.tip:SetLootItem(slot)
	local n = self.tip:NumLines() or 0
	if n < 1 then return nil end
	for i = 2, n do
		local fs = getglobal("SkullEPGPScanTipTextLeft" .. i)
		local t = fs and fs:GetText()
		if t and (t == ITEM_BIND_ON_PICKUP or t == ITEM_SOULBOUND or t == ITEM_BIND_QUEST) then
			return true
		end
	end
	return false
end

-- Master looter only. On opening a corpse, takes for yourself:
--  * every item below the minimum quality that is not bind-on-pickup / soulbound / quest
--  * the coins
-- Hold SHIFT while opening the corpse to skip it.
function X:AutoLootLowQuality()
	if not self.db.autoLoot or not self:PlayerIsML() then return end
	if IsShiftKeyDown() then self:Debug("auto-loot skipped (shift held)"); return end
	local me = UnitName("player")
	local myIndex
	for i = 1, 40 do
		if GetMasterLootCandidate(i) == me then myIndex = i; break end
	end
	local taken, coins, left = {}, 0, 0
	local superwow = SUPERWOW_VERSION ~= nil
	for slot = 1, (GetNumLootItems() or 0) do
		local link = GetLootSlotLink(slot)
		if not link then
			-- no item link = coins (SuperWoW lets LootSlot take them: LootSlot(slot, 1))
			local ok, err
			if superwow then ok, err = pcall(LootSlot, slot, 1) else ok, err = pcall(LootSlot, slot) end
			self:Debug(string.format("auto-loot slot %d: coins, ok=%s%s", slot, tostring(ok), ok and "" or (" err=" .. tostring(err))))
			if ok then coins = coins + 1 end
		elseif string.find(link, "|Hitem:") then
			local _, _, _, quality = GetLootSlotInfo(slot)
			local q = qualityFromLink(link)
			if q == nil and type(quality) == "number" then q = quality end
			if q and q < self.db.minQuality then
				local bop = self:IsBindOnPickup(slot)
				self:Debug(string.format("auto-loot slot %d %s: quality %d < %d, bop=%s", slot, link, q, self.db.minQuality, tostring(bop)))
				if bop == false then
					if myIndex then GiveMasterLoot(slot, myIndex) else LootSlot(slot) end
					table.insert(taken, link)
				else
					left = left + 1
				end
			end
		end
	end
	if table.getn(taken) > 0 or coins > 0 then
		local msg = "Auto-looted"
		if table.getn(taken) > 0 then
			msg = msg .. " " .. table.getn(taken) .. " item(s) below " .. self:QualityLabel(self.db.minQuality) .. ": " .. table.concat(taken, " ")
		end
		if coins > 0 then msg = msg .. (table.getn(taken) > 0 and " + coins" or " coins") end
		self:Print(msg)
	end
	if left > 0 then
		self:Print(left .. " bind-on-pickup / unknown item(s) below " .. self:QualityLabel(self.db.minQuality) .. " left in the loot window.")
	end
end

-- Auto-open the window when at least one listed item is present: master looter, or raid leader / assistant.
function X:ShouldAutoOpen()
	if self:PlayerIsML() then return true end
	if GetNumRaidMembers() > 0 and (IsRaidLeader() or IsRaidOfficer()) then return true end
	return false
end

-- Reads the open loot window. Like RollFor, an item is any slot that has an item link
-- (GetLootSlotLink is nil for coins); quality comes from the link colour first.
-- Returns [itemId] = { n = copies, slots = { slot numbers }, link, icon, quality } for items of the minimum quality or better.
function X:ReadSlots()
	local res = {}
	local n = GetNumLootItems() or 0
	self:Debug(string.format("scan: %d slot(s), loot method = %s", n, tostring((GetLootMethod()))))
	for i = 1, n do
		local link = GetLootSlotLink(i)
		local icon, name, qty, quality = GetLootSlotInfo(i)
		local q = link and qualityFromLink(link)
		if q == nil and type(quality) == "number" then q = quality end
		self:Debug(string.format("  slot %d: link=%s quality=%s (info=%s)", i, tostring(link), tostring(q), tostring(quality)))
		if link and string.find(link, "|Hitem:") and (q or 0) >= self.db.minQuality then
			local _, _, id = string.find(link, "item:(%d+)")
			local r = res[id]
			if not r then
				r = { n = 0, slots = {}, link = link, icon = icon, quality = q or 0 }
				res[id] = r
			end
			r.n = r.n + 1
			table.insert(r.slots, i)
		end
	end
	return res
end

-- The list of loot to distribute: every line keeps
--   bags    = copies already in the master looter's bags
--   corpses = { [corpse key] = copies still in that corpse }  (key = GUID from SuperWoW, see GetCorpseKey)
-- so reopening a corpse that was already scanned replaces its own copies instead of duplicating them.
function X:UpdateCounts()
	for i = table.getn(self.lootItems), 1, -1 do
		local it = self.lootItems[i]
		it.corpses = it.corpses or {}
		local c = 0
		for k, n in pairs(it.corpses) do
			if n > 0 then c = c + n else it.corpses[k] = nil end
		end
		it.bagExp = it.bagExp or {}
		it.corpse, it.bags = c, table.getn(it.bagExp)
		it.count = it.corpse + it.bags
		if it.count <= 0 then table.remove(self.lootItems, i) end
	end
end

-- Identifies the corpse being looted. SuperWoW's UnitExists("unit") returns the unit GUID as a second value;
-- the looted corpse is normally the target (or the mouseover). Without SuperWoW, or if the loot
-- source is not a dead unit (chest...), a single shared key is used (a rescan then replaces the previous one).
function X:GetCorpseKey()
	local units = { "target", "mouseover" }
	for _, u in ipairs(units) do
		local ok, exists, guid = pcall(UnitExists, u)
		if ok and exists and type(guid) == "string" and UnitIsDead(u) then
			self:Debug("corpse key (" .. u .. "): " .. guid)
			return guid
		end
	end
	self:Debug("corpse key: none (no SuperWoW GUID), using shared key")
	return "nokey"
end

-- Removes n copies from the corpses (the open one first)
function X:DecCorpse(it, n)
	n = n or 1
	it.corpses = it.corpses or {}
	local function take(k)
		local have = it.corpses[k] or 0
		local m = math.min(have, n)
		if m > 0 then it.corpses[k] = have - m; n = n - m end
	end
	if self.curKey then take(self.curKey) end
	for k, _ in pairs(it.corpses) do if n > 0 then take(k) end end
end

-- Copies in the master looter's bags: bagExp holds one entry per copy = time() at which it can no longer be
-- traded (0 = no timer, i.e. not bind-on-pickup). X.TRADE_SECONDS after the copy was picked up.
X.TRADE_SECONDS = 600
function X:AddBag(it, n, bop)
	it.bagExp = it.bagExp or {}
	for _ = 1, n do table.insert(it.bagExp, bop and (time() + self.TRADE_SECONDS) or 0) end
end

-- Removes the oldest copy from the bags, returns its expiry
function X:PopBag(it)
	if not it.bagExp or table.getn(it.bagExp) == 0 then return 0 end
	return table.remove(it.bagExp, 1)
end

function X:SavePending()
	if not self.db then return end
	local p = {}
	for _, it in ipairs(self.lootItems) do
		if table.getn(it.bagExp or {}) > 0 then
			local e = {}
			for _, v in ipairs(it.bagExp) do table.insert(e, v) end
			table.insert(p, { link = it.link, icon = it.icon, quality = it.quality, id = it.id, bags = table.getn(e), exp = e })
		end
	end
	self.db.pending = p
end

function X:RestorePending()
	self.lootItems = {}
	for _, p in ipairs(self.db.pending or {}) do
		local e = {}
		for i = 1, (p.bags or 0) do e[i] = (p.exp and p.exp[i]) or 0 end
		table.insert(self.lootItems, { link = p.link, icon = p.icon, quality = p.quality, id = p.id, bagExp = e, corpses = {} })
	end
	self:UpdateCounts()
end

-- Removes a line from the list of items to announce (all its copies). The corpses it came from will not add it again.
X.ignored = {}
function X:RemoveLootItem(it)
	if not it then return end
	for k, n in pairs(it.corpses or {}) do
		if n > 0 then self.ignored[k .. ":" .. it.id] = true end
	end
	for i = table.getn(self.lootItems), 1, -1 do
		if self.lootItems[i] == it then table.remove(self.lootItems, i) end
	end
	self:SavePending()
	if self.UI then self.UI:RefreshLoot() end
end

function X:ScanLoot(key)
	if key then
		self.curKey = key
		if key == "nokey" then
			-- no GUID: a freshly opened loot window is a new source, forget what was removed from the previous one
			for k in pairs(self.ignored) do
				if string.find(k, "^nokey:") then self.ignored[k] = nil end
			end
		end
	elseif not self.curKey then
		self.curKey = self:GetCorpseKey()
	end
	local k = self.curKey
	for _, it in ipairs(self.lootItems) do
		if it.corpses then it.corpses[k] = nil end
	end
	local slots = self:ReadSlots()
	-- keep the order of the slots: first slot of each item decides
	local order = {}
	for id, r in pairs(slots) do table.insert(order, { id = id, first = r.slots[1] }) end
	table.sort(order, function(a, b) return a.first < b.first end)
	for _, o in ipairs(order) do
		local r = slots[o.id]
		local same
		for _, it in ipairs(self.lootItems) do
			if it.id == o.id then same = it; break end
		end
		-- (a line removed by the officer is not added again for this corpse)
		if not self.ignored[k .. ":" .. o.id] then
			if not same then
				same = { link = r.link, icon = r.icon, quality = r.quality, id = o.id, corpses = {}, bagExp = {} }
				table.insert(self.lootItems, same)
			end
			same.corpses = same.corpses or {}
			same.corpses[k] = r.n
		end
	end
	self:UpdateCounts()
	self:SavePending()
end

function X:CorpseItemCount()
	-- copies in the corpse that is currently open
	local n = 0
	for _, it in ipairs(self.lootItems or {}) do
		n = n + ((it.corpses and self.curKey and it.corpses[self.curKey]) or 0)
	end
	return n
end

-- Master looter: takes one copy of the item into his own bags (to trade it later). It stays in the list.
function X:TakeItem(it)
	if not it or ((it.corpses and self.curKey and it.corpses[self.curKey]) or 0) < 1 then return false end
	if not self:PlayerIsML() or (GetNumLootItems() or 0) == 0 then
		self:Print("Open the corpse as master looter to take the item.")
		return false
	end
	local me, myIndex = UnitName("player")
	for i = 1, 40 do
		if GetMasterLootCandidate(i) == me then myIndex = i; break end
	end
	local r = self:ReadSlots()[it.id]
	if not r or not myIndex then
		self:Print("Item not found in the loot window.")
		return false
	end
	local bop = self:IsBindOnPickup(r.slots[1])
	GiveMasterLoot(r.slots[1], myIndex)
	local pp = self.pendingPick
	if not pp or pp.id ~= it.id then pp = { id = it.id, n = 0, t = 0 }; self.pendingPick = pp end
	pp.bop = (bop ~= false)   -- only bind-on-pickup items get the trade timer (unknown counts as bound)
	pp.n = pp.n + 1
	pp.t = 0
	return true
end

-- Compares the loot window with the list: copies that left the window because of a "Take" move to the bags.
function X:SyncCorpse(final, cleared)
	local pp = self.pendingPick
	local open = (GetNumLootItems() or 0) > 0
	local slots = open and self:ReadSlots() or {}
	local k = self.curKey
	for _, it in ipairs(self.lootItems) do
		local have = (it.corpses and k and it.corpses[k]) or 0
		if open and have > 0 then
			local newc = slots[it.id] and slots[it.id].n or 0
			if newc < have then
				local d = have - newc
				if pp and pp.id == it.id then
					local m = math.min(d, pp.n)
					self:AddBag(it, m, pp.bop)
					pp.n = pp.n - m
				end
				it.corpses[k] = newc
			end
		end
	end
	if pp then
		if (final or (cleared and not open)) and pp.n > 0 then
			if not open then
				-- the window closed right after the click: assume the copies were taken
				for _, it in ipairs(self.lootItems) do
					if it.id == pp.id then
						local have = (it.corpses and k and it.corpses[k]) or 0
						local m = math.min(pp.n, have)
						if m > 0 then it.corpses[k] = have - m; self:AddBag(it, m, pp.bop) end
					end
				end
			else
				self:Print("The item could not be taken (bags full?).")
			end
			self.pendingPick = nil
		elseif pp.n <= 0 then
			self.pendingPick = nil
		end
	end
	self:UpdateCounts()
	self:SavePending()
	if self.UI then self.UI:RefreshLoot() end
end

-- Forgets the whole list (bags and corpses), then rescans the open loot window
function X:ClearBagItems()
	self.lootItems = {}
	self.curKey = nil
	if (GetNumLootItems() or 0) > 0 then self:ScanLoot() else self:SavePending() end
	if self.UI then self.UI:RefreshLoot() end
end

function X:OnEvent(event, a1, a2, a3, a4)
	if event == "VARIABLES_LOADED" then
		self:InitDB()
		self:RestorePending()
		if self.UI then self.UI:ApplySaved(); self.UI:RefreshAll() end
		if self.Minimap then self.Minimap:Apply() end
	elseif not self.db then
		return
	elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" or event == "PLAYER_ENTERING_WORLD"
		or event == "PARTY_LOOT_METHOD_CHANGED" or event == "PARTY_LEADER_CHANGED" then
		self:UpdateRoster()
		self:CheckStatus()
		-- a new group member may be the other officer: ask for newer data (throttled)
		if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
			if self:Grouped() and self:IsOfficer() then self:RequestSync() end
		end
	elseif not self:Active() then
		return      -- officer addon only works for the master looter / group leader
	elseif event == "LOOT_OPENED" then
		self.lootOpen = true
		self:ScanLoot(self:GetCorpseKey())
		self:AutoLootLowQuality()
		self:Debug(string.format("LOOT_OPENED: %d item(s) kept (min quality %d), isML=%s",
			table.getn(self.lootItems), self.db.minQuality, tostring(self:PlayerIsML())))
		if self.UI then
			self.UI:RefreshLoot()
			if self.db.autoOpen and self:CorpseItemCount() > 0 and self:ShouldAutoOpen() then
				self.UI:Show(1)
			else
				self:Debug(string.format("window not opened: autoOpen=%s items=%d allowed=%s",
					tostring(self.db.autoOpen), table.getn(self.lootItems), tostring(self:ShouldAutoOpen())))
			end
		end
	elseif event == "LOOT_SLOT_CLEARED" then
		if self.pendingPick then self:SyncCorpse(false, true) end
	elseif event == "LOOT_CLOSED" then
		-- keep the list: bidding can continue while the loot window is closed
		self.lootOpen = false
		if self.UI then self.UI:RefreshLoot() end
	elseif event == "TRADE_SHOW" or event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_ACCEPT_UPDATE" or event == "TRADE_CLOSED" or event == "UI_INFO_MESSAGE" then
		self:OnTradeEvent(event, a1)
	elseif event == "CHAT_MSG_SYSTEM" then
		self:HandleTradeMessage(a1)
		self:HandleSystem(a1)
	elseif event == "CHAT_MSG_ADDON" then
		self:HandleAddon(a1, a2, a3, a4)
	elseif string.find(event, "^CHAT_MSG_") then
		self:HandleChat(a1, a2)
	end
end

X.frame = CreateFrame("Frame", "SkullEPGPEventFrame")
local evs = { "VARIABLES_LOADED", "RAID_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "PLAYER_ENTERING_WORLD",
	"LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED", "TRADE_SHOW", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_CLOSED", "UI_INFO_MESSAGE", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_SYSTEM", "CHAT_MSG_ADDON",
	"PARTY_LOOT_METHOD_CHANGED", "PARTY_LEADER_CHANGED" }
for i = 1, table.getn(evs) do X.frame:RegisterEvent(evs[i]) end
X.frame:SetScript("OnEvent", function() X:OnEvent(event, arg1, arg2, arg3, arg4) end)
X.frame:SetScript("OnUpdate", function() X:OnUpdate(arg1) end)
