-- Trade.lua : items awarded but still in the master looter's bags, waiting for the trade with the winner.
-- GP is only applied (and the award logged) once the trade is done.
local X = SkullEPGP

local function itemId(link)
	local _, _, id = string.find(link or "", "item:(%d+)")
	return id
end

-- GP + log + priorities broadcast for a finished award
-- rec = { main, char, cost, bid, roll, link }
function X:ApplyAward(rec)
	local name, id = X.ItemInfo(rec.link)
	local d = rec.main and self.db.players[rec.main]
	local cost = (d and rec.cost) or 0
	if d and cost > 0 then d.gp = d.gp + cost; self:Touch(rec.main) end
	self:AddLog({
		type = "AWARD", player = rec.main or rec.char, char = rec.char, gp = cost,
		bid = rec.bid, roll = rec.roll, item = name, itemId = id, link = rec.link,
	})
	if d and cost > 0 then self:Publish(nil, rec.main) end
end

-- Seconds left before the trade window of a copy closes (nil = no timer)
function X:TimeLeft(exp)
	if not exp or exp <= 0 then return nil end
	return exp - time()
end

-- Plain countdown "m:ss"
function X.FormatLeft(s)
	if s <= 0 then return "0:00" end
	return string.format("%d:%02d", math.floor(s / 60), math.mod(s, 60))
end

function X:AddTrade(rec)
	table.insert(self.db.trades, rec)
	if self.UI then self.UI:RefreshTrades(); self.UI:RefreshLoot() end
end

function X:ValidateTrade(i, auto)
	local t = self.db.trades[i]
	if not t then return false end
	table.remove(self.db.trades, i)
	self:ApplyAward(t)
	self:Print(string.format("Trade done: %s => |cffffd700%s|r%s", t.link, t.char,
		(t.main and t.cost > 0) and string.format(" (%d GP applied)", t.cost) or ""))
	if self.UI then self.UI:RefreshAll() end
	return true
end

-- The item goes back to the list (still in the bags), no GP is applied
function X:CancelTrade(i)
	local t = self.db.trades[i]
	if not t then return false end
	table.remove(self.db.trades, i)
	local entry
	for _, it in ipairs(self.lootItems) do
		if it.id == itemId(t.link) then entry = it; break end
	end
	if not entry then
		local tex
		if GetItemInfo then
			local _, _, _, _, _, _, _, _, _, tx = GetItemInfo(itemId(t.link))
			tex = tx
		end
		entry = { link = t.link, icon = tex, quality = 4, id = itemId(t.link), corpses = {}, bagExp = {} }
		table.insert(self.lootItems, entry)
	end
	table.insert(entry.bagExp, t.exp or 0)
	self:UpdateCounts()
	self:SavePending()
	self:Print(string.format("Trade cancelled: %s is back in your list, no GP applied (%s was announced as the winner).", t.link, t.char))
	if self.UI then self.UI:RefreshAll() end
	return true
end

-------------------------------------------------------------------------------
-- "Trade" button: opens the trade window with the winner and puts the item in it
-------------------------------------------------------------------------------
-- unit token of a group member (or the target) with this character name
function X:UnitFor(char)
	local lc = string.lower(char)
	if UnitName("target") and string.lower(UnitName("target")) == lc then return "target" end
	for i = 1, (GetNumRaidMembers() or 0) do
		local n = UnitName("raid" .. i)
		if n and string.lower(n) == lc then return "raid" .. i end
	end
	for i = 1, (GetNumPartyMembers() or 0) do
		local n = UnitName("party" .. i)
		if n and string.lower(n) == lc then return "party" .. i end
	end
end

-- Puts the first matching item of the bags into the first free slot of the open trade window
function X:PlaceTradeItem(t)
	local id = itemId(t.link)
	local free
	for i = 1, 6 do
		if X.TradeSlotId(i) == id then return true end   -- already in the window
		if not free and not X.TradeSlotUsed(i) then free = i end
	end
	if not free then self:Print("No free slot in the trade window."); return false end
	for bag = 0, 4 do
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			local l = GetContainerItemLink(bag, slot)
			if l and itemId(l) == id then
				if CursorHasItem and CursorHasItem() then ClearCursor() end
				PickupContainerItem(bag, slot)
				ClickTradeButton(free)
				return true
			end
		end
	end
	self:Print("Item not found in your bags: " .. t.link)
	return false
end

function X:StartTrade(i)
	local t = self.db.trades[i]
	if not t then return end
	local partner = TradeFrameRecipientNameText and TradeFrameRecipientNameText.GetText and TradeFrameRecipientNameText:GetText()
	if TradeFrame and TradeFrame:IsShown() and partner and string.lower(partner) == string.lower(t.char) then
		self:PlaceTradeItem(t)
		return
	end
	local unit = self:UnitFor(t.char)
	if not unit then
		self:Print("|cffffd700" .. t.char .. "|r is not in your group (or target him and try again).")
		return
	end
	self.pendingTrade = { char = t.char, link = t.link, t = 0 }
	local ok, err = pcall(InitiateTrade, unit)
	if not ok then
		self.pendingTrade = nil
		self:Print("Could not open the trade window: " .. tostring(err))
	end
end

-------------------------------------------------------------------------------
-- Automatic detection of the trade (TRADE_* events + "Trade complete.")
-------------------------------------------------------------------------------
-- Item id offered in slot i of the trade window (nil = empty or unreadable).
-- Tries GetTradePlayerItemLink, then ClassicAPI's GetTradePlayerItemID.
function X.TradeSlotId(i)
	if GetTradePlayerItemLink then
		local ok, link = pcall(GetTradePlayerItemLink, i)
		if ok and link then
			local id = itemId(link)
			if id then return id end
		end
	end
	if GetTradePlayerItemID then
		local ok, id = pcall(GetTradePlayerItemID, i)
		if ok and id and id ~= 0 then return tostring(id) end
	end
end

-- true when the trade slot has something in it (whatever we can or cannot read)
function X.TradeSlotUsed(i)
	if X.TradeSlotId(i) then return true end
	if GetTradePlayerItemInfo then
		local ok, name = pcall(GetTradePlayerItemInfo, i)
		if ok and name and name ~= "" then return true end
	end
	return false
end

local function cleanName(n)
	if not n then return nil end
	n = string.gsub(n, "|c%x%x%x%x%x%x%x%x", "")
	n = string.gsub(n, "|r", "")
	n = string.gsub(n, "^%s+", "")
	n = string.gsub(n, "%s+$", "")
	return n ~= "" and n or nil
end

-- number of bag slots holding this item
local function bagCount(id)
	local n = 0
	for bag = 0, 4 do
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			local l = GetContainerItemLink(bag, slot)
			if l and itemId(l) == id then n = n + 1 end
		end
	end
	return n
end

-- Remembers who we trade with and what we offer (+ how many copies we own in total, bags + trade window)
function X:SnapshotTrade()
	local partner = cleanName(UnitName("NPC"))
	if not partner and TradeFrameRecipientNameText and TradeFrameRecipientNameText.GetText then
		partner = cleanName(TradeFrameRecipientNameText:GetText())
	end
	local ids, totals = {}, {}
	for i = 1, 6 do
		local id = X.TradeSlotId(i)
		if id then
			table.insert(ids, id)
			totals[id] = (totals[id] or 0) + 1
		end
	end
	for id, n in pairs(totals) do totals[id] = n + bagCount(id) end
	self.tradeSnap = { partner = partner, ids = ids, totals = totals }
	self:Debug("trade snapshot: partner=" .. tostring(partner) .. ", items=" .. table.getn(ids))
end

function X:OnTradeEvent(event, a1)
	if not self.db then return end
	self:Debug("trade event: " .. event .. " " .. tostring(a1))
	if event == "TRADE_SHOW" then
		self.tradeSnap = nil
		local ok, err = pcall(self.SnapshotTrade, self)
		if not ok then self:Debug("snapshot error: " .. tostring(err)) end
		local pt = self.pendingTrade
		if pt then
			self.pendingTrade = nil
			local partner = self.tradeSnap and self.tradeSnap.partner
			if partner and string.lower(partner) == string.lower(pt.char) then
				pcall(self.PlaceTradeItem, self, pt)
			end
		end
	elseif event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then
		local ok, err = pcall(self.SnapshotTrade, self)
		if not ok then self:Debug("snapshot error: " .. tostring(err)) end
	elseif event == "TRADE_CLOSED" then
		-- no "Trade complete." seen (yet): check a moment later whether the items really left the bags
		if self.tradeSnap and self.tradeSnap.partner then
			self.tradeCheck = { snap = self.tradeSnap, t = 0 }
		end
	elseif event == "UI_INFO_MESSAGE" then
		self:HandleTradeMessage(a1)
	end
end

function X:HandleTradeMessage(msg)
	if msg and msg == (ERR_TRADE_COMPLETE or "Trade complete.") then
		self:Debug("trade complete message")
		self:OnTradeComplete()
	end
end

-- Validates the pending trades whose item was in the window with the matching partner
function X:CompleteTrade(snap)
	if not snap or not snap.partner or table.getn(self.db.trades) == 0 then return end
	local partner = string.lower(snap.partner)
	for _, id in ipairs(snap.ids) do
		for i = 1, table.getn(self.db.trades) do
			local t = self.db.trades[i]
			if itemId(t.link) == id and string.lower(t.char) == partner then
				self:ValidateTrade(i, true)
				break
			end
		end
	end
end

-- When the trade window content cannot be read: a pending trade of the partner is done if its item
-- is no longer in the bags (copies the addon still lists in the bags + pending trades = expected).
function X:CompleteByBags(partner)
	if not partner then return end
	partner = string.lower(partner)
	local i = 1
	while i <= table.getn(self.db.trades) do
		local t = self.db.trades[i]
		local id = itemId(t.link)
		local expected = 0
		for _, o in ipairs(self.db.trades) do if itemId(o.link) == id then expected = expected + 1 end end
		for _, it in ipairs(self.lootItems) do if it.id == id then expected = expected + (it.bags or 0) end end
		if string.lower(t.char) == partner and bagCount(id) < expected then
			self:Debug("trade by bags: " .. t.link .. " => " .. t.char)
			self:ValidateTrade(i, true)      -- removes entry i
		else
			i = i + 1
		end
	end
end

function X:OnTradeComplete()
	local snap = self.tradeSnap
	self.tradeSnap = nil
	self.tradeCheck = nil
	if snap and table.getn(snap.ids) > 0 then
		self:CompleteTrade(snap)
	elseif snap then
		self:CompleteByBags(snap.partner)
	end
end

-------------------------------------------------------------------------------
-- Once a second: warnings when a trade window is about to close, timers refresh
-------------------------------------------------------------------------------
X.tradeTick = 0
X.warned = {}
function X:TradeTick(elapsed)
	local tc = self.tradeCheck
	if tc then
		tc.t = tc.t + (elapsed or 0)
		if tc.t >= 1 then
			self.tradeCheck = nil
			-- an offered item that is no longer in the bags/trade window was given away
			local gone = { partner = tc.snap.partner, ids = {} }
			for _, id in ipairs(tc.snap.ids) do
				if bagCount(id) < (tc.snap.totals[id] or 0) then table.insert(gone.ids, id) end
			end
			self:Debug("trade closed check: " .. table.getn(gone.ids) .. " item(s) left the bags")
			if table.getn(tc.snap.ids) > 0 then self:CompleteTrade(gone) else self:CompleteByBags(tc.snap.partner) end
		end
	end
	if self.pendingTrade then
		self.pendingTrade.t = self.pendingTrade.t + (elapsed or 0)
		if self.pendingTrade.t > 5 then
			self:Print("The trade window did not open (is " .. self.pendingTrade.char .. " in range?).")
			self.pendingTrade = nil
		end
	end
	self.tradeTick = self.tradeTick + (elapsed or 0)
	if self.tradeTick < 1 then return end
	self.tradeTick = 0
	if not self.db then return end
	local any = false
	local function check(link, id, exp)
		local left = self:TimeLeft(exp)
		if not left then return end
		any = true
		local k = tostring(id) .. ":" .. tostring(exp)
		if left <= 0 then
			if self.warned[k] ~= 2 then self.warned[k] = 2; self:Print("|cffff4040Trade window closed|r for " .. link .. ".") end
		elseif left <= 120 and not self.warned[k] then
			self.warned[k] = 1
			self:Print("|cffff8040" .. link .. ": less than 2 minutes left to trade it.|r")
		end
	end
	for _, it in ipairs(self.lootItems) do
		for _, e in ipairs(it.bagExp or {}) do check(it.link, it.id, e) end
	end
	for _, t in ipairs(self.db.trades) do check(t.link, itemId(t.link), t.exp) end
	if any and self.UI then self.UI:RefreshTimers() end
end
