-- UI.lua : officer window (Loot / Players / Import-Export / Log) - resizable
local X = SkullEPGP
local UI = {}
X.UI = UI

local EDIT_BD = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local WIN_BD = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
local BID_COLORS = { MIN = "|cff33cc33", NEED = "|cffff8000", MAX = "|cffff3333", ROLL = "|cffaaaaaa" }

local DEFAULT_W, DEFAULT_H = 580, 600
local MIN_W, MIN_H = 520, 470
local MAX_W, MAX_H = 1000, 950
local PANEL_TOP, PANEL_SIDE, PANEL_BOTTOM = 66, 20, 24   -- panel insets inside the window

local counter = 0
local function NewName()
	counter = counter + 1
	return "SkullEPGPUI" .. counter
end

-- Text(parent, text, font, width, justify) : width is optional (omit it when the text is anchored on both sides)
local function Text(parent, text, font, w, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	if text then fs:SetText(text) end
	if w then fs:SetWidth(w) end
	fs:SetJustifyH(justify or "LEFT")
	return fs
end

local function Button(parent, text, w, h, onclick)
	local b = CreateFrame("Button", NewName(), parent, "UIPanelButtonTemplate")
	b:SetWidth(w)
	b:SetHeight(h or 22)
	b:SetText(text)
	b:SetScript("OnClick", onclick)
	return b
end

local function Edit(parent, w, h)
	local e = CreateFrame("EditBox", NewName(), parent)
	if w then e:SetWidth(w) end
	e:SetHeight(h or 20)
	e:SetAutoFocus(false)
	e:SetFontObject(ChatFontNormal)
	e:SetBackdrop(EDIT_BD)
	e:SetBackdropColor(0, 0, 0, 0.6)
	e:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	e:SetTextInsets(5, 5, 2, 2)
	e:SetScript("OnEscapePressed", function() this:ClearFocus() end)
	e:SetScript("OnEnterPressed", function() this:ClearFocus() end)
	return e
end

local function ItemTooltip(frame, getLink)
	frame:SetScript("OnEnter", function()
		local link = getLink(this)
		if link then
			local _, _, str = string.find(link, "|H(item:[^|]+)|h")
			if str then
				GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
				GameTooltip:SetHyperlink(str)
				GameTooltip:Show()
			end
		end
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local HL = "Interface\\QuestFrame\\UI-QuestTitleHighlight"

-- A row stretched over the full width of its panel (TOPLEFT + TOPRIGHT anchors)
local function StretchRow(parent, y, h, rightInset)
	local row = CreateFrame("Button", NewName(), parent)
	row:SetHeight(h)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", rightInset or 0, y)
	row:SetHighlightTexture(HL)
	row.sel = row:CreateTexture(nil, "BACKGROUND")
	row.sel:SetAllPoints(row)
	row.sel:SetTexture(1, 0.82, 0, 0.18)
	row.sel:Hide()
	return row
end

-- A column cell anchored to the RIGHT edge of its parent (so columns follow the window width)
local function RightCell(parent, font, right, w)
	local fs = Text(parent, "", font or "GameFontHighlightSmall", w)
	fs:SetPoint("RIGHT", parent, "RIGHT", right, 0)
	return fs
end

-------------------------------------------------------------------------------
-- Main window
-------------------------------------------------------------------------------
local f = CreateFrame("Frame", "SkullEPGPFrame", UIParent)
UI.frame = f
f:SetWidth(DEFAULT_W)
f:SetHeight(DEFAULT_H)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
f:SetBackdrop(WIN_BD)
f:SetFrameStrata("DIALOG")
f:SetMovable(true)
f:SetResizable(true)
f:SetMinResize(MIN_W, MIN_H)
f:SetMaxResize(MAX_W, MAX_H)
f:EnableMouse(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", function() this:StartMoving() end)
f:SetScript("OnDragStop", function() this:StopMovingOrSizing(); UI:SaveFrame() end)
f:Hide()
table.insert(UISpecialFrames, "SkullEPGPFrame")

local title = Text(f, "Skull EPGP - Officer", "GameFontNormalLarge")
title:SetPoint("TOP", f, "TOP", 0, -16)
local close = CreateFrame("Button", NewName(), f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)

-- Resize grip (bottom-right corner)
local grip = CreateFrame("Button", NewName(), f)
grip:SetWidth(16)
grip:SetHeight(16)
grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
grip:SetFrameLevel(f:GetFrameLevel() + 20)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); UI:SaveFrame() end)
grip:SetScript("OnEnter", function()
	GameTooltip:SetOwner(this, "ANCHOR_LEFT")
	GameTooltip:SetText("Drag to resize")
	GameTooltip:Show()
end)
grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

local panels = {}
local tabs = {}
local function MakePanel()
	local p = CreateFrame("Frame", NewName(), f)
	p:SetPoint("TOPLEFT", f, "TOPLEFT", PANEL_SIDE, -PANEL_TOP)
	p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PANEL_SIDE, PANEL_BOTTOM)
	p:Hide()
	table.insert(panels, p)
	return p
end

function UI:ShowTab(i)
	for k = 1, table.getn(panels) do
		if k == i then panels[k]:Show() else panels[k]:Hide() end
	end
	self.tab = i
	self:Layout()
end

function UI:Show(tab)
	f:Show()
	self:ShowTab(tab or self.tab or 1)
end

function UI:HideWindow()
	f:Hide()
end

function UI:Toggle()
	if f:IsShown() then f:Hide(); return end
	if not X:Active() then X:Print(X.INACTIVE_MSG); return end
	self:Show()
end

-- panel index -> tab label (panel 5 = Trades is created last but its tab is shown second)
local tabNames = { "Loot", "Players", "Import / Export", "Log", "Trades" }
local tabW = { 70, 80, 110, 60, 100 }
local tabOrder = { 1, 5, 2, 3, 4 }
do
	local prev
	for _, i in ipairs(tabOrder) do
		local idx = i
		local b = Button(f, tabNames[i], tabW[i], 22, function() UI:ShowTab(idx) end)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -38) end
		prev = b
		tabs[i] = b
	end
end

-- Saved size / position
function UI:SaveFrame()
	if not X.db then return end
	X.db.frameW, X.db.frameH = f:GetWidth(), f:GetHeight()
	local left, top = f:GetLeft(), f:GetTop()
	if left and top then X.db.frameX, X.db.frameY = left, top end
end

function UI:ApplySaved()
	if not X.db then return end
	local w, h = X.db.frameW, X.db.frameH
	if w and h then
		f:SetWidth(math.min(MAX_W, math.max(MIN_W, w)))
		f:SetHeight(math.min(MAX_H, math.max(MIN_H, h)))
	end
	if X.db.frameX and X.db.frameY then
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", X.db.frameX, X.db.frameY)
	end
end

function UI:ResetFrame()
	if X.db then X.db.frameW, X.db.frameH, X.db.frameX, X.db.frameY = nil, nil, nil, nil end
	f:SetWidth(DEFAULT_W)
	f:SetHeight(DEFAULT_H)
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	self:Layout()
end

-------------------------------------------------------------------------------
-- Tab 1 : Loot / Bidding
-------------------------------------------------------------------------------
local p1 = MakePanel()
local LOOT_ROWS, RANK_MAX = 5, 30
local RANK_TOP = 242   -- y of the first ranking row

local h1 = Text(p1, "Items in the loot window", "GameFontNormal")
h1:SetPoint("TOPLEFT", p1, "TOPLEFT", 0, 0)
local btnScan = Button(p1, "Rescan", 70, 18, function()
	X:ScanLoot()
	UI:RefreshLoot()
	if table.getn(X.lootItems) == 0 then
		X:Print("No item found (is the loot window open? minimum quality = " .. X.db.minQuality .. ", see /epgp quality).")
	end
end)
btnScan:SetPoint("TOPRIGHT", p1, "TOPRIGHT", 0, 2)

local lootRows = {}
for i = 1, LOOT_ROWS do
	local idx = i
	local row = StretchRow(p1, -22 - (i - 1) * 23, 22)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetWidth(20)
	row.icon:SetHeight(20)
	row.icon:SetPoint("LEFT", row, "LEFT", 22, 0)
	row.del = Button(row, "x", 18, 18, function()
		local it = X.lootItems and X.lootItems[idx]
		if it then X:RemoveLootItem(it) end
	end)
	row.del:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.del:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText("Remove from the list")
		GameTooltip:AddLine("Removes this item (all copies) from the list of items to announce. It will not come back when you reopen the same corpse.", 1, 1, 1, 1)
		GameTooltip:Show()
	end)
	row.del:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.btn = Button(row, "Announce", 84, 20, function()
		local it = X.lootItems and X.lootItems[idx]
		if it then UI:Announce(it.link, it.count) end
	end)
	row.btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.take = Button(row, "Take", 50, 20, function()
		local it = X.lootItems and X.lootItems[idx]
		if it then X:TakeItem(it) end
	end)
	row.take:SetPoint("RIGHT", row.btn, "LEFT", -4, 0)
	row.take:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText("Take")
		GameTooltip:AddLine("Master looter: picks the item up into your own bags so you can trade it to the winner later. It stays in this list until it is awarded.", 1, 1, 1, 1)
		GameTooltip:Show()
	end)
	row.take:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.assign = Button(row, "Assign", 50, 20, function()
		local it = X.lootItems and X.lootItems[idx]
		if it then UI:ShowAssignMenu(it, this) end
	end)
	row.assign:SetPoint("RIGHT", row.take, "LEFT", -4, 0)
	row.assign:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText("Assign")
		GameTooltip:AddLine("Gives one copy directly to a player you pick in the list, without announcing it (no GP). Needs the loot window open (master looter) or the item in your bags.", 1, 1, 1, 1)
		GameTooltip:Show()
	end)
	row.assign:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.text = Text(row, "", "GameFontHighlight")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", row.assign, "LEFT", -6, 0)
	ItemTooltip(row, function() local it = X.lootItems and X.lootItems[idx]; return it and it.link end)
	row:Hide()
	lootRows[i] = row
end

-- Assign menu: one button per candidate, coloured by class
local ASSIGN_COLS, ASSIGN_BW, ASSIGN_BH = 3, 104, 18
local assignFrame = CreateFrame("Frame", "SkullEPGPAssignFrame", UIParent)
assignFrame:SetFrameStrata("DIALOG")
assignFrame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
assignFrame:EnableMouse(true)
assignFrame:Hide()
table.insert(UISpecialFrames, "SkullEPGPAssignFrame")
local assignTitle = Text(assignFrame, "", "GameFontNormal", 300, "CENTER")
assignTitle:SetPoint("TOP", assignFrame, "TOP", 0, -14)
local assignButtons = {}
local assignItem

function UI:ShowAssignMenu(it, anchor)
	if not X:Active() then X:Print(X.INACTIVE_MSG); return end
	assignItem = it
	local names = X:AssignCandidates()
	local n = table.getn(names)
	local rows = math.max(1, math.ceil(n / ASSIGN_COLS))
	assignFrame:SetWidth(ASSIGN_COLS * ASSIGN_BW + 28)
	assignFrame:SetHeight(rows * ASSIGN_BH + 52)
	assignTitle:SetText("Assign " .. it.link .. " to:")
	for i = 1, math.max(n, table.getn(assignButtons)) do
		local b = assignButtons[i]
		if not b and i <= n then
			b = CreateFrame("Button", "SkullEPGPAssignBtn" .. i, assignFrame)
			b:SetWidth(ASSIGN_BW)
			b:SetHeight(ASSIGN_BH)
			b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
			b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			b.text:SetAllPoints(b)
			b:SetScript("OnClick", function()
				local who, item = this.who, assignItem
				assignFrame:Hide()
				if who and item then
					X:Confirm("Assign " .. item.link .. " to " .. who .. "?\nNo announcement, no GP.", function() X:AssignItem(item, who) end)
				end
			end)
			assignButtons[i] = b
		end
		if b then
			if i <= n then
				b.who = names[i]
				b.text:SetText(X:ClassColor(names[i]) .. names[i] .. "|r")
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", assignFrame, "TOPLEFT", 14 + math.mod(i - 1, ASSIGN_COLS) * ASSIGN_BW, -34 - math.floor((i - 1) / ASSIGN_COLS) * ASSIGN_BH)
				b:Show()
			else
				b:Hide()
			end
		end
	end
	local cancel = assignFrame.cancel
	if not cancel then
		cancel = Button(assignFrame, "Cancel", 70, 20, function() assignFrame:Hide() end)
		assignFrame.cancel = cancel
	end
	cancel:ClearAllPoints()
	cancel:SetPoint("BOTTOM", assignFrame, "BOTTOM", 0, 10)
	assignFrame:ClearAllPoints()
	assignFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	assignFrame:Show()
end

local lootEmpty = Text(p1, "No items (open a corpse, click Rescan, or use /epgp announce [item])", "GameFontDisableSmall")
lootEmpty:SetPoint("TOPLEFT", p1, "TOPLEFT", 4, -26)
lootEmpty:SetPoint("TOPRIGHT", p1, "TOPRIGHT", 0, -26)

local durLabel = Text(p1, "Duration (s):", "GameFontNormalSmall")
durLabel:SetPoint("TOPLEFT", p1, "TOPLEFT", 0, -144)
local durBox = Edit(p1, 40, 20)
durBox:SetPoint("LEFT", durLabel, "RIGHT", 6, 0)
durBox:SetNumeric(true)
durBox:SetMaxLetters(3)
local costLabel = Text(p1, "", "GameFontHighlightSmall", 190, "RIGHT")
costLabel:SetPoint("RIGHT", btnScan, "LEFT", -10, 0)

-- Auto-loot checkbox (master looter): items below the minimum quality, never bind-on-pickup
local autoCheck = CreateFrame("CheckButton", "SkullEPGPAutoLootCheck", p1, "UICheckButtonTemplate")
autoCheck:SetWidth(24)
autoCheck:SetHeight(24)
autoCheck:SetPoint("LEFT", durBox, "RIGHT", 14, 0)
getglobal("SkullEPGPAutoLootCheckText"):SetText("Auto-loot below min quality")
autoCheck:SetScript("OnClick", function()
	X.db.autoLoot = (this:GetChecked() and true or false)
end)
autoCheck:SetScript("OnEnter", function()
	GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
	GameTooltip:SetText("Auto-loot")
	GameTooltip:AddLine("As master looter, every item below the minimum quality and the coins are taken when you open a corpse - except bind-on-pickup / soulbound / quest items, which stay in the window. Coins need SuperWoW.", 1, 1, 1, 1)
	GameTooltip:AddLine("Hold SHIFT while opening the corpse to skip it.", 0.7, 0.7, 0.7, 1)
	GameTooltip:Show()
end)
autoCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Minimum quality: drop-down list (same UIDropDownMenu pattern as the old MasterLoot addon).
-- If the drop-down API misbehaves on this client, one button per quality is built instead.
local qLabel = Text(p1, "Min quality:", "GameFontNormalSmall", 70)
qLabel:SetPoint("TOPLEFT", p1, "TOPLEFT", 0, -177)
local qDrop
local qButtons = {}
UI.qMode = "dropdown"

local function SetMinQuality(q)
	X.db.minQuality = q
	if (GetNumLootItems() or 0) > 0 then X:ScanLoot() end
	UI:RefreshLoot()
end

local function QualityDropClicked()
	SetMinQuality(this.value)
end

local function QualityDropInit()
	local level = UIDROPDOWNMENU_MENU_LEVEL or 1
	if level ~= 1 then return end
	for q = 0, 5 do
		local info = {}
		info.text = X:QualityLabel(q)
		info.value = q
		info.checked = (X.db and X.db.minQuality == q) and 1 or nil
		info.hasArrow = false
		info.owner = UIDROPDOWNMENU_OPEN_MENU
		info.func = QualityDropClicked
		UIDropDownMenu_AddButton(info, level)
	end
end

local okDrop = pcall(function()
	qDrop = CreateFrame("Frame", "SkullEPGPQualityDropDown", p1, "UIDropDownMenuTemplate")
	qDrop:SetPoint("TOPLEFT", p1, "TOPLEFT", 56, -167)
	UIDropDownMenu_Initialize(qDrop, QualityDropInit)
	UIDropDownMenu_SetWidth(150, qDrop)
end)

if not okDrop then
	UI.qMode = "buttons"
	if qDrop then qDrop:Hide() end
	for q = 0, 5 do
		local quality = q
		local b = Button(p1, X:QualityLabel(quality), 64, 20, function() SetMinQuality(quality) end)
		if q == 0 then b:SetPoint("TOPLEFT", p1, "TOPLEFT", 72, -170) else b:SetPoint("LEFT", qButtons[q - 1], "RIGHT", 2, 0) end
		qButtons[q] = b
	end
end

local sep = p1:CreateTexture(nil, "ARTWORK")
sep:SetTexture(1, 1, 1, 0.2)
sep:SetHeight(1)
sep:SetPoint("TOPLEFT", p1, "TOPLEFT", 0, -200)
sep:SetPoint("TOPRIGHT", p1, "TOPRIGHT", 0, -200)

local aucTimer = Text(p1, "", "GameFontNormal", 150, "RIGHT")
aucTimer:SetPoint("TOPRIGHT", p1, "TOPRIGHT", 0, -210)
local aucTitle = Text(p1, "", "GameFontNormal")
aucTitle:SetPoint("TOPLEFT", p1, "TOPLEFT", 0, -210)
aucTitle:SetPoint("TOPRIGHT", aucTimer, "TOPLEFT", -6, 0)
local aucHover = CreateFrame("Button", NewName(), p1)
aucHover:SetPoint("TOPLEFT", aucTitle, "TOPLEFT", 0, 0)
aucHover:SetPoint("BOTTOMRIGHT", aucTitle, "BOTTOMRIGHT", 0, 0)
ItemTooltip(aucHover, function() return X.auction and X.auction.link end)

-- Ranking columns (offsets from the right edge): cost, roll, PR, bid, then the name fills the rest
local COL = { cost = { -4, 50 }, roll = { -58, 40 }, pr = { -102, 50 }, bid = { -156, 60 }, nameRight = -222 }

do
	local function hdr(txt, right, w)
		local h = Text(p1, txt, "GameFontNormalSmall", w)
		h:SetPoint("TOPRIGHT", p1, "TOPRIGHT", right, -RANK_TOP + 14)
		return h
	end
	local hr = Text(p1, "#", "GameFontNormalSmall", 22)
	hr:SetPoint("TOPLEFT", p1, "TOPLEFT", 4, -RANK_TOP + 14)
	local hn = Text(p1, "Player", "GameFontNormalSmall", 100)
	hn:SetPoint("TOPLEFT", p1, "TOPLEFT", 28, -RANK_TOP + 14)
	hdr("Bid", COL.bid[1], COL.bid[2])
	hdr("PR", COL.pr[1], COL.pr[2])
	hdr("Roll", COL.roll[1], COL.roll[2])
	hdr("Cost", COL.cost[1], COL.cost[2])
end

local rankRows = {}
for i = 1, RANK_MAX do
	local row = StretchRow(p1, -RANK_TOP - (i - 1) * 18, 18)
	row.cRank = Text(row, "", "GameFontHighlightSmall", 22)
	row.cRank:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.cCost = RightCell(row, nil, COL.cost[1], COL.cost[2])
	row.cRoll = RightCell(row, nil, COL.roll[1], COL.roll[2])
	row.cPR = RightCell(row, nil, COL.pr[1], COL.pr[2])
	row.cBid = RightCell(row, nil, COL.bid[1], COL.bid[2])
	row.cName = Text(row, "", "GameFontHighlightSmall")
	row.cName:SetPoint("LEFT", row, "LEFT", 28, 0)
	row.cName:SetPoint("RIGHT", row, "RIGHT", COL.nameRight, 0)
	row:SetScript("OnClick", function()
		if this.key then
			UI.selectedKey = this.key
			UI:RefreshAuction()
		end
	end)
	row:Hide()
	rankRows[i] = row
end

local moreText = Text(p1, "", "GameFontDisableSmall", 300)

local btnAward = Button(p1, "Award", 100, 24, function() X:Award(UI.selectedKey) end)
btnAward:SetPoint("BOTTOMLEFT", p1, "BOTTOMLEFT", 0, 0)
local btnClose = Button(p1, "Close bids", 100, 24, function() X:CloseAuction() end)
btnClose:SetPoint("LEFT", btnAward, "RIGHT", 6, 0)
local btnCancel = Button(p1, "Cancel", 90, 24, function() X:CancelAuction() end)
btnCancel:SetPoint("LEFT", btnClose, "RIGHT", 6, 0)
local btnRe = Button(p1, "Re-announce", 110, 24, function()
	local a = X.auction
	if a then
		local link, left = a.link, a.remaining or 1
		if a.state == "open" then X:CancelAuction() end
		X.auction = nil
		UI:Announce(link, left)
	end
end)
btnRe:SetPoint("LEFT", btnCancel, "RIGHT", 6, 0)

function UI:Announce(link, count)
	local d = tonumber(durBox:GetText())
	if X:StartAuction(link, d, count) then
		self.selectedKey = nil
	end
end

function UI:RefreshLoot()
	if not X.db then return end
	local items = X.lootItems or {}
	for i = 1, LOOT_ROWS do
		local row, it = lootRows[i], items[i]
		if it then
			row.icon:SetTexture(it.icon)
			local txt = it.link
			if (it.count or 1) > 1 then txt = txt .. " |cffffd700x" .. it.count .. "|r" end
			local bags = it.bags or 0
			if bags > 0 then
				txt = txt .. ((bags == it.count) and " |cff33ccff(in bags)|r" or (" |cff33ccff(" .. bags .. " in bags)|r"))
				-- trade timer of the oldest bind-on-pickup copy
				local soon
				for _, e in ipairs(it.bagExp or {}) do
					if e and e > 0 and (not soon or e < soon) then soon = e end
				end
				if soon then txt = txt .. " |cffffd700(" .. X.FormatLeft(soon - time()) .. ")|r" end
			end
			row.text:SetText(txt)
			local inCorpse = X.lootOpen and ((it.corpses and X.curKey and it.corpses[X.curKey]) or 0) > 0 and X:PlayerIsML()
			if inCorpse then row.take:Enable() else row.take:Disable() end
			if inCorpse or (it.bags or 0) > 0 then row.assign:Enable() else row.assign:Disable() end
			row:Show()
		else
			row:Hide()
		end
	end
	local activeQ = X.db.minQuality or 4
	local head = "Loot: " .. X:QualityLabel(activeQ) .. " or better"
	if table.getn(items) > LOOT_ROWS then head = head .. " |cff888888(" .. LOOT_ROWS .. "/" .. table.getn(items) .. ")|r" end
	h1:SetText(head)
	autoCheck:SetChecked(X.db.autoLoot and 1 or nil)
	local q = X.db.minQuality or 4
	if UI.qMode == "dropdown" then
		UIDropDownMenu_SetText(X:QualityLabel(q), qDrop)
	else
		for i = 0, 5 do
			if i == q then
				qButtons[i]:SetText(">" .. X:QualityLabel(i) .. "<")
				qButtons[i]:LockHighlight()
			else
				qButtons[i]:SetText(X:QualityLabel(i))
				qButtons[i]:UnlockHighlight()
			end
		end
	end
	if table.getn(items) == 0 then
		local slots = GetNumLootItems() or 0
		if slots > 0 then
			lootEmpty:SetText("|cffff8080" .. slots .. " slot(s) in the loot window, none of " .. X:QualityLabel(q) .. "|cffff8080 quality or better.|r Lower the minimum quality below.")
		else
			lootEmpty:SetText("No items (open a corpse, click Rescan, or use /epgp announce [item])")
		end
		lootEmpty:Show()
	else
		lootEmpty:Hide()
	end
	local c = X.db.costs
	costLabel:SetText(string.format("|cff33cc33MIN %d|r  |cffff8000NEED %d|r  |cffff3333MAX %d|r GP", c.MIN, c.NEED, c.MAX))
	if not durBox:HasFocus() then durBox:SetText(tostring(X.db.duration)) end
end

function UI:UpdateTimer()
	local a = X.auction
	if not a then
		aucTimer:SetText("")
	elseif a.state == "open" then
		local r = math.ceil(a.endTime - GetTime())
		if r < 0 then r = 0 end
		aucTimer:SetText("|cffffd700" .. r .. " s|r")
	elseif a.state == "closed" then
		aucTimer:SetText("|cffff8080Bidding closed|r")
	else
		aucTimer:SetText("|cff33cc33Awarded|r")
	end
end

function UI:RankVisible()
	local v = math.floor((f:GetHeight() - PANEL_TOP - PANEL_BOTTOM - RANK_TOP - 36) / 18)
	if v < 3 then v = 3 end
	if v > RANK_MAX then v = RANK_MAX end
	return v
end

function UI:RefreshAuction()
	if not X.db or not f:IsShown() then return end
	local vis = self:RankVisible()
	local a = X.auction
	if not a then
		aucTitle:SetText("|cff888888No bidding round in progress|r")
		for i = 1, RANK_MAX do rankRows[i]:Hide() end
		moreText:SetText("")
		btnAward:Disable(); btnClose:Disable(); btnCancel:Disable(); btnRe:Disable()
		self:UpdateTimer()
		return
	end
	aucTitle:SetText(a.link .. ((a.count or 1) > 1 and (" |cffffd700x" .. (a.remaining or 1) .. " left|r") or ""))
	self:UpdateTimer()
	local rank = X:GetRanking()
	local n = table.getn(rank)
	-- selection: first row by default
	local found = false
	for i = 1, n do if rank[i].key == self.selectedKey then found = true end end
	if not found then self.selectedKey = rank[1] and rank[1].key or nil end
	for i = 1, RANK_MAX do
		local row, r = rankRows[i], rank[i]
		if r and i <= vis then
			row.key = r.key
			row.cRank:SetText(i)
			local color = r.main and X:MainColor(r.main) or X:ClassColor(r.char)
			row.cName:SetText(color .. r.display .. "|r" .. (r.main and "" or " |cffff8080(?)|r"))
			row.cBid:SetText(BID_COLORS[r.bid] .. r.bid .. "|r")
			row.cPR:SetText(r.bid == "ROLL" and "-" or string.format("%.2f", r.pr))
			row.cRoll:SetText(r.roll and tostring(r.roll) or "-")
			row.cCost:SetText(r.cost > 0 and (r.cost .. " GP") or "-")
			if r.key == self.selectedKey then row.sel:Show() else row.sel:Hide() end
			row:Show()
		else
			row.key = nil
			row:Hide()
		end
	end
	moreText:ClearAllPoints()
	moreText:SetPoint("TOPLEFT", p1, "TOPLEFT", 4, -RANK_TOP - vis * 18 - 2)
	if n > vis then moreText:SetText("+ " .. (n - vis) .. " more (enlarge the window to see them)") else moreText:SetText("") end
	local live = (a.state == "open" or a.state == "closed")
	if live and n > 0 then btnAward:Enable() else btnAward:Disable() end
	if a.state == "open" then btnClose:Enable() else btnClose:Disable() end
	btnCancel:Enable()
	btnRe:Enable()
end

function UI:OnAuctionChanged()
	self:RefreshAuction()
end

-------------------------------------------------------------------------------
-- Tab 2 : Players
-------------------------------------------------------------------------------
local p2 = MakePanel()
local PL_MAX = 40
local PL_TOP = 44
local PL_BOTTOM = 80                -- space reserved for the edit controls under the list

local fl = Text(p2, "Filter:", "GameFontNormalSmall")
fl:SetPoint("TOPLEFT", p2, "TOPLEFT", 0, -4)
local filterBox = Edit(p2, 160, 20)
filterBox:SetPoint("LEFT", fl, "RIGHT", 6, 0)
filterBox:SetScript("OnTextChanged", function() UI.plOffset = 0; UI:RefreshPlayers() end)
local plCount = Text(p2, "", "GameFontDisableSmall", 200, "RIGHT")
plCount:SetPoint("TOPRIGHT", p2, "TOPRIGHT", -24, -8)

-- Columns (offsets from the right edge of a row; rows leave 24 px on the right for the scroll buttons)
local PCOL = { pr = { -4, 80 }, gp = { -88, 70 }, ep = { -162, 70 }, nameRight = -236 }
do
	local hn = Text(p2, "Player", "GameFontNormalSmall", 100)
	hn:SetPoint("TOPLEFT", p2, "TOPLEFT", 4, -30)
	local function hdr(txt, c)
		local h = Text(p2, txt, "GameFontNormalSmall", c[2])
		h:SetPoint("TOPRIGHT", p2, "TOPRIGHT", c[1] - 24, -30)
	end
	hdr("EP", PCOL.ep); hdr("GP", PCOL.gp); hdr("PR (EP/GP)", PCOL.pr)
end

local plRows = {}
for i = 1, PL_MAX do
	local row = StretchRow(p2, -PL_TOP - (i - 1) * 18, 18, -24)
	row.cPR = RightCell(row, nil, PCOL.pr[1], PCOL.pr[2])
	row.cGP = RightCell(row, nil, PCOL.gp[1], PCOL.gp[2])
	row.cEP = RightCell(row, nil, PCOL.ep[1], PCOL.ep[2])
	row.cName = Text(row, "", "GameFontHighlightSmall")
	row.cName:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.cName:SetPoint("RIGHT", row, "RIGHT", PCOL.nameRight, 0)
	row:SetScript("OnClick", function()
		local p = this.data
		if p then
			UI.selectedPlayer = p.name
			UI.nameBox:SetText(p.name)
			UI.epBox:SetText(tostring(X:Round(p.ep, 2)))
			UI.gpBox:SetText(tostring(X:Round(p.gp, 2)))
			UI:RefreshPlayers()
		end
	end)
	row:Hide()
	plRows[i] = row
end

local scrollUp = CreateFrame("Button", NewName(), p2, "UIPanelScrollUpButtonTemplate")
scrollUp:SetPoint("TOPRIGHT", p2, "TOPRIGHT", 0, -PL_TOP)
scrollUp:SetScript("OnClick", function() UI.plOffset = math.max(0, (UI.plOffset or 0) - 3); UI:RefreshPlayers() end)
local scrollDown = CreateFrame("Button", NewName(), p2, "UIPanelScrollDownButtonTemplate")
scrollDown:SetPoint("BOTTOMRIGHT", p2, "BOTTOMRIGHT", 0, PL_BOTTOM)
scrollDown:SetScript("OnClick", function() UI.plOffset = (UI.plOffset or 0) + 3; UI:RefreshPlayers() end)
p2:EnableMouseWheel(true)
p2:SetScript("OnMouseWheel", function()
	UI.plOffset = math.max(0, (UI.plOffset or 0) - arg1 * 3)
	UI:RefreshPlayers()
end)

-- Edit controls, anchored to the bottom of the panel
local l1 = Text(p2, "Player", "GameFontNormalSmall"); l1:SetPoint("BOTTOMLEFT", p2, "BOTTOMLEFT", 0, 56)
local l2 = Text(p2, "EP", "GameFontNormalSmall"); l2:SetPoint("BOTTOMLEFT", p2, "BOTTOMLEFT", 170, 56)
local l3 = Text(p2, "GP", "GameFontNormalSmall"); l3:SetPoint("BOTTOMLEFT", p2, "BOTTOMLEFT", 244, 56)
UI.nameBox = Edit(p2, 160, 20); UI.nameBox:SetPoint("BOTTOMLEFT", p2, "BOTTOMLEFT", 0, 32)
UI.epBox = Edit(p2, 66, 20); UI.epBox:SetPoint("BOTTOMLEFT", p2, "BOTTOMLEFT", 170, 32)
UI.gpBox = Edit(p2, 66, 20); UI.gpBox:SetPoint("BOTTOMLEFT", p2, "BOTTOMLEFT", 244, 32)
local bApply = Button(p2, "Apply", 80, 22, function()
	local name = X.Trim(UI.nameBox:GetText())
	local ep, gp = tonumber(UI.epBox:GetText()), tonumber(UI.gpBox:GetText())
	if name == "" or not ep or not gp then X:Print("Enter a valid name, EP and GP."); return end
	X:SetPlayer(name, ep, gp)
	UI.selectedPlayer = X:FindMain(name)
	UI:RefreshPlayers()
end)
bApply:SetPoint("BOTTOMLEFT", p2, "BOTTOMLEFT", 320, 31)
local bDel = Button(p2, "Delete", 80, 22, function()
	local name = X.Trim(UI.nameBox:GetText())
	if name == "" or not X:FindMain(name) then return end
	X:Confirm("Remove " .. name .. " from the EPGP list?", function()
		X:RemovePlayer(name)
		UI.selectedPlayer = nil
		UI:RefreshPlayers()
	end)
end)
bDel:SetPoint("LEFT", bApply, "RIGHT", 4, 0)

local rl = Text(p2, "Raid EP:", "GameFontNormalSmall"); rl:SetPoint("BOTTOMLEFT", p2, "BOTTOMLEFT", 0, 6)
local raidBox = Edit(p2, 66, 20); raidBox:SetPoint("BOTTOMLEFT", p2, "BOTTOMLEFT", 56, 2)
local bRaid = Button(p2, "Give to whole raid", 130, 22, function()
	local amount = tonumber(raidBox:GetText())
	if not amount or amount == 0 then X:Print("Invalid EP amount."); return end
	X:Confirm(string.format("Give %+d EP to everyone in the raid?", amount), function()
		X:AwardRaidEP(amount)
		raidBox:SetText("")
		UI:RefreshPlayers()
	end)
end)
bRaid:SetPoint("LEFT", raidBox, "RIGHT", 6, 0)
local bPub = Button(p2, "Broadcast to players", 140, 22, function()
	local n = X:Publish()
	X:Print("Priorities broadcast (" .. n .. " addon message(s)).")
end)
bPub:SetPoint("LEFT", bRaid, "RIGHT", 6, 0)

function UI:PlayerVisible()
	local v = math.floor((f:GetHeight() - PANEL_TOP - PANEL_BOTTOM - PL_TOP - PL_BOTTOM) / 18)
	if v < 3 then v = 3 end
	if v > PL_MAX then v = PL_MAX end
	return v
end

function UI:RefreshPlayers()
	if not X.db or not p2:IsShown() then return end
	local vis = self:PlayerVisible()
	local all = X:SortedPlayers()
	local filter = string.lower(X.Trim(filterBox:GetText() or ""))
	local list = {}
	for i = 1, table.getn(all) do
		local p = all[i]
		if filter == "" or string.find(string.lower(X:PlayerName(p.name)), filter, 1, true) then
			table.insert(list, p)
		end
	end
	local n = table.getn(list)
	local maxOffset = math.max(0, n - vis)
	self.plOffset = math.min(self.plOffset or 0, maxOffset)
	for i = 1, PL_MAX do
		local row, p = plRows[i], list[i + self.plOffset]
		if p and i <= vis then
			row.data = p
			row.cName:SetText(X:MainColor(p.name) .. X:PlayerName(p.name) .. "|r")
			row.cEP:SetText(tostring(X:Round(p.ep, 2)))
			row.cGP:SetText(tostring(X:Round(p.gp, 2)))
			row.cPR:SetText(string.format("%.2f", p.pr))
			if p.name == self.selectedPlayer then row.sel:Show() else row.sel:Hide() end
			row:Show()
		else
			row.data = nil
			row:Hide()
		end
	end
	plCount:SetText(n .. " player(s)")
end

-------------------------------------------------------------------------------
-- Tab 3 : Import / Export
-------------------------------------------------------------------------------
local p3 = MakePanel()
local ioHelp = Text(p3, "Export: click Export, the JSON gets selected; press Ctrl+C, then paste it into the Google Doc.\n" ..
	"Import: paste the JSON generated by the Google Doc into the field below (single line), then pick a mode.\n\n" ..
	"Accepted format:\n" ..
	"|cffffd700{\"players\":[{\"name\":\"Main\",\"ep\":1200,\"gp\":300,\"alts\":[\"Alt1\"]}, ...]}|r\n" ..
	"(a plain array [...] or an object {\"Name\":{\"ep\":..,\"gp\":..}} is also accepted)",
	"GameFontHighlightSmall")
ioHelp:SetPoint("TOPLEFT", p3, "TOPLEFT", 0, 0)
ioHelp:SetPoint("TOPRIGHT", p3, "TOPRIGHT", 0, 0)
ioHelp:SetHeight(110)
ioHelp:SetJustifyV("TOP")

local ioBox = Edit(p3, nil, 24)
ioBox:SetPoint("TOPLEFT", p3, "TOPLEFT", 0, -124)
ioBox:SetPoint("TOPRIGHT", p3, "TOPRIGHT", 0, -124)
ioBox:SetMaxLetters(200000)
local ioStatus = Text(p3, "", "GameFontNormal")
ioStatus:SetPoint("TOPLEFT", p3, "TOPLEFT", 0, -220)
ioStatus:SetPoint("TOPRIGHT", p3, "TOPRIGHT", 0, -220)
ioStatus:SetHeight(60)
ioStatus:SetJustifyV("TOP")

function UI.countPlayers()
	local n = 0
	for _ in pairs(X.db.players) do n = n + 1 end
	return n
end

local function doImport(mode)
	local list, costs, skipped = X:ParseImport(ioBox:GetText())
	if not list then
		ioStatus:SetText("|cffff4040Import failed:|r " .. tostring(costs))
		return
	end
	local msg
	if mode == "replace" then
		msg = string.format("Replace the WHOLE current list (%d players) with %d imported player(s)?", UI.countPlayers(), table.getn(list))
	else
		msg = string.format("Update %d player(s) from the JSON (the others are kept)?", table.getn(list))
	end
	X:Confirm(msg, function()
		local n = X:ApplyImport(list, costs, mode)
		local extra = (skipped and skipped > 0) and (" (" .. skipped .. " invalid entr" .. (skipped > 1 and "ies" or "y") .. " skipped)") or ""
		ioStatus:SetText("|cff33cc33" .. n .. " player(s) imported." .. extra .. "|r")
		ioBox:SetText("")
		UI:RefreshAll()
	end)
end

local bExport = Button(p3, "Export", 90, 24, function()
	local json = X:Export()
	ioBox:SetText(json)
	ioBox:SetFocus()
	ioBox:HighlightText()
	ioStatus:SetText("|cff33cc33Export ready (" .. string.len(json) .. " characters, " .. UI.countPlayers() .. " players).|r\nPress Ctrl+C to copy, then paste into the Google Doc.")
end)
bExport:SetPoint("TOPLEFT", p3, "TOPLEFT", 0, -158)
local bImpR = Button(p3, "Import (replace all)", 150, 24, function() doImport("replace") end)
bImpR:SetPoint("LEFT", bExport, "RIGHT", 6, 0)
local bImpM = Button(p3, "Import (update)", 130, 24, function() doImport("merge") end)
bImpM:SetPoint("LEFT", bImpR, "RIGHT", 6, 0)
local bClr = Button(p3, "Clear", 60, 24, function() ioBox:SetText(""); ioStatus:SetText("") end)
bClr:SetPoint("LEFT", bImpM, "RIGHT", 6, 0)
local bSync = Button(p3, "Synchronize", 110, 24, function() X:SyncPlayers() end)
bSync:SetPoint("TOPLEFT", p3, "TOPLEFT", 0, -188)
bSync:SetScript("OnEnter", function()
	GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
	GameTooltip:SetText("Synchronize")
	GameTooltip:AddLine("Sends every player's priority and the prices to the group (use it after an import done before the raid). Imports and value changes already do it automatically; players who connect later ask for their priority by themselves.", 1, 1, 1, 1)
	GameTooltip:Show()
end)
bSync:SetScript("OnLeave", function() GameTooltip:Hide() end)

-------------------------------------------------------------------------------
-- Tab 4 : Log
-------------------------------------------------------------------------------
local p4 = MakePanel()
local logFrame = CreateFrame("ScrollingMessageFrame", NewName(), p4)
logFrame:SetPoint("TOPLEFT", p4, "TOPLEFT", 0, 0)
logFrame:SetPoint("BOTTOMRIGHT", p4, "BOTTOMRIGHT", 0, 0)
logFrame:SetFontObject(ChatFontNormal)
logFrame:SetJustifyH("LEFT")
logFrame:SetMaxLines(500)
logFrame:SetFading(false)
logFrame:EnableMouseWheel(true)
logFrame:SetScript("OnMouseWheel", function()
	if arg1 > 0 then this:ScrollUp(); this:ScrollUp() else this:ScrollDown(); this:ScrollDown() end
end)

local function logLine(e)
	local who = e.player or ""
	if e.char and e.char ~= e.player then who = who .. " (" .. e.char .. ")" end
	local t = e.type
	local stamp = "|cff888888" .. tostring(e.t) .. "|r "
	if t == "AWARD" then
		return string.format("%s|cffffd700Award|r %s: %s [%s%s] |cffff4040+%d GP|r", stamp, e.link or e.item or "?", who, e.bid or "", e.roll and (", roll " .. e.roll) or "", e.gp or 0)
	elseif t == "SET" then
		return string.format("%sSet %s: EP %s / GP %s", stamp, who, tostring(e.ep), tostring(e.gp))
	elseif t == "EP" then
		return string.format("%sEP %+d for %s", stamp, e.ep, who)
	elseif t == "GP" then
		return string.format("%sGP %+d for %s%s", stamp, e.gp, who, e.reason and (" (" .. e.reason .. ")") or "")
	elseif t == "RAIDEP" then
		return string.format("%sRaid EP %+d (%d players)", stamp, e.ep, e.count or 0)
	elseif t == "REMOVE" then
		return string.format("%sRemoved %s", stamp, who)
	elseif t == "IMPORT" then
		return string.format("%s|cff33cc33Import|r %d player(s) (%s)", stamp, e.count or 0, e.reason or "")
	end
	return stamp .. tostring(t)
end

function UI:RefreshLog()
	if not X.db or not p4:IsShown() then return end
	logFrame:Clear()
	local n = table.getn(X.db.log)
	for i = math.max(1, n - 199), n do
		logFrame:AddMessage(logLine(X.db.log[i]))
	end
end

-------------------------------------------------------------------------------
-- Tab 5 (shown 2nd) : Trades - awarded items still in the master looter's bags
-------------------------------------------------------------------------------
local p5 = MakePanel()
local TR_MAX = 30
local tHead = Text(p5, "Items to trade to the winners (GP is applied once the trade is done)", "GameFontNormal")
tHead:SetPoint("TOPLEFT", p5, "TOPLEFT", 0, 0)
local tEmpty = Text(p5, "Nothing to trade. Awarding an item that you took into your bags adds it here.", "GameFontDisableSmall")
tEmpty:SetPoint("TOPLEFT", p5, "TOPLEFT", 4, -26)
local tHelp = Text(p5, "The trade is detected automatically when you complete it with the winner. Trade = open the trade window and place the item, Done = apply GP manually, Cancel = put the item back in the loot list (no GP).", "GameFontDisableSmall", 480)
tHelp:SetPoint("BOTTOMLEFT", p5, "BOTTOMLEFT", 0, 0)

local tradeRows = {}
for i = 1, TR_MAX do
	local idx = i
	local row = StretchRow(p5, -24 - (i - 1) * 24, 22)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetWidth(20)
	row.icon:SetHeight(20)
	row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
	row.cancel = Button(row, "Cancel", 60, 20, function() X:CancelTrade(idx) end)
	row.cancel:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.done = Button(row, "Done", 50, 20, function() X:ValidateTrade(idx) end)
	row.done:SetPoint("RIGHT", row.cancel, "LEFT", -4, 0)
	row.trade = Button(row, "Trade", 50, 20, function() X:StartTrade(idx) end)
	row.trade:SetPoint("RIGHT", row.done, "LEFT", -4, 0)
	row.trade:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText("Trade")
		GameTooltip:AddLine("Opens the trade window with the winner (he must be in your group and in range) and puts the item in it. You still have to accept the trade.", 1, 1, 1, 1)
		GameTooltip:Show()
	end)
	row.trade:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.timer = Text(row, "", "GameFontHighlightSmall", 56, "RIGHT")
	row.timer:SetPoint("RIGHT", row.trade, "LEFT", -6, 0)
	row.text = Text(row, "", "GameFontHighlight")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", row.timer, "LEFT", -6, 0)
	ItemTooltip(row, function() local t = X.db and X.db.trades[idx]; return t and t.link end)
	row:Hide()
	tradeRows[i] = row
end

local function tradeIcon(t)
	if GetItemInfo then
		local _, _, _, _, _, _, _, _, _, tex = GetItemInfo((string.gsub(t.link or "", "^.-item:(%d+).*$", "%1")))
		return tex
	end
end

function UI:RefreshTrades()
	if not X.db then return end
	local n = table.getn(X.db.trades)
	tabs[5]:SetText("Trades" .. (n > 0 and (" (" .. n .. ")") or ""))
	if not p5:IsShown() then return end
	local vis = math.floor((f:GetHeight() - PANEL_TOP - PANEL_BOTTOM - 24 - 34) / 24)
	if vis < 3 then vis = 3 end
	if vis > TR_MAX then vis = TR_MAX end
	for i = 1, TR_MAX do
		local row, t = tradeRows[i], X.db.trades[i]
		if t and i <= vis then
			row.icon:SetTexture(tradeIcon(t))
			local who = t.main or t.char
			if t.main and string.lower(t.main) ~= string.lower(t.char) then who = t.main .. " (" .. t.char .. ")" end
			local color = t.main and X:MainColor(t.main) or X:ClassColor(t.char)
			local cost = (t.cost or 0) > 0 and (" |cff888888" .. t.bid .. ", " .. t.cost .. " GP|r") or " |cff888888roll|r"
			row.text:SetText(t.link .. " |cffffffff->|r " .. color .. who .. "|r" .. cost)
			local left = X:TimeLeft(t.exp)
			row.timer:SetText(left and ("|cffffd700" .. X.FormatLeft(left) .. "|r") or "")
			row:Show()
		else
			row:Hide()
		end
	end
	if n == 0 then tEmpty:Show() else tEmpty:Hide() end
end

-- Called every second while a trade timer is running
function UI:RefreshTimers()
	if f:IsShown() then
		self:RefreshLoot()
		self:RefreshTrades()
	end
end

-------------------------------------------------------------------------------
function UI:RefreshAll()
	if not X.db then return end
	self:RefreshLoot()
	self:RefreshTrades()
	self:RefreshAuction()
	self:RefreshPlayers()
	self:RefreshLog()
end

-- Called when the window is resized or a tab is shown
function UI:Layout()
	self:RefreshAll()
end

f:SetScript("OnSizeChanged", function() UI:Layout() end)
