-- Commands.lua : /epgp slash commands
local X = SkullEPGP

SLASH_SKULLEPGP1 = "/epgp"
SLASH_SKULLEPGP2 = "/skullepgp"

local function help()
	X:Print("|cffffd700/epgp commands|r")
	X:Print("  /epgp - open/close the window (or click the minimap button)")
	X:Print("  /epgp announce [item] [xN] [seconds] - announce the item in raid warning and open bidding")
	X:Print("  /epgp close | cancel | award [player] - close / cancel / award the current bidding round")
	X:Print("  /epgp bid <player> <MIN|NEED|MAX> - add a bid manually")
	X:Print("  /epgp show <player> - show EP / GP / PR")
	X:Print("  /epgp set <player> <ep> <gp>  |  /epgp ep <player> <+/-n>  |  /epgp gp <player> <+/-n>")
	X:Print("  /epgp raidep <n> - give EP to the whole raid  |  /epgp remove <player>")
	X:Print("  /epgp basegp <n> - priority = EP / (GP + n)  (also set by the \"baseGP\" key of an imported JSON)")
	X:Print("  /epgp sync - send everybody's priority to the group (same as the Synchronize button)")
	X:Print("  /epgp publish - broadcast priorities to players (player addon)")
	X:Print("  /epgp cost <MIN|NEED|MAX> <n>  |  /epgp duration <s>  |  /epgp quality <0-5> (0 poor ... 4 epic, 5 legendary)  |  /epgp auto <on|off>")
	X:Print("  /epgp countdown full|reduced|off - chat countdown during bidding (default full: 10 s text + 3, 2, 1)")
	X:Print("  /epgp chatbudget <messages> <seconds>  |  chatgap <s>  |  chatstat - chat anti-spam budget of the addon (default 10 messages in 55 s)")
	X:Print("  /epgp chattest <count> <interval> [same] [say|party|raid|guild] - sends messages to measure the server's mute limit  |  /epgp chattest stop")
	X:Print("  /epgp autoloot [on|off] - master looter: auto-loot items below the minimum quality + coins (never bind-on-pickup; hold SHIFT to skip)")
	X:Print("  /epgp off | on - disable / enable the addon by hand (same as right-click on the minimap button)")
	X:Print("  /epgp minimap [on|off] - show/hide the minimap button")
	X:Print("  /epgp scan - re-read the open loot window  |  /epgp debug - toggle loot detection debug output")
	X:Print("  /epgp clear - empty the list of loot to distribute (bags and corpses)")
	X:Print("  /epgp reset - reset window size and position")
end

SlashCmdList["SKULLEPGP"] = function(msg)
	if not X.db then return end
	msg = X.Trim(msg or "")
	local words = {}
	for w in string.gfind(msg, "%S+") do table.insert(words, w) end
	local cmd = words[1] and string.lower(words[1]) or ""
	if cmd == "off" or cmd == "disable" then X:SetDisabled(true); return end
	if cmd == "on" or cmd == "enable" then X:SetDisabled(false); return end
	if not X:Active() and cmd ~= "help" and cmd ~= "?" and cmd ~= "debug" then
		X:Print(X.INACTIVE_MSG)
		return
	end

	if cmd == "" then
		X.UI:Toggle()

	elseif cmd == "help" or cmd == "?" then
		help()

	elseif cmd == "announce" then
		local _, _, link = string.find(msg, "(|c%x+|Hitem:[^|]+|h%[.-%]|h|r)")
		if not link then
			X:Print("Usage: /epgp announce [item] [xN] [seconds]  (shift-click the item)")
			return
		end
		local _, _, after = string.find(msg, "|h|r(.*)$")
		after = " " .. (after or "")
		local _, _, cnt = string.find(after, "%sx(%d+)")
		local _, _, secs = string.find(string.gsub(after, "%sx%d+", ""), "(%d+)")
		X:StartAuction(link, secs, cnt)

	elseif cmd == "close" then
		X:CloseAuction()

	elseif cmd == "cancel" then
		X:CancelAuction()

	elseif cmd == "award" then
		local key
		if words[2] then
			if not X.auction then X:Print("No bidding round."); return end
			key = X:KeyFor(words[2])
		end
		X:Award(key)

	elseif cmd == "bid" then
		local who, bid = words[2], words[3] and string.upper(words[3])
		if not who or not (bid == "MIN" or bid == "NEED" or bid == "MAX") then
			X:Print("Usage: /epgp bid <player> <MIN|NEED|MAX>")
			return
		end
		if not (X.auction and X.auction.state == "open") then X:Print("No bidding round is open."); return end
		if not X:RegisterBid(who, bid) then X:Print("Bid not registered (one choice per announcement, only NEED -> MAX allowed; or player not in the group).") end

	elseif cmd == "show" then
		local main = X:FindMain(words[2])
		if not main then X:Print("Player not found: " .. tostring(words[2])); return end
		local d = X.db.players[main]
		X:Print(string.format("%s: EP %s / GP %s / PR %.2f", X:PlayerName(main), X:Round(d.ep, 2), X:Round(d.gp, 2), X:GetPR(main)))

	elseif cmd == "set" then
		local ep, gp = tonumber(words[3]), tonumber(words[4])
		if not words[2] or not ep or not gp then X:Print("Usage: /epgp set <player> <ep> <gp>"); return end
		local main = X:SetPlayer(words[2], ep, gp)
		X:Print(main .. ": EP " .. ep .. " / GP " .. gp)
		X.UI:RefreshAll()

	elseif cmd == "ep" or cmd == "gp" then
		local n = tonumber(words[3])
		if not words[2] or not n then X:Print("Usage: /epgp " .. cmd .. " <player> <+/-n>"); return end
		local main, total
		if cmd == "ep" then main, total = X:AddEP(words[2], n) else main, total = X:AddGP(words[2], n, "manual") end
		if main then X:Print(string.format("%s: %s %+d (total %s)", main, string.upper(cmd), n, X:Round(total, 2))) else X:Print("Player not found: " .. words[2]) end
		X.UI:RefreshAll()

	elseif cmd == "raidep" then
		local n = tonumber(words[2])
		if not n or n == 0 then X:Print("Usage: /epgp raidep <n>"); return end
		X:AwardRaidEP(n)
		X.UI:RefreshAll()

	elseif cmd == "remove" then
		local main = words[2] and X:RemovePlayer(words[2])
		if main then X:Print(main .. " removed.") else X:Print("Player not found.") end
		X.UI:RefreshAll()

	elseif cmd == "sync" then
		X:SyncPlayers()

	elseif cmd == "publish" then
		X:Print("Priorities broadcast (" .. X:Publish() .. " addon message(s)).")

	elseif cmd == "cost" then
		local k, n = words[2] and string.upper(words[2]), tonumber(words[3])
		if (k == "MIN" or k == "NEED" or k == "MAX") and n and n > 0 then
			X.db.costs[k] = n
			X:SyncConfig()
			X:Print(k .. " cost = " .. n .. " GP")
			X.UI:RefreshAll()
		else
			X:Print("Usage: /epgp cost <MIN|NEED|MAX> <n>")
		end

	elseif cmd == "basegp" then
		local n = tonumber(words[2])
		if n and n >= 0 then
			X.db.baseGP = n
			X:SyncConfig()
			X:Print("Priority = EP / (GP + " .. n .. ")")
			X.UI:RefreshAll()
			X:Publish()
		else
			X:Print("Usage: /epgp basegp <n>   (now " .. tostring(X.db.baseGP or 0) .. ")")
		end

	elseif cmd == "duration" then
		local n = tonumber(words[2])
		if n and n >= 5 and n <= 300 then X.db.duration = n; X:Print("Bidding duration: " .. n .. " s"); X.UI:RefreshAll()
		else X:Print("Usage: /epgp duration <5-300>") end

	elseif cmd == "countdown" then
		local v = words[2]
		if v == "full" or v == "reduced" or v == "off" then
			X.db.countdown = v
			X:Print("Chat countdown: " .. v .. " (applies to the next announcement)")
		else
			X:Print("Usage: /epgp countdown full|reduced|off   (now " .. (X.db.countdown or "full") .. "). full = 10 s text + 3, 2, 1; reduced = 10 s text only; off = none.")
		end

	elseif cmd == "chatgap" then
		local n = tonumber(words[2])
		if n and n >= 0 and n <= 5 then X.db.chatGap = n; X:Print("Minimum delay between two chat messages: " .. n .. " s")
		else X:Print("Usage: /epgp chatgap <0-5>   (now " .. tostring(X.db.chatGap or 0.5) .. " s)") end

	elseif cmd == "chatbudget" then
		local l, w = tonumber(words[2]), tonumber(words[3])
		if l and w and l >= 1 and l <= 50 and w >= 1 and w <= 60 then
			X.db.chatLimit, X.db.chatWindow = l, w
			X:Print(string.format("Chat budget: at most %d message(s) in any %d second(s)", l, w))
		else
			X:Print(string.format("Usage: /epgp chatbudget <messages> <seconds>   (now %d in %d s). Anti-spam: the addon never sends more than this; countdown digits are skipped when the window is nearly full.", X.db.chatLimit or 10, X.db.chatWindow or 55))
		end

	elseif cmd == "chatstat" then
		X:Print(string.format("Chat budget: %d message(s) sent in the last %d s (limit %d), %d message(s) waiting, minimum gap %.2f s",
			X:ChatUsed(), X:ChatWindow(), X.db.chatLimit or 10, table.getn(X.chatQ), X:ChatGap()))

	elseif cmd == "chattest" then
		-- measures the server's limit: sends n numbered messages in /say, one every <interval> seconds (0 = all at once)
		if words[2] == "stop" then X.chatTest = nil; X:Print("Chat test stopped."); return end
		local n, iv = tonumber(words[2]), tonumber(words[3])
		local same, chan = false, "SAY"
		for k = 4, 5 do
			local w = words[k]
			if w == "same" then same = true
			elseif w == "raid" or w == "party" or w == "say" or w == "guild" then chan = string.upper(w) end
		end
		if n and iv and n >= 1 and n <= 60 and iv >= 0 and iv <= 10 then
			X.chatTest = { n = n, interval = iv, sent = 0, t = iv, start = GetTime(), same = same, chan = chan }
			X:Print(string.format("Chat test: %d %s message(s) in /%s, one every %.1f s. Watch for the moment you get muted.", n, same and "identical" or "different", string.lower(chan), iv))
		else
			X:Print("Usage: /epgp chattest <count 1-60> <interval seconds 0-10> [same] [say|party|raid|guild]   (/epgp chattest stop)")
		end

	elseif cmd == "quality" then
		local n = tonumber(words[2])
		if n and n >= 0 and n <= 5 then
			X.db.minQuality = n
			X:Print("Minimum quality of listed items: " .. X:QualityLabel(n) .. " (" .. n .. ")")
			X:ScanLoot(); X.UI:RefreshLoot()
		else X:Print("Usage: /epgp quality <0-5>") end

	elseif cmd == "minimap" then
		X.db.minimapHidden = (words[2] == "off") or (words[2] == nil and not X.db.minimapHidden)
		X.Minimap:Apply()
		X:Print("Minimap button: " .. (X.db.minimapHidden and "hidden" or "shown"))

	elseif cmd == "autoloot" then
		if words[2] == "on" then X.db.autoLoot = true elseif words[2] == "off" then X.db.autoLoot = false else X.db.autoLoot = not X.db.autoLoot end
		X:Print("Auto-loot below " .. X:QualityLabel(X.db.minQuality) .. " + coins (not bind-on-pickup): " .. (X.db.autoLoot and "ON" or "OFF"))
		X.UI:RefreshLoot()

	elseif cmd == "auto" then
		X.db.autoOpen = (words[2] ~= "off")
		X:Print("Open the window automatically when looting: " .. (X.db.autoOpen and "yes" or "no"))

	elseif cmd == "scan" then
		X:ScanLoot()
		X.UI:Show(1)
		X:Print(table.getn(X.lootItems) .. " item(s) found in the loot window (min quality " .. X.db.minQuality .. ").")

	elseif cmd == "clear" then
		X:ClearBagItems()
		X:Print("Loot list cleared.")

	elseif cmd == "debug" then
		X.db.debug = not X.db.debug
		X:Print("Debug output: " .. (X.db.debug and "ON (open a corpse and copy the [debug] lines)" or "OFF"))

	elseif cmd == "reset" then
		X.UI:ResetFrame()
		X:Print("Window size and position reset.")

	else
		help()
	end
end
