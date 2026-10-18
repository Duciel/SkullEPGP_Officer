-- Auction.lua : item announcement, MIN/NEED/MAX bid and roll tracking, ranking, awarding
local X = SkullEPGP

X.auction = nil

-- Pattern of the /roll system message, built from the client's localized constant
local function buildRollPattern()
	local p = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
	p = string.gsub(p, "%%%d%$s", "\1")
	p = string.gsub(p, "%%%d%$d", "\2")
	p = string.gsub(p, "%%s", "\1")
	p = string.gsub(p, "%%d", "\2")
	p = string.gsub(p, "([%(%)%.%-%+%[%]%*%?%^%$])", "%%%1")
	p = string.gsub(p, "\1", "(.+)")
	p = string.gsub(p, "\2", "(%%d+)")
	return "^" .. p
end
X.rollPattern = buildRollPattern()
X.rollPatternFallback = "^(.+) rolls (%d+) %((%d+)%-(%d+)%)"

-------------------------------------------------------------------------------
-- Starting a round
-------------------------------------------------------------------------------
X.INACTIVE_MSG = "Officer mode is OFF: it only works when the loot method is Master Looter (master looter or group leader), and when it has not been disabled by hand (right-click the minimap button or /epgp on)."

function X:StartAuction(link, duration, count)
	if not self:Active() then self:Print(self.INACTIVE_MSG); return false end
	local a = self.auction
	if a and a.state == "open" then
		self:Print("A bidding round is already running: close or cancel it first.")
		return false
	end
	if not link or not string.find(link, "|Hitem:") then
		self:Print("Invalid item link.")
		return false
	end
	count = tonumber(count) or 1
	if count < 1 then count = 1 end
	duration = tonumber(duration) or self.db.duration
	if duration < 5 then duration = 5 end
	if duration > 300 then duration = 300 end
	self.db.duration = duration

	self.db.nextId = self.db.nextId + 1
	local now = GetTime()
	a = {
		id = self.db.nextId,
		link = link,
		count = count,          -- copies dropped
		remaining = count,      -- copies still to award
		duration = duration,
		startTime = now,
		endTime = now + duration,
		state = "open",
		entries = {},
		marks = {},
	}
	for _, m in ipairs(self.COUNTDOWN_MARKS) do
		if m >= duration then a.marks[m] = true end
	end
	self.auction = a

	local c = self.db.costs
	local shown = (count > 1) and (link .. " x" .. count) or link
	self:SendWarning(string.format("%s - BIDDING OPEN (%ds): MIN (%d GP) / NEED (%d GP) / MAX (%d GP) in raid chat, or /roll. One choice only (NEED can be upgraded to MAX)",
		shown, duration, c.MIN, c.NEED, c.MAX))
	self:Comm("AUC;" .. a.id .. ";" .. duration .. ";" .. count .. ";" .. link)
	if self.UI then self.UI:OnAuctionChanged() end
	return true
end

-------------------------------------------------------------------------------
-- Recording bids and rolls
-------------------------------------------------------------------------------
function X:InRoster(char)
	return self.rosterCount == 0 or self.roster[string.lower(char)] ~= nil
end

function X:KeyFor(char)
	local main = self:FindMain(char)
	return main and ("m:" .. string.lower(main)) or ("c:" .. string.lower(char)), main
end

function X:GetEntry(char)
	local a = self.auction
	local key, main = self:KeyFor(char)
	local e = a.entries[key]
	if not e then
		e = { key = key, main = main, char = char, time = GetTime() }
		a.entries[key] = e
	end
	e.char = char
	return e
end

-- One choice per announcement: a player picks MIN, NEED, MAX or a plain /roll.
-- The only change allowed afterwards is upgrading NEED to MAX.
function X:RegisterBid(char, bid)
	local a = self.auction
	if not a or a.state ~= "open" then return false end
	if not self:InRoster(char) then return false end
	local e = a.entries[self:KeyFor(char)]
	if e and e.won then return false end   -- already won a copy of this item
	if e then
		if e.bid then
			if not (e.bid == "NEED" and bid == "MAX") then
				if e.bid ~= bid then
					self:Print(string.format("%s: %s ignored, already chose %s (only NEED -> MAX is allowed).", char, bid, e.bid))
				end
				return false
			end
		elseif e.roll then
			self:Print(string.format("%s: %s ignored, already chose a plain /roll (%d).", char, bid, e.roll))
			return false
		end
	end
	e = self:GetEntry(char)
	e.bid = bid
	if not e.main then
		self:Print("|cffff8080" .. char .. " is not on the EPGP list (priority 0).|r")
	end
	self:BroadcastBid(e)
	if self.UI then self.UI:RefreshAuction() end
	return true
end

-- Tells the player addons about a bid / roll (they show the list of bidders with their priority)
function X:BroadcastBid(e, target)
	local a = self.auction
	if not a or not e then return end
	local pr = e.main and self:GetPR(e.main) or 0
	self:Comm(string.format("BID;%d;%s;%s;%d;%s", a.id, e.char, e.bid or "ROLL", e.roll or 0, self:Round(pr, 2)), target)
end

function X:SendBids(target)
	local a = self.auction
	if not a then return end
	for _, e in pairs(a.entries) do
		if not e.won then self:BroadcastBid(e, target) end
	end
end

function X:RegisterRoll(char, roll)
	local a = self.auction
	if not a or a.state ~= "open" then return false end
	if not self:InRoster(char) then return false end
	local e = a.entries[self:KeyFor(char)]
	if e and e.won then return false end
	if e and e.bid then
		self:Print(string.format("%s: /roll %d ignored, already chose %s.", char, roll, e.bid))
		return false
	end
	if e and e.roll then return false end    -- only the first /roll counts
	e = self:GetEntry(char)
	e.roll = roll
	self:BroadcastBid(e)
	if self.UI then self.UI:RefreshAuction() end
	return true
end

function X:HandleChat(msg, sender)
	local a = self.auction
	if not a or a.state ~= "open" or not msg or not sender then return end
	local up = string.upper(X.Trim(msg))
	up = string.gsub(up, "[%s!%.]+$", "")
	if up == "MIN" or up == "NEED" or up == "MAX" then
		self:RegisterBid(sender, up)
	end
end

function X:HandleSystem(msg)
	local a = self.auction
	if not a or a.state ~= "open" or not msg then return end
	local _, _, who, roll, lo, hi = string.find(msg, self.rollPattern)
	if not who then
		_, _, who, roll, lo, hi = string.find(msg, self.rollPatternFallback)
	end
	if who and tonumber(lo) == 1 then
		hi = tonumber(hi)
		if hi == 100 then
			self:RegisterRoll(who, tonumber(roll))
		elseif hi and hi > 1 and hi < 100 then
			-- a roll with a range below 100 (e.g. 1-50) is tracked and ranked as a 100
			if self:RegisterRoll(who, 100) then
				self:Print(string.format("%s rolled %d (1-%d): counted as 100.", who, tonumber(roll), hi))
			end
		end
	end
end

-- Addon messages received (the player addon asks for the current state with "REQ")
function X:HandleAddon(prefix, text, channel, sender)
	if prefix ~= self.PREFIX or sender == UnitName("player") then return end
	if string.len(text or "") > 2 and string.sub(text, 3, 3) == ";" and string.sub(text, 1, 1) == "S" then
		self:HandleSync(text, sender)      -- officer <-> officer synchronisation (Sync.lua)
		return
	end
	if text == "REQ" then
		local main = self:FindMain(sender)
		if main then self:Publish(sender, main) else self:Comm("NP;" .. sender) end
		-- prices / current announcement are for everybody: do not repeat them for each request (raid start)
		local now = GetTime()
		if self.lastReqExtra and now - self.lastReqExtra < 5 then return end
		self.lastReqExtra = now
		self:Comm(self:CfgString())
		local a = self.auction
		if a and a.state == "open" then
			local remaining = math.ceil(a.endTime - GetTime())
			if remaining > 0 then
				self:Comm("AUC;" .. a.id .. ";" .. remaining .. ";" .. (a.remaining or 1) .. ";" .. a.link, sender)
				self:SendBids()
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Ranking: tier (MAX > NEED > MIN > roll), then EP/GP priority, then roll, then arrival order
-------------------------------------------------------------------------------
function X:GetRanking()
	local a = self.auction
	local list = {}
	if not a then return list end
	local costs = self.db.costs
	for key, e in pairs(a.entries) do
	  if not e.won then
		local bid = e.bid or "ROLL"
		local pr = e.main and self:GetPR(e.main) or 0
		local display = e.main or e.char
		if e.main and string.lower(e.main) ~= string.lower(e.char) then
			display = e.main .. " (" .. e.char .. ")"
		end
		table.insert(list, {
			key = key,
			main = e.main,
			char = e.char,
			display = display,
			bid = bid,
			tier = self.TIERS[bid],
			pr = pr,
			prc = math.floor(pr * 10000 + 0.5),
			roll = e.roll,
			time = e.time,
			cost = e.bid and costs[e.bid] or 0,
		})
	  end
	end
	table.sort(list, function(x, y)
		if x.tier ~= y.tier then return x.tier > y.tier end
		if x.tier > 1 and x.prc ~= y.prc then return x.prc > y.prc end
		local rx, ry = x.roll or 0, y.roll or 0
		if rx ~= ry then return rx > ry end
		if x.time ~= y.time then return x.time < y.time end
		return x.key < y.key
	end)
	return list
end

local function describe(r)
	if r.bid == "ROLL" then
		return string.format("%s roll %s", r.char, tostring(r.roll or 0))
	end
	local s = string.format("%s %s (PR %.2f", r.char, r.bid, r.pr)
	if r.roll then s = s .. ", roll " .. r.roll end
	return s .. ")"
end

-------------------------------------------------------------------------------
-- Closing / cancelling / awarding
-------------------------------------------------------------------------------
function X:CloseAuction()
	local a = self.auction
	if not a or a.state ~= "open" then return end
	a.state = "closed"
	local rank = self:GetRanking()
	if table.getn(rank) == 0 then
		self:SendChat(a.link .. " - Bidding closed: no participants.")
	else
		local parts = {}
		for i = 1, math.min(3, table.getn(rank)) do
			table.insert(parts, i .. ") " .. describe(rank[i]))
		end
		self:SendChat(a.link .. " - Bidding closed. " .. table.concat(parts, "; "))
	end
	self:Comm("END;" .. a.id)
	if self.UI then self.UI:OnAuctionChanged() end
end

function X:CancelAuction()
	local a = self.auction
	if not a then return end
	if a.state == "open" or a.state == "closed" then
		self:SendChat(a.link .. " - Bidding cancelled.")
		self:Comm("CAN;" .. a.id)
	end
	self.auction = nil
	if self.UI then self.UI:OnAuctionChanged() end
end

local function itemId(link)
	local _, _, id = string.find(link or "", "item:(%d+)")
	return id
end

-- Gives the item through master loot if the loot window is open
function X:TryGiveLoot(link, char)
	if not self:PlayerIsML() or GetNumLootItems() == 0 then return false end
	local slot
	for i = 1, GetNumLootItems() do
		local l = GetLootSlotLink(i)
		if l and itemId(l) == itemId(link) then slot = i; break end
	end
	if not slot then return false end
	for ci = 1, 40 do
		if GetMasterLootCandidate(ci) == char then
			GiveMasterLoot(slot, ci)
			return true
		end
	end
	return false
end

-- key: key of a ranking row (nil = first)
function X:Award(key)
	local a = self.auction
	if not a or (a.state ~= "open" and a.state ~= "closed") then
		self:Print("No bidding round to award.")
		return
	end
	local rank = self:GetRanking()
	local r = rank[1]
	if key then
		for i = 1, table.getn(rank) do if rank[i].key == key then r = rank[i] end end
	end
	if not r then
		self:Print("No participants.")
		return
	end
	local text = string.format("Award %s%s to %s?\n%s", a.link, (a.count > 1) and string.format(" (copy %d/%d)", a.count - a.remaining + 1, a.count) or "", r.display,
		(r.cost > 0) and string.format("Cost: %d GP (%s)", r.cost, r.bid) or "No GP (roll)")
	if not r.main and r.cost > 0 then
		text = text .. "\n|cffff8080Player not on the EPGP list: GP will not be recorded.|r"
	end
	self:Confirm(text, function() X:DoAward(r) end)
end

function X:DoAward(r)
	local a = self.auction
	if not a then return end
	local gz
	if r.cost > 0 then
		gz = string.format("Gz %s => %s (%s, -%d GP)", r.char, a.link, r.bid, r.cost)
	else
		gz = string.format("Gz %s => %s (roll %s)", r.char, a.link, tostring(r.roll or 0))
	end
	self:SendChat(gz)
	self:Comm("WIN;" .. a.id .. ";" .. r.char .. ";" .. r.bid .. ";" .. r.cost)

	local given = self:TryGiveLoot(a.link, r.char)
	-- which copy of the list was used: the one in the corpse if it was given from there, else one from the bags
	local entry
	for _, it in ipairs(self.lootItems or {}) do
		if itemId(it.link) == itemId(a.link) then entry = it; break end
	end
	local from, exp
	if entry then
		if given and (entry.corpse or 0) > 0 then self:DecCorpse(entry, 1); from = "corpse"
		elseif table.getn(entry.bagExp or {}) > 0 then exp = self:PopBag(entry); from = "bags"
		elseif (entry.corpse or 0) > 0 then self:DecCorpse(entry, 1); from = "corpse" end
	end
	local rec = { main = r.main, char = r.char, cost = (r.main and r.cost) or 0, bid = r.bid, roll = r.roll, link = a.link, exp = exp or 0 }
	local me = UnitName("player")
	if not given and from == "bags" and string.lower(r.char) ~= string.lower(me) then
		-- the item is in the master looter's bags: GP only once the trade is done
		self:AddTrade(rec)
		self:Print(string.format("%s => |cffffd700%s|r: trade it from your bags (Trades tab). GP will be applied once the trade is done.", a.link, r.char))
	else
		self:ApplyAward(rec)
		if not given then
			if from == "bags" then
				self:Print("The item is already in your bags. GP has been applied.")
			else
				self:Print("Item not given automatically (not master looter, or loot window closed): give it manually to |cffffd700" .. r.char .. "|r. GP has been applied.")
			end
		end
	end
	-- this player has won a copy: out of the ranking for the remaining copies
	local we = a.entries[r.key]
	if we then we.won = true end
	a.winner = r
	a.remaining = (a.remaining or 1) - 1
	if a.remaining <= 0 then
		a.state = "awarded"
		a.entries = {}                    -- last copy awarded: the list of bidders is cleared
	else
		self:Print(string.format("%d more copy(ies) of %s to award: pick the next winner.", a.remaining, a.link))
	end
	-- one copy less in the top list (the line disappears when none is left)
	self:UpdateCounts()
	self:SavePending()
	if self.UI then self.UI:RefreshLoot(); self.UI:OnAuctionChanged() end
end

-------------------------------------------------------------------------------
-- Timer
-------------------------------------------------------------------------------
X.tick = 0
function X:OnUpdate(elapsed)
	self:StatusTick(elapsed)
	self:FlushSync(elapsed)
	self:TradeTick(elapsed)
	if self.pendingPick then
		self.pendingPick.t = self.pendingPick.t + (elapsed or 0)
		if self.pendingPick.t > 1 then self:SyncCorpse(true) end
	end
	local a = self.auction
	if not a then return end
	self.tick = self.tick + (elapsed or 0)
	if self.tick < 0.25 then return end
	self.tick = 0
	if a.state == "open" then
		local remaining = a.endTime - GetTime()
		for _, m in ipairs(self.COUNTDOWN_MARKS) do
			if not a.marks[m] and remaining <= m then
				a.marks[m] = true
				if remaining > 0 then
					if m >= 10 then
						self:SendChat(string.format("%s - %d seconds left (MIN / NEED / MAX or /roll)", a.link, m))
					else
						self:SendChat(tostring(m))
					end
				end
			end
		end
		if remaining <= 0 then
			self:CloseAuction()
			return
		end
	end
	if self.UI then self.UI:UpdateTimer() end
end

-------------------------------------------------------------------------------
-- Generic confirmation
-------------------------------------------------------------------------------
StaticPopupDialogs["SKULLEPGP_CONFIRM"] = {
	text = "%s",
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function()
		local f = X.pendingAction
		X.pendingAction = nil
		if f then f() end
	end,
	OnCancel = function() X.pendingAction = nil end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

function X:Confirm(text, fn)
	self.pendingAction = fn
	StaticPopup_Show("SKULLEPGP_CONFIRM", text)
end
