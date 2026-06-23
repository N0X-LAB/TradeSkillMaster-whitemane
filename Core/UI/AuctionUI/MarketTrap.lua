-- ------------------------------------------------------------------------------ --
--                                TradeSkillMaster                                --
--                          https://tradeskillmaster.com                          --
--    All Rights Reserved - Detailed license information included with addon.     --
-- ------------------------------------------------------------------------------ --

local TSM = select(2, ...) ---@type TSM
local MarketTrap = TSM.UI.AuctionUI:NewPackage("MarketTrap") ---@type AddonPackage
local L = TSM.Locale.GetTable()
local TextureAtlas = TSM.LibTSMService:Include("UI.TextureAtlas")
local PlayerInfo = TSM.LibTSMApp:Include("Service.PlayerInfo")
local UIElements = TSM.LibTSMUI:Include("Util.UIElements")
local UIUtils = TSM.LibTSMUI:Include("Util.UIUtils")
local Reactive = TSM.LibTSMUtil:Include("Reactive")
local UIManager = TSM.LibTSMUtil:IncludeClassType("UIManager")
local AuctionBuyScan = TSM.LibTSMUI:IncludeClassType("AuctionBuyScan")
local private = {
	auctionBuyScan = nil,
	manager = nil,
	settings = nil,
	selectedGroups = {},
	updateCallbacks = {},
}
local STATE_SCHEMA = Reactive.CreateStateSchema("MARKET_TRAP_UI_STATE")
	:AddOptionalTableField("frame")
	:AddOptionalTableField("scanFrame")
	:AddStringField("contentPath", "selection")
	:AddStringField("searchName", "")
	:AddBooleanField("groupSelectionCleared", true)
	:AddStringField("candidateText", "")
	:AddBooleanField("candidateIsValid", false)
	:Commit()



-- ============================================================================
-- Module Functions
-- ============================================================================

function MarketTrap.OnInitialize(settingsDB)
	private.settings = settingsDB:NewView()
		:AddKey("global", "auctionUIContext", "marketTrapSelectionDividedContainer")
		:AddKey("global", "auctionUIContext", "marketTrapAuctionScrollingTable")
		:AddKey("char", "auctionUIContext", "marketTrapGroupTree")

	local state = STATE_SCHEMA:CreateState()
	private.manager = UIManager.Create("MARKET_TRAP", state, private.ActionHandler)
	private.auctionBuyScan = AuctionBuyScan.NewBrose(L["Market Trap"], PlayerInfo.AuctionOwnerIsPlayer, nil, nil, nil, TSM.MarketTrap.GetPostQuantity)

	local function GetFrame()
		return private.GetMarketTrapFrame(state)
	end
	TSM.UI.AuctionUI.RegisterTopLevelPage(L["Market Trap"], GetFrame)
end

function MarketTrap.IsVisible()
	return TSM.UI.AuctionUI.IsPageOpen(L["Market Trap"])
end

function MarketTrap.RegisterUpdateCallback(callback)
	tinsert(private.updateCallbacks, callback)
end



-- ============================================================================
-- Market Trap UI
-- ============================================================================

---@param state MarketTrapUIState
function private.GetMarketTrapFrame(state)
	UIUtils.AnalyticsRecordPathChange("auction", "marketTrap")
	if not private.auctionBuyScan:GetSearchContext() then
		state.contentPath = "selection"
	end
	local frame = UIElements.New("ViewContainer", "marketTrap")
		:SetContext(state)
		:SetNavCallback(private.GetMarketTrapContentFrame)
		:AddPath("selection")
		:AddPath("scan")
		:SetPath(state.contentPath)
		:SetManager(private.manager)
		:SetScript("OnHide", private.manager:CallbackToProcessAction("ACTION_FRAME_HIDDEN"))
	state.frame = frame
	for _, callback in ipairs(private.updateCallbacks) do
		callback()
	end
	return frame
end

function private.GetMarketTrapContentFrame(viewContainer, path)
	local state = viewContainer:GetContext() ---@type MarketTrapUIState
	state.contentPath = path
	if path == "selection" then
		return private.GetSelectionFrame(state)
	elseif path == "scan" then
		return private.GetScanFrame(state)
	else
		error("Unexpected path: "..tostring(path))
	end
end

---@param state MarketTrapUIState
function private.GetSelectionFrame(state)
	UIUtils.AnalyticsRecordPathChange("auction", "marketTrap", "selection")
	local frame = UIElements.New("DividedContainer", "selection")
		:SetSettingsContext(private.settings, "marketTrapSelectionDividedContainer")
		:SetMinWidth(220, 350)
		:SetBackgroundColor("PRIMARY_BG")
		:SetLeftChild(UIElements.New("Frame", "groupSelection")
			:SetLayout("VERTICAL")
			:AddChild(UIElements.New("ApplicationGroupTreeWithControls", "groupTree")
				:SetOperationType("Shopping")
				:SetSettingsContext(private.settings, "marketTrapGroupTree")
				:SetAction("OnGroupSelectionChanged", "ACTION_GROUP_SELECTION_CHANGED")
			)
			:AddChild(UIElements.New("HorizontalLine", "line"))
			:AddChild(UIElements.New("Frame", "bottom")
				:SetLayout("VERTICAL")
				:SetHeight(72)
				:SetPadding(8)
				:SetBackgroundColor("PRIMARY_BG_ALT")
				:AddChild(UIElements.New("ActionButton", "runScanBtn")
					:SetHeight(24)
					:SetMargin(0, 0, 0, 8)
					:SetText(L["Run Scan"])
					:SetDisabledPublisher(state:PublisherForKeyChange("groupSelectionCleared"))
					:SetAction("OnClick", "ACTION_START_DISCOVERY_SCAN")
				)
				:AddChild(UIElements.New("ActionButton", "stopScanBtn")
					:SetHeight(24)
					:SetText(L["Stop Scan"])
					:SetAction("OnClick", "ACTION_STOP_SCAN")
				)
			)
		)
		:SetRightChild(private.GetOverviewFrame(state))
	state.groupSelectionCleared = frame:GetElement("groupSelection.groupTree"):IsSelectionCleared()
	return frame
end

---@param state MarketTrapUIState
function private.GetOverviewFrame(state)
	return UIElements.New("Frame", "overview")
		:SetLayout("VERTICAL")
		:SetPadding(16)
		:SetBackgroundColor("PRIMARY_BG_ALT")
		:AddChild(private.CreateHeading("discoveryHeading", L["Discovery Scan"]))
		:AddChild(UIElements.New("Text", "discoveryText")
			:SetHeight(42)
			:SetMargin(0, 0, 0, 16)
			:SetFont("BODY_BODY2")
			:SetText(L["Scans the selected groups and surfaces items with low auction count and low available quantity."])
		)
		:AddChild(private.CreateHeading("reviewHeading", L["Candidate Review"]))
		:AddChild(UIElements.New("Text", "reviewText")
			:SetHeight(42)
			:SetMargin(0, 0, 0, 16)
			:SetFont("BODY_BODY2")
			:SetText(L["Select a result after the discovery scan to review its score, limits, and target repost price."])
		)
		:AddChild(private.CreateHeading("executeHeading", L["Controlled Execute"]))
		:AddChild(UIElements.New("Text", "executeText")
			:SetHeight(64)
			:SetFont("BODY_BODY2")
			:SetText(L["Validated candidates use the existing Browse buy and post controls so every purchase and repost stays under TSM and Auction House confirmation."])
		)
end

---@param state MarketTrapUIState
function private.GetScanFrame(state)
	UIUtils.AnalyticsRecordPathChange("auction", "marketTrap", "scan")
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
				:SetText(L["Discovery Scan"].." - "..state.searchName)
			)
			:AddChild(UIElements.New("ActionButton", "rescanBtn")
				:SetWidth(140)
				:SetMargin(8, 0, 0, 0)
				:SetText(L["Run Scan"])
				:SetAction("OnClick", "ACTION_RESCAN")
			)
			:AddChild(UIElements.New("ActionButton", "stopBtn")
				:SetWidth(140)
				:SetMargin(8, 0, 0, 0)
				:SetText(L["Stop Scan"])
				:SetAction("OnClick", "ACTION_STOP_SCAN")
			)
		)
		:AddChild(UIElements.New("AuctionScrollTable", "auctions")
			:SetSettings(private.settings, "marketTrapAuctionScrollingTable")
			:SetCreatedGroupName(L["Market Trap"].." - "..state.searchName)
			:SetBrowseResultsVisible(true)
			:SetRowScoreFunction(TSM.MarketTrap.GetRowScore)
			:SetRowFilterFunction(TSM.MarketTrap.ShouldShowRow)
			:SetIsPlayerFunction(PlayerInfo.AuctionOwnerIsPlayer)
		)
		:AddChild(UIElements.New("HorizontalLine", "candidateLine"))
		:AddChild(UIElements.New("Frame", "candidate")
			:SetLayout("HORIZONTAL")
			:SetHeight(40)
			:SetPadding(8)
			:SetBackgroundColor("PRIMARY_BG_ALT")
			:AddChild(UIElements.New("Text", "text")
				:SetHeight(24)
				:SetFont("BODY_BODY2")
				:SetTextPublisher(state:PublisherForKeyChange("candidateText"))
			)
			:AddChild(UIElements.New("ActionButton", "reviewBtn")
				:SetWidth(140)
				:SetMargin(8, 0, 0, 0)
				:SetText(L["Review Candidate"])
				:SetAction("OnClick", "ACTION_REVIEW_CANDIDATE")
			)
			:AddChild(UIElements.New("ActionButton", "executeBtn")
				:SetWidth(150)
				:SetMargin(8, 0, 0, 0)
				:SetText(L["Controlled Execute"])
				:SetDisabledPublisher(state:PublisherForKeyChange("candidateIsValid"):InvertBoolean())
				:SetAction("OnClick", "ACTION_CONTROLLED_EXECUTE")
			)
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

function private.CreateHeading(id, text)
	return UIElements.New("Text", id)
		:SetHeight(19)
		:SetMargin(0, 0, 0, 4)
		:SetFont("BODY_BODY1_BOLD")
		:SetText(text)
end



-- ============================================================================
-- Action Handler
-- ============================================================================

---@param manager UIManager
---@param state MarketTrapUIState
function private.ActionHandler(manager, state, action, ...)
	if action == "ACTION_FRAME_HIDDEN" then
		assert(state.frame)
		state.frame = nil
		for _, callback in ipairs(private.updateCallbacks) do
			callback()
		end
	elseif action == "ACTION_SCAN_FRAME_HIDDEN" then
		state.scanFrame = nil
		private.auctionBuyScan:SetAuctionScrollTable(nil)
	elseif action == "ACTION_GROUP_SELECTION_CHANGED" then
		state.groupSelectionCleared = state.frame:GetElement("selection.groupSelection.groupTree"):IsSelectionCleared()
	elseif action == "ACTION_START_DISCOVERY_SCAN" then
		manager:ProcessAction("ACTION_START_SEARCH", private.GetGroupSearchContext(state))
	elseif action == "ACTION_START_SEARCH" then
		local searchContext = ...
		state.frame:SetPath("selection", true)
		if not searchContext then
			return
		end
		if not private.auctionBuyScan:PrepareStartSearch() then
			return
		end
		local name = searchContext:GetName()
		assert(name)
		state.searchName = name
		state.candidateText = L["Select a result and review the candidate."]
		state.candidateIsValid = false
		TSM.MarketTrap.ResetExecuteSession()
		state.frame:SetPath("scan", true)
		private.auctionBuyScan:StartSearch(searchContext)
	elseif action == "ACTION_RESCAN" then
		manager:ProcessAction("ACTION_START_SEARCH", private.auctionBuyScan:GetSearchContext())
	elseif action == "ACTION_STOP_SCAN" then
		if private.auctionBuyScan:GetSearchContext() then
			private.auctionBuyScan:EndSearch()
		end
	elseif action == "ACTION_SCAN_BACK_BUTTON_CLICKED" then
		state.searchName = ""
		state.candidateText = ""
		state.candidateIsValid = false
		state.frame:SetPath("selection", true)
		private.auctionBuyScan:EndSearch()
	elseif action == "ACTION_REVIEW_CANDIDATE" then
		local candidate, reason = TSM.MarketTrap.BuildCandidate(state.scanFrame and state.scanFrame:GetElement("auctions"):GetSelectedRow() or nil)
		local isValid, validationReason = TSM.MarketTrap.ValidateCandidate(candidate)
		state.candidateText = TSM.MarketTrap.GetCandidateText(candidate, reason or validationReason).." - "..validationReason
		state.candidateIsValid = isValid
	elseif action == "ACTION_CONTROLLED_EXECUTE" then
		local candidate, reason = TSM.MarketTrap.BuildCandidate(state.scanFrame and state.scanFrame:GetElement("auctions"):GetSelectedRow() or nil)
		local isValid, validationReason = TSM.MarketTrap.ValidateCandidate(candidate)
		state.candidateText = TSM.MarketTrap.GetCandidateText(candidate, reason or validationReason).." - "..validationReason
		state.candidateIsValid = isValid
		if isValid then
			private.auctionBuyScan:PostAuction()
		end
	else
		error("Unknown action: "..tostring(action))
	end
end

---@param state MarketTrapUIState
function private.GetGroupSearchContext(state)
	wipe(private.selectedGroups)
	for _, groupPath in state.frame:GetElement("selection.groupSelection.groupTree"):SelectedGroupsIterator() do
		if groupPath ~= "" and not strmatch(groupPath, "^`") then
			tinsert(private.selectedGroups, groupPath)
		end
	end
	local searchContext = TSM.Shopping.GroupSearch.GetSearchContext(private.selectedGroups)
	assert(searchContext)
	return searchContext
end
