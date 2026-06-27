--                                TradeSkillMaster                                --
--                          https://tradeskillmaster.com                          --
--    All Rights Reserved - Detailed license information included with addon.     --
-- ------------------------------------------------------------------------------ --

local TSM = select(2, ...) ---@type TSM
local Opportunities = TSM.UI.AuctionUI:NewPackage("Opportunities") ---@type AddonPackage
local L = TSM.Locale.GetTable()
local TextureAtlas = TSM.LibTSMService:Include("UI.TextureAtlas")
local PlayerInfo = TSM.LibTSMApp:Include("Service.PlayerInfo")
local UIElements = TSM.LibTSMUI:Include("Util.UIElements")
local UIUtils = TSM.LibTSMUI:Include("Util.UIUtils")
local Reactive = TSM.LibTSMUtil:Include("Reactive")
local UIManager = TSM.LibTSMUtil:IncludeClassType("UIManager")
local AuctionBuyScan = TSM.LibTSMUI:IncludeClassType("AuctionBuyScan")
local private = {
	settings = nil,
	manager = nil,
	auctionBuyScan = nil,
}
local STATE_SCHEMA = Reactive.CreateStateSchema("OPPORTUNITIES_UI_STATE")
	:AddOptionalTableField("frame")
	:AddOptionalTableField("scanFrame")
	:AddStringField("contentPath", "selection")
	:AddStringField("searchName", "")
	:Commit()



-- ============================================================================
-- Module Functions
-- ============================================================================

function Opportunities.OnInitialize(settingsDB)
	private.settings = settingsDB:NewView()
		:AddKey("global", "auctionUIContext", "opportunitiesAuctionScrollingTable")

	local state = STATE_SCHEMA:CreateState()
	private.manager = UIManager.Create("OPPORTUNITIES", state, private.ActionHandler)
	private.auctionBuyScan = AuctionBuyScan.NewBrose("Opportunities", PlayerInfo.AuctionOwnerIsPlayer)

	local function GetFrame()
		return private.GetOpportunitiesFrame(state)
	end
	TSM.UI.AuctionUI.RegisterTopLevelPage("Opportunities", GetFrame)
end



-- ============================================================================
-- Opportunities UI
-- ============================================================================

---@param state OpportunitiesUIState
function private.GetOpportunitiesFrame(state)
	UIUtils.AnalyticsRecordPathChange("auction", "opportunities")
	if not private.auctionBuyScan:GetSearchContext() then
		state.contentPath = "selection"
	end
	local frame = UIElements.New("ViewContainer", "opportunities")
		:SetContext(state)
		:SetNavCallback(private.GetContentFrame)
		:AddPath("selection")
		:AddPath("scan")
		:SetPath(state.contentPath)
		:SetManager(private.manager)
		:SetScript("OnHide", private.manager:CallbackToProcessAction("ACTION_FRAME_HIDDEN"))
	state.frame = frame
	return frame
end

function private.GetContentFrame(viewContainer, path)
	local state = viewContainer:GetContext() ---@type OpportunitiesUIState
	state.contentPath = path
	if path == "selection" then
		return private.GetSelectionFrame()
	elseif path == "scan" then
		return private.GetScanFrame(state)
	else
		error("Unexpected path: "..tostring(path))
	end
end

function private.GetSelectionFrame()
	UIUtils.AnalyticsRecordPathChange("auction", "opportunities", "selection")
	return UIElements.New("Frame", "selection")
		:SetLayout("VERTICAL")
		:SetPadding(16)
		:SetBackgroundColor("PRIMARY_BG_ALT")
		:AddChild(UIElements.New("Text", "title")
			:SetHeight(24)
			:SetMargin(0, 0, 0, 8)
			:SetFont("BODY_BODY1_BOLD")
			:SetText("Opportunities")
		)
		:AddChild(UIElements.New("Text", "description")
			:SetHeight(44)
			:SetMargin(0, 0, 0, 12)
			:SetFont("BODY_BODY3")
			:SetText("Scan locally-known items whose current minimum buyout is below your configured market value threshold.")
		)
		:AddChild(UIElements.New("Frame", "actions")
			:SetLayout("HORIZONTAL")
			:SetHeight(24)
			:AddChild(UIElements.New("ActionButton", "runScanBtn")
				:SetWidth(160)
				:SetText(L["Run Scan"])
				:SetAction("OnClick", "ACTION_START_SCAN")
			)
			:AddChild(UIElements.New("Spacer", "spacer"))
		)
end

---@param state OpportunitiesUIState
function private.GetScanFrame(state)
	UIUtils.AnalyticsRecordPathChange("auction", "opportunities", "scan")
	local frame = UIElements.New("Frame", "scan")
		:SetLayout("VERTICAL")
		:SetBackgroundColor("PRIMARY_BG_ALT")
		:AddChild(UIElements.New("Frame", "header")
			:SetLayout("HORIZONTAL")
			:SetHeight(40)
			:SetPadding(8)
			:AddChild(UIElements.New("Frame", "back")
				:SetLayout("HORIZONTAL")
				:SetHeight(24)
				:SetMargin(0, 8, 0, 0)
				:AddChild(UIElements.New("ActionButton", "button")
					:SetWidth(64)
					:SetText(TextureAtlas.GetTextureLink(TextureAtlas.GetFlippedHorizontallyKey("iconPack.14x14/Chevron/Right"))..BACK)
					:SetAction("OnClick", "ACTION_SCAN_BACK_BUTTON_CLICKED")
				)
			)
			:AddChild(UIElements.New("Text", "title")
				:SetHeight(24)
				:SetFont("BODY_BODY1_BOLD")
				:SetText(state.searchName)
			)
			:AddChild(UIElements.New("ActionButton", "rescanBtn")
				:SetWidth(140)
				:SetMargin(8, 0, 0, 0)
				:SetText(L["Run Scan"])
				:SetAction("OnClick", "ACTION_RESCAN")
			)
		)
		:AddChild(UIElements.New("AuctionScrollTable", "auctions")
			:SetSettings(private.settings, "opportunitiesAuctionScrollingTable")
			:SetCreatedGroupName("Opportunities")
			:SetBrowseResultsVisible(true)
			:SetIsPlayerFunction(PlayerInfo.AuctionOwnerIsPlayer)
		)
		:AddChild(UIElements.New("HorizontalLine", "bottomLine"))
		:AddChild(private.auctionBuyScan:CreateBottomUIFrameForBrowse())
		:SetScript("OnUpdate", private.ScanFrameOnUpdate)
		:SetScript("OnHide", private.manager:CallbackToProcessAction("ACTION_SCAN_FRAME_HIDDEN"))
	state.scanFrame = frame
	return frame
end

function private.ScanFrameOnUpdate(frame)
	frame:SetScript("OnUpdate", nil)
	private.auctionBuyScan:SetAuctionScrollTable(frame:GetElement("auctions"))
end



-- ============================================================================
-- Action Handler
-- ============================================================================

---@param manager UIManager
---@param state OpportunitiesUIState
function private.ActionHandler(manager, state, action, ...)
	if action == "ACTION_FRAME_HIDDEN" then
		state.frame = nil
	elseif action == "ACTION_SCAN_FRAME_HIDDEN" then
		state.scanFrame = nil
		private.auctionBuyScan:SetAuctionScrollTable(nil)
	elseif action == "ACTION_START_SCAN" or action == "ACTION_RESCAN" then
		manager:ProcessAction("ACTION_START_SEARCH", TSM.Opportunities.GetSearchContext())
	elseif action == "ACTION_START_SEARCH" then
		local searchContext = ...
		state.frame:SetPath("selection", true)
		if not searchContext then
			return
		end
		if not private.auctionBuyScan:PrepareStartSearch() then
			return
		end
		state.searchName = searchContext:GetName()
		state.frame:SetPath("scan", true)
		private.auctionBuyScan:StartSearch(searchContext)
	elseif action == "ACTION_SCAN_BACK_BUTTON_CLICKED" then
		private.auctionBuyScan:EndSearch()
		state.frame:SetPath("selection", true)
	else
		error("Unknown action: "..tostring(action))
	end
end
