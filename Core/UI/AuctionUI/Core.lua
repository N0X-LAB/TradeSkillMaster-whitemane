-- ------------------------------------------------------------------------------ --
--                                TradeSkillMaster                                --
--                          https://tradeskillmaster.com                          --
--    All Rights Reserved - Detailed license information included with addon.     --
-- ------------------------------------------------------------------------------ --

local TSM = select(2, ...) ---@type TSM
local AuctionUI = TSM.UI:NewPackage("AuctionUI") ---@type AddonPackage
local ClientInfo = TSM.LibTSMWoW:Include("Util.ClientInfo")
local L = TSM.Locale.GetTable()
local DelayTimer = TSM.LibTSMWoW:IncludeClassType("DelayTimer")
local ScriptWrapper = TSM.LibTSMWoW:Include("API.ScriptWrapper")
local AuctionScan = TSM.LibTSMService:Include("AuctionScan")
local Theme = TSM.LibTSMService:Include("UI.Theme")
local ItemLinked = TSM.LibTSMUI:Include("Util.ItemLinked")
local DefaultUI = TSM.LibTSMWoW:Include("UI.DefaultUI")
local UIElements = TSM.LibTSMUI:Include("Util.UIElements")
local UIUtils = TSM.LibTSMUI:Include("Util.UIUtils")
local AppHelper = TSM.LibTSMApp:Include("Service.AppHelper")
local LibAHTab = LibStub("LibAHTab-1-0")
local private = {
	settings = nil,
	topLevelPages = {},
	frame = nil,
	hasShown = false,
	isSwitching = false,
	scanningPage = nil,
	updateCallbacks = {},
	defaultFrame = nil,
}
local MIN_FRAME_SIZE = { width = 750, height = 450 }
local AH_TAB_ID = "TSM_AH_TAB"

local function HasModernAuctionHouse()
	return ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE)
end



-- ============================================================================
-- Module Functions
-- ============================================================================

function AuctionUI.OnInitialize(settingsDB)
	private.settings = settingsDB:NewView()
		:AddKey("global", "auctionUIContext", "showDefault")
		:AddKey("global", "auctionUIContext", "frame")
		:AddKey("global", "coreOptions", "protectAuctionHouse")
		:AddKey("global", "coreOptions", "regionWide")
		:AddKey("global", "appearanceOptions", "showTotalMoney")
		:AddKey("global", "internalData", "warbankMoney")
		:AddKey("sync", "internalData", "money")
	UIParent:UnregisterEvent("AUCTION_HOUSE_SHOW")
	DefaultUI.RegisterAuctionHouseVisibleCallback(private.AuctionFrameInit, true)
	DefaultUI.RegisterAuctionHouseVisibleCallback(private.AuctionFrameHidden, false)
	AuctionScan.ConfigureLock(L["A scan is already in progress. Please stop that scan before starting another one."], private.ScanLockCallback)
	ItemLinked.RegisterCallback(private.ItemLinkedCallback, true)
	TSM.Auctioning.CancelTracker.RegisterCallback(private.UpdateCancelCounter)
	local loadTimer = DelayTimer.New("AUCTION_UI_LOAD_BLIZZ", function() C_AddOns.LoadAddOn(HasModernAuctionHouse() and "Blizzard_AuctionHouseUI" or "Blizzard_AuctionUI") end)
	loadTimer:RunForTime(1)
end

function AuctionUI.OnDisable()
	if private.frame then
		-- hide the frame
		private.frame:Hide()
		assert(not private.frame)
	end
end

function AuctionUI.RegisterTopLevelPage(name, callback, itemLinkedHandler)
	tinsert(private.topLevelPages, { name = name, callback = callback, itemLinkedHandler = itemLinkedHandler })
end

function AuctionUI.SetOpenPage(name)
	private.frame:SetSelectedNavButton(name, true)
end

function AuctionUI.IsPageOpen(name)
	if not private.frame then
		return false
	end
	return private.frame:GetSelectedNavButton() == name
end

function AuctionUI.IsScanning()
	return private.scanningPage and true or false
end

function AuctionUI.RegisterUpdateCallback(callback)
	tinsert(private.updateCallbacks, callback)
end

function AuctionUI.IsVisible()
	return private.frame and true or false
end



-- ============================================================================
-- Main Frame
-- ============================================================================

local function NoOp()
	-- do nothing - what did you expect?
end

function private.AuctionFrameInit()
	if GameLimitedMode_IsActive() then
		return
	end
	local tabTemplateName = nil
	if HasModernAuctionHouse() then
		private.defaultFrame = AuctionHouseFrame
		tabTemplateName = "AuctionHouseFrameTabTemplate"
	else
		private.defaultFrame = AuctionFrame
		tabTemplateName = "AuctionTabTemplate"
	end
	if not private.hasShown then
		private.hasShown = true
		if HasModernAuctionHouse() then
			LibAHTab:CreateTab(AH_TAB_ID, CreateFrame("Frame"), Theme.GetColor("INDICATOR_ALT"):ColorText("TSM"))
			ScriptWrapper.Set(LibAHTab:GetButton(AH_TAB_ID), "OnClick", private.TSMTabOnClick)
			AuctionHouseFrame:HookScript("OnShow", private.UnregisterDefaultUIEvents)
			if private.defaultFrame:IsVisible() then
				private.UnregisterDefaultUIEvents()
			end
		else
			local tabId = private.defaultFrame.numTabs + 1
			local tab = CreateFrame("Button", "AuctionFrameTab"..tabId, private.defaultFrame, tabTemplateName)
			tab:Hide()
			tab:SetID(tabId)
			tab:SetText(Theme.GetColor("INDICATOR_ALT"):ColorText("TSM"))
			tab:SetNormalFontObject(GameFontHighlightSmall)
			tab:SetPoint("LEFT", _G["AuctionFrameTab"..tabId - 1], "RIGHT", -8, 0)
			tab:Show()
			PanelTemplates_SetNumTabs(private.defaultFrame, tabId)
			PanelTemplates_EnableTab(private.defaultFrame, tabId)
			ScriptWrapper.Set(tab, "OnClick", private.TSMTabOnClick)
		end
	end
	if private.settings.showDefault then
		if not HasModernAuctionHouse() then
			UIParent_OnEvent(UIParent, "AUCTION_HOUSE_SHOW")
		end
	else
		if HasModernAuctionHouse() then
			private.defaultFrame:SetScale(0.001)
			LibAHTab:SetSelected(AH_TAB_ID)
		end
		PlaySound(SOUNDKIT.AUCTION_WINDOW_OPEN)
		private.ShowAuctionFrame()
	end
end

function private.UnregisterDefaultUIEvents()
	private.defaultFrame:UnregisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
	private.defaultFrame:UnregisterEvent("AUCTION_HOUSE_SHOW_NOTIFICATION")
	private.defaultFrame:UnregisterEvent("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION")
	private.defaultFrame:UnregisterEvent("AUCTION_HOUSE_SHOW_COMMODITY_WON_NOTIFICATION")
end

function private.ShowAuctionFrame()
	if private.frame then
		return
	end
	private.frame = private.CreateMainFrame()
	private.frame:Show()
	private.frame:Draw()
	for _, callback in ipairs(private.updateCallbacks) do
		callback()
	end
end

function private.AuctionFrameHidden()
	if not private.frame then
		return
	end
	if HasModernAuctionHouse() then
		private.defaultFrame:SetScale(1)
		private.defaultFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
	end
	private.HideAuctionFrame()
end

function private.HideAuctionFrame()
	if not private.frame then
		return
	end
	private.frame:Hide()
	-- For some reason, on retail the OnHide callback isn't called immediately
	if not HasModernAuctionHouse() then
		assert(not private.frame)
	end
	for _, callback in ipairs(private.updateCallbacks) do
		callback()
	end
end

function private.CreateMainFrame()
	UIUtils.AnalyticsRecordPathChange("auction")
	local frame = UIElements.New("LargeApplicationFrame", "base")
		:SetParent(UIParent)
		:SetSettingsContext(private.settings, "frame")
		:SetMinResize(MIN_FRAME_SIZE.width, MIN_FRAME_SIZE.height)
		:SetStrata("HIGH")
		:SetProtected(not HasModernAuctionHouse() and private.settings.protectAuctionHouse)
		:AddPlayerGold(private.settings)
		:AddSwitchButton(private.SwitchBtnOnClick)
		:SetScript("OnHide", private.BaseFrameOnHide)
	private.AddCancelCounter(frame)
	if AppHelper.IsDesktopAppSupported() then
		frame:AddAppStatusIcon(AppHelper.GetRegion(), AppHelper.GetLastSync(), TSM.AuctionDB.GetAppDataUpdateTimes())
	end
	for _, info in ipairs(private.topLevelPages) do
		frame:AddNavButton(info.name, info.callback)
	end
	local whatsNewDialog = TSM.UI.WhatsNew.GetDialog()
	if whatsNewDialog then
		frame:ShowDialogFrame(whatsNewDialog)
	end
	return frame
end

function private.AddCancelCounter(frame)
	local titleFrame = frame:GetElement("titleFrame")
	titleFrame:AddChildBeforeById("playerGold", UIElements.New("Text", "cancelCounter")
		:SetWidth("AUTO")
		:SetMargin(0, 8, 0, 0)
		:SetFont("TABLE_TABLE1")
		:SetJustifyH("RIGHT")
		:SetText(private.GetCancelCounterText())
	)
end



-- ============================================================================
-- Local Script Handlers
-- ============================================================================

function private.ScanLockCallback(name)
	private.scanningPage = name
	if private.frame then
		private.frame:SetPulsingNavButton(name)
	end
	for _, callback in ipairs(private.updateCallbacks) do
		callback()
	end
end

function private.BaseFrameOnHide(frame)
	assert(frame == private.frame)
	frame:Release()
	private.frame = nil
	if not private.isSwitching then
		PlaySound(SOUNDKIT.AUCTION_WINDOW_CLOSE)
		if HasModernAuctionHouse() then
			private.defaultFrame:SetScale(1)
			C_AuctionHouse.CloseAuctionHouse()
		else
			CloseAuctionHouse()
		end
	end
	UIUtils.AnalyticsRecordClose("auction")
end

function private.SwitchBtnOnClick(button)
	private.isSwitching = true
	private.settings.showDefault = true
	private.HideAuctionFrame()
	if HasModernAuctionHouse() then
		private.defaultFrame:SetScale(1)
		private.defaultFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
	end
	UIParent_OnEvent(UIParent, "AUCTION_HOUSE_SHOW")
	private.isSwitching = false
end

function private.UpdateCancelCounter()
	if not private.frame then
		return
	end
	private.frame:GetElement("titleFrame.cancelCounter")
		:SetText(private.GetCancelCounterText())
	private.frame:Draw()
end

function private.GetCancelCounterText()
	if not TSM.Auctioning.CancelTracker.GetShown() then
		return ""
	end
	local count = TSM.Auctioning.CancelTracker.GetCount()
	local color = private.GetCancelCounterColor(count, TSM.Auctioning.CancelTracker.GetThreshold())
	return Theme.GetColor("TEXT_ALT"):ColorText("Cancels: ")..Theme.GetColor(color):ColorText(tostring(count))
end

function private.GetCancelCounterColor(count, threshold)
	threshold = max(threshold or 1, 1)
	local pct = count / threshold
	if pct >= 1 then
		return "FEEDBACK_RED"
	elseif pct >= 0.9 then
		return "FEEDBACK_ORANGE"
	elseif pct >= 0.7 then
		return "FEEDBACK_YELLOW"
	else
		return "TEXT"
	end
end

function private.TSMTabOnClick()
	private.settings.showDefault = false
	if not HasModernAuctionHouse() then
		ClearCursor()
		ClickAuctionSellItemButton(AuctionsItemButton, "LeftButton")
	end
	ClearCursor()
	if HasModernAuctionHouse() then
		private.defaultFrame:SetScale(0.001)
		LibAHTab:SetSelected(AH_TAB_ID)
	else
		-- Replace CloseAuctionHouse() with a no-op while hiding the AH frame so we don't stop interacting with the AH NPC
		local origCloseAuctionHouse = CloseAuctionHouse
		CloseAuctionHouse = NoOp
		AuctionFrame_Hide()
		CloseAuctionHouse = origCloseAuctionHouse
	end
	private.ShowAuctionFrame()
end

function private.ItemLinkedCallback(name, itemLink)
	if not private.frame then
		return
	end
	local path = private.frame:GetSelectedNavButton()
	for _, info in ipairs(private.topLevelPages) do
		if info.name == path then
			if info.itemLinkedHandler(name, itemLink) then
				return true
			else
				return
			end
		end
	end
	error("Invalid frame path")
end
