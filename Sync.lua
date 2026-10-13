-- Sync.lua : officer mode (master looter / group leader only) and priority synchronisation between officers.
--
-- The officer addon is only active for the master looter and the raid (party) leader. Everybody else can
-- keep it installed without it doing anything. The two officers keep EP/GP, costs, base GP and the award
-- log in sync through addon messages (prefix SKULLEPGP, messages starting with "S"):
--   SQ;<rev>                              "who has newer data than rev?"
--   SU;<rv>;<name>;<ep>;<gp>;<alts>       one player changed (alts separated by |)
--   SD;<rv>;<name>                        one player removed
--   SF;<rev>;<replace 0|1>                full state begins
--   SP;<name,ep,gp,rv,alts>;<...>         full state: players
--   SE;<rev>;<count>                      full state ends (replace: players not listed are removed)
--   SC;<rv>;<MIN>;<NEED>;<MAX>;<baseGP>   costs / base GP
--   SL;<json>                             one log entry (awards, EP/GP edits...)
-- Every player carries a revision number "rv"; the newest revision wins.
local X = SkullEPGP
local J = SkullEPGP_Json

-------------------------------------------------------------------------------
-- Who is an officer ?
-------------------------------------------------------------------------------
function X:Grouped()
	return (GetNumRaidMembers() or 0) > 0 or (GetNumPartyMembers() or 0) > 0
end

function X:IsLeader()
	if (GetNumRaidMembers() or 0) > 0 then return IsRaidLeader() and true or false end
	if (GetNumPartyMembers() or 0) > 0 then return (IsPartyLeader and IsPartyLeader()) and true or false end
	return false
end

-- is the loot method "Master Looter" ?
function X:MasterMode()
	local method = GetLootMethod()
	return method == "master"
end

-- master looter or leader of the group, and only while the loot method is Master Looter
function X:IsOfficer()
	return not (self.db and self.db.disabled) and self:MasterMode() and (self:IsLeader() or self:PlayerIsML())
end

-- The officer addon works for officers; when you are not in a group at all it stays usable to prepare things
-- (import, edit values). In a group it does nothing unless the loot method is Master Looter and you are the
-- master looter or the leader.
function X:Active()
	if self.db and self.db.disabled then return false end
	return (not self:Grouped()) or self:IsOfficer()
end

-- manual switch (right-click on the minimap button, /epgp on|off): the addon does nothing while it is off
function X:SetDisabled(flag)
	if not self.db then return end
	self.db.disabled = flag and true or false
	if self.db.disabled then
		self.auction = nil
		if self.UI then self.UI:HideWindow() end
	end
	self.officerState = nil
	if self.db.disabled then
		self:Print("Officer mode |cffff8080OFF|r (disabled by hand). Right-click the minimap button or type /epgp on to enable it again.")
	else
		self:Print("Officer mode enabled again.")
	end
	self:CheckStatus()
	if self.Minimap then self.Minimap:Apply() end
end

-- Is this player (by name) the leader or the master looter of the group ?
function X:IsOfficerName(name)
	if not name then return false end
	name = string.lower(name)
	local nraid = GetNumRaidMembers() or 0
	if nraid > 0 then
		for i = 1, nraid do
			local n, rank = GetRaidRosterInfo(i)
			if n and string.lower(n) == name and rank == 2 then return true end
		end
	else
		for i = 1, (GetNumPartyMembers() or 0) do
			local u = "party" .. i
			local n = UnitName(u)
			if n and string.lower(n) == name and UnitIsPartyLeader and UnitIsPartyLeader(u) then return true end
		end
	end
	local method, partyID, raidID = GetLootMethod()
	if method == "master" then
		local u
		if raidID and raidID > 0 then u = "raid" .. raidID elseif partyID and partyID > 0 then u = "party" .. partyID end
		local n = u and UnitName(u)
		if n and string.lower(n) == name then return true end
	end
	return false
end

X.officerState = nil
X.statusTick = 0
function X:StatusTick(elapsed)
	self.statusTick = self.statusTick + (elapsed or 0)
	if self.statusTick < 2 then return end
	self.statusTick = 0
	self:CheckStatus()
end

function X:CheckStatus()
	if not self.db then return end
	local active = self:Active()
	local sync = self:Grouped() and self:IsOfficer()
	local state = (active and "A" or "I") .. (sync and "S" or "-")
	if state == self.officerState then return end
	local first = (self.officerState == nil)
	self.officerState = state
	if not first then
		if active then
			if self:Grouped() then
				self:Print("Officer mode |cff33cc33ON|r (" .. (self:PlayerIsML() and "master looter" or "group leader") .. ").")
			else
				self:Print("Officer mode ON (not in a group).")
			end
		else
			if self.db.disabled then
				self:Print("Officer mode |cffff8080OFF|r: disabled by hand (right-click the minimap button to enable it).")
			elseif not self:MasterMode() then
				self:Print("Officer mode |cffff8080OFF|r: the loot method is not Master Looter.")
			else
				self:Print("Officer mode |cffff8080OFF|r: you are neither master looter nor group leader.")
			end
		end
	end
	if not active and self.UI then self.UI:HideWindow() end
	if sync then self:RequestSync() end
end

-------------------------------------------------------------------------------
-- Sending (queued: one message every 0.1 s)
-------------------------------------------------------------------------------
X.outq = {}
X.outTick = 0
function X:SendSync(text)
	if not self:Grouped() then return end
	table.insert(self.outq, text)
end

function X:FlushSync(elapsed)
	if table.getn(self.outq) == 0 then return end
	self.outTick = self.outTick + (elapsed or 0)
	if self.outTick < 0.1 then return end
	self.outTick = 0
	local text = table.remove(self.outq, 1)
	self:Comm(text)
end

local function altsString(d)
	if d.alts and table.getn(d.alts) > 0 then return table.concat(d.alts, "|") end
	return ""
end

local function split(s, sep)
	local out, pos = {}, 1
	while true do
		local a = string.find(s, sep, pos, true)
		if not a then
			table.insert(out, string.sub(s, pos))
			break
		end
		table.insert(out, string.sub(s, pos, a - 1))
		pos = a + string.len(sep)
	end
	return out
end

function X:NextRev()
	self.db.rev = (self.db.rev or 0) + 1
	return self.db.rev
end

-- local change of one player
function X:Touch(main)
	local d = main and self.db.players[main]
	if not d then return end
	d.rv = self:NextRev()
	self:SendSync(string.format("SU;%d;%s;%s;%s;%s", d.rv, main, self:Round(d.ep, 4), self:Round(d.gp, 4), altsString(d)))
end

function X:TouchRemoved(main)
	self:SendSync(string.format("SD;%d;%s", self:NextRev(), main))
end

function X:SyncConfig()
	local c = self.db.costs
	self.db.cfgRev = (self.db.cfgRev or 0) + 1
	self:SendSync(string.format("SC;%d;%s;%s;%s;%s", self.db.cfgRev, c.MIN, c.NEED, c.MAX, self.db.baseGP or 0))
	self:Comm(self:CfgString())      -- the player addons too
end

-- the whole state (after an import, or as an answer to SQ)
function X:SendFullState(replace)
	local rev = self.db.rev or 0
	self:SendSync("SF;" .. rev .. ";" .. (replace and 1 or 0))
	local cur, count = "SP", 0
	for _, p in ipairs(self:SortedPlayers()) do
		local d = self.db.players[p.name]
		if d then
			local piece = ";" .. p.name .. "," .. self:Round(d.ep, 4) .. "," .. self:Round(d.gp, 4) .. "," .. (d.rv or 0) .. "," .. altsString(d)
			if string.len(cur) + string.len(piece) > 225 then
				self:SendSync(cur)
				cur = "SP"
			end
			cur = cur .. piece
			count = count + 1
		end
	end
	if cur ~= "SP" then self:SendSync(cur) end
	self:SendSync("SE;" .. rev .. ";" .. count)
	local c = self.db.costs
	self:SendSync(string.format("SC;%d;%s;%s;%s;%s", self.db.cfgRev or 0, c.MIN, c.NEED, c.MAX, self.db.baseGP or 0))
end

-- after an import: every player gets a fresh revision, then the full state is sent
function X:SyncAfterImport(replace)
	local rev = self:NextRev()
	for _, d in pairs(self.db.players) do d.rv = rev end
	self.db.cfgRev = (self.db.cfgRev or 0) + 1
	self:SendFullState(replace)
end

X.lastSQ = -100
function X:RequestSync()
	local now = GetTime()
	if now - self.lastSQ < 10 then return end
	self.lastSQ = now
	self:SendSync("SQ;" .. (self.db.rev or 0))
end

function X:SendLog(entry)
	if self.noSync or not self:Grouped() or not self:IsOfficer() then return end
	local o = {}
	for k, v in pairs(entry) do
		if k ~= "link" then o[k] = v end
	end
	local text = "SL;" .. J.Encode(o)
	if string.len(text) > 235 then
		o.item = nil
		text = "SL;" .. J.Encode(o)
	end
	self:SendSync(text)
end

-------------------------------------------------------------------------------
-- Receiving
-------------------------------------------------------------------------------
local function applyPlayer(X, name, ep, gp, rv, alts)
	local d = X.db.players[name]
	if d and (d.rv or 0) >= rv then return false end
	if not d then
		d = {}
		X.db.players[name] = d
	end
	d.ep, d.gp, d.rv = ep, gp, rv
	d.alts = alts
	if rv > (X.db.rev or 0) then X.db.rev = rv end
	return true
end

local function parseAlts(s)
	local alts = {}
	if s and s ~= "" then
		for a in string.gfind(s, "[^|]+") do table.insert(alts, a) end
	end
	return alts
end

function X:HandleSync(text, sender)
	if not self.db or not self:Grouped() or not self:IsOfficer() then return end
	if not self:IsOfficerName(sender) then return end
	local f = split(text, ";")
	local tag = f[1]
	local changed = false
	if tag == "SQ" then
		if (tonumber(f[2]) or 0) < (self.db.rev or 0) then
			local now = GetTime()
			if now - (self.lastFull or -100) >= 10 then
				self.lastFull = now
				self:SendFullState(false)
			end
		end
	elseif tag == "SU" then
		local rv, ep, gp = tonumber(f[2]), tonumber(f[4]), tonumber(f[5])
		if rv and f[3] and ep and gp then changed = applyPlayer(self, f[3], ep, gp, rv, parseAlts(f[6])) end
	elseif tag == "SD" then
		local rv = tonumber(f[2])
		local d = f[3] and self.db.players[f[3]]
		if rv and d and rv >= (d.rv or 0) then
			self.db.players[f[3]] = nil
			if rv > (self.db.rev or 0) then self.db.rev = rv end
			changed = true
		end
	elseif tag == "SF" then
		self.fullIn = { seen = {}, replace = (f[3] == "1") }
	elseif tag == "SP" then
		local fi = self.fullIn
		for i = 2, table.getn(f) do
			local e = split(f[i], ",")
			local ep, gp, rv = tonumber(e[2]), tonumber(e[3]), tonumber(e[4])
			if e[1] and e[1] ~= "" and ep and gp and rv then
				if fi then fi.seen[e[1]] = true end
				if applyPlayer(self, e[1], ep, gp, rv, parseAlts(e[5])) then changed = true end
			end
		end
	elseif tag == "SE" then
		local fi, rev = self.fullIn, tonumber(f[2])
		if fi and fi.replace and rev then
			for name, d in pairs(self.db.players) do
				if not fi.seen[name] and (d.rv or 0) < rev then
					self.db.players[name] = nil
					changed = true
				end
			end
		end
		self.fullIn = nil
		if rev and rev > (self.db.rev or 0) then self.db.rev = rev end
		changed = true
	elseif tag == "SC" then
		local rv = tonumber(f[2])
		local mn, nd, mx, base = tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
		if rv and rv > (self.db.cfgRev or 0) and mn and nd and mx then
			self.db.cfgRev = rv
			self.db.costs.MIN, self.db.costs.NEED, self.db.costs.MAX = mn, nd, mx
			if base then self.db.baseGP = base end
			changed = true
		end
	elseif tag == "SL" then
		local ok, e = pcall(J.Decode, string.sub(text, 4))
		if ok and type(e) == "table" and e.type then
			self.noSync = true
			self:AddLog(e)
			self.noSync = false
			if e.type == "IMPORT" then self.db.logStart = table.getn(self.db.log) + 1 end
		end
	end
	if changed then
		self:RebuildIndex()
		if self.UI then self.UI:RefreshAll() end
	end
end
