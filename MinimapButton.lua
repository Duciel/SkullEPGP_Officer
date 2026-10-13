-- MinimapButton.lua : minimap button (click = open/close the window, drag = move it)
local X = SkullEPGP
local M = {}
X.Minimap = M

local btn = CreateFrame("Button", "SkullEPGPMinimapButton", Minimap)
M.button = btn
btn:SetWidth(32)
btn:SetHeight(32)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")

local icon = btn:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
icon:SetWidth(20)
icon:SetHeight(20)
icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -6)

local border = btn:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetWidth(52)
border:SetHeight(52)
border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

local offText = btn:CreateFontString(nil, "OVERLAY")
offText:SetFontObject(GameFontNormalSmall)
offText:SetPoint("CENTER", btn, "CENTER", 0, 0)
offText:SetText("|cffff2020OFF|r")
offText:Hide()

function M:SetPosition(angle)
	angle = tonumber(angle) or 200
	local rad = math.rad(angle)
	btn:ClearAllPoints()
	btn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 52 - (80 * math.cos(rad)), (80 * math.sin(rad)) - 52)
end

function M:Apply()
	if not X.db then return end
	-- place the button only once: addons like pfUI move minimap buttons into their own bar, and anchoring it
	-- again (each time the state changes) would pull it out of there for a moment
	if not self.positioned then
		self.positioned = true
		self:SetPosition(X.db.minimapAngle)
	end
	if X.db.minimapHidden then btn:Hide() else btn:Show() end
	-- disabled by hand: the button stays visible (half transparent, red "OFF" on top)
	if X.db.disabled then btn:SetAlpha(0.6); offText:Show() else btn:SetAlpha(1); offText:Hide() end
end

btn:SetScript("OnDragStart", function()
	this:LockHighlight()
	this:SetScript("OnUpdate", function()
		local mx, my = GetCursorPosition()
		local scale = UIParent:GetScale()
		local x = Minimap:GetLeft() - mx / scale + 70
		local y = my / scale - Minimap:GetBottom() - 70
		local angle = math.deg(math.atan2(y, x))
		if angle < 0 then angle = angle + 360 end
		X.db.minimapAngle = angle
		M:SetPosition(angle)
	end)
end)

btn:SetScript("OnDragStop", function()
	this:SetScript("OnUpdate", nil)
	this:UnlockHighlight()
end)

btn:SetScript("OnClick", function()
	if arg1 == "RightButton" then
		local ok, err = pcall(function() X:SetDisabled(not X.db.disabled) end)
		if not ok then X:Print("Error: " .. tostring(err)) end
		M:Apply()
		return
	end
	if X.UI then X.UI:Toggle() end
end)

btn:SetScript("OnEnter", function()
	GameTooltip:SetOwner(this, "ANCHOR_LEFT")
	GameTooltip:SetText("Skull EPGP - Officer")
	if X.db and X.db.disabled then
		GameTooltip:AddLine("DISABLED by hand", 1, 0.3, 0.3)
	end
	GameTooltip:AddLine("Click: open / close the window", 1, 1, 1)
	GameTooltip:AddLine("Right-click: " .. ((X.db and X.db.disabled) and "enable" or "disable (plain master loot, no EPGP)") .. " the addon", 1, 1, 1)
	GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
