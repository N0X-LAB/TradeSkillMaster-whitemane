-- ------------------------------------------------------------------------------ --
--                                TradeSkillMaster                                --
--                          https://tradeskillmaster.com                          --
--    All Rights Reserved - Detailed license information included with addon.     --
-- ------------------------------------------------------------------------------ --

local TSM = select(2, ...) ---@type TSM
local MarketTrap = TSM.UI.AuctionUI:NewPackage("MarketTrap") ---@type AddonPackage
local L = TSM.Locale.GetTable()
local TextureAtlas = TSM.LibTSMService:Include("UI.TextureAtlas")
local Theme = TSM.LibTSMService:Include("UI.Theme")
local ItemInfo = TSM.LibTSMService:Include("Item.ItemInfo")
local Tooltip = TSM.LibTSMUI:Include("Tooltip")
local PlayerInfo = TSM.LibTSMApp:Include("Service.PlayerInfo")
local UIElements = TSM.LibTSMUI:Include("Util.UIElements")
local UIUtils = TSM.LibTSMUI:Include("Util.UIUtils")
local TempTable = TSM.LibTSMUtil:Include("BaseType.TempTable")
local Reactive = TSM.LibTSMUtil:Include("Reactive")
local UIManager = TSM.LibTSMUtil:IncludeClassType("UIManager")
local AuctionBuyScan = TSM.LibTSMUI:IncludeClassType("AuctionBuyScan")
local private = {
	auctionBuyScan = nil,
	manager = nil,
	state = nil,
	settings = nil,
	selectedGroups = {},
	updateCallbacks = {},
	scanDividedContainer = { leftWidth = 1080 },
}
local SCAN_DIVIDED_CONTAINER_DEFAULT = { leftWidth = 1080 }
local STATE_SCHEMA = Reactive.CreateStateSchema("MARKET_TRAP_UI_STATE")
	:AddOptionalTableField("frame")
	:AddOptionalTableField("scanFrame")
	:AddStringField("contentPath", "selection")
	:AddStringField("searchName", "")
	:AddBooleanField("groupSelectionCleared", true)
	:AddBooleanField("hasFavoriteTraps", false)
	:AddBooleanField("favoriteScanOnly", false)
	:AddStringField("candidateText", "")
	:AddStringField("executeText", "")
	:AddBooleanField("candidateIsValid", false)
	:Commit()
local FavoriteList = UIElements.Define("MarketTrapFavoriteList", "List")
local FAVORITE_LIST_ROW_HEIGHT = 20

function FavoriteList:__init()
	self.__super:__init()
	self._itemStrings = {}
	self._status = {}
end

function FavoriteList:Acquire()
	self.__super:Acquire(FAVORITE_LIST_ROW_HEIGHT)
	self:UpdateData()
end

function FavoriteList:Release()
	wipe(self._itemStrings)
	wipe(self._status)
	self.__super:Release()
end

function FavoriteList:UpdateData()
	wipe(self._itemStrings)
	wipe(self._status)
	for itemString in TSM.MarketTrap.FavoriteIterator() do
		tinsert(self._itemStrings, itemString)
		self._status[itemString] = TSM.MarketTrap.IsFavoriteActive(itemString) and L["Active"] or L["Inactive"]
	end
	sort(self._itemStrings)
	self:_SetNumRows(#self._itemStrings)
	self:Draw()
end

---@param row ListRow
function FavoriteList.__protected:_HandleRowAcquired(row)
	local colSpacing = Theme.GetColSpacing()
	local status = row:AddText("status")
	status:SetHeight(FAVORITE_LIST_ROW_HEIGHT)
	status:TSMSetFont("TABLE_TABLE1")
	status:SetJustifyH("RIGHT")
	status:SetPoint("RIGHT", -colSpacing, 0)
	status:SetWidth(78)
	local item = row:AddText("item")
	item:SetHeight(FAVORITE_LIST_ROW_HEIGHT)
	item:TSMSetFont("ITEM_BODY3")
	item:SetJustifyH("LEFT")
	item:SetPoint("LEFT", colSpacing / 2, 0)
	item:SetPoint("RIGHT", status, "LEFT", -colSpacing, 0)
end

---@param row ListRow
function FavoriteList.__protected:_HandleRowDraw(row)
	local itemString = self._itemStrings[row:GetDataIndex()]
	local itemName = UIUtils.GetDisplayItemName(itemString) or ItemInfo.GetName(itemString) or itemString
	row:GetText("item"):SetText("|T"..(ItemInfo.GetTexture(itemString) or 0)..":0|t "..itemName)
	local status = self._status[itemString]
	row:GetText("status"):SetText((status == L["Active"] and Theme.GetColor("FEEDBACK_GREEN") or Theme.GetColor("TEXT_ALT")):ColorText(status))
end

---@param row ListRow
function FavoriteList.__protected:_HandleRowEnter(row)
	row:ShowTooltip(self._itemStrings[row:GetDataIndex()])
end

function FavoriteList.__protected:_HandleRowLeave()
	Tooltip.Hide()
end



-- ============================================================================
-- Module Functions
-- ============================================================================

function MarketTrap.OnInitialize(settingsDB)
	private.settings = settingsDB:NewView()
		:AddKey("global", "auctionUIContext", "marketTrapSelectionDividedContainer")
		:AddKey("global", "auctionUIContext", "marketTrapAuctionScrollingTable")
		:AddKey("char", "auctionUIContext", "marketTrapGroupTree")

	local state = STATE_SCHEMA:CreateState()
	private.state = state
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
			:AddChild(UIElements.New("ActionButton", "favoriteTrapsBtn")
				:SetHeight(24)
				:SetMargin(8, 8, 8, 0)
				:SetText(L["Favorite Traps"])
				:SetDisabledPublisher(state:PublisherForKeyChange("hasFavoriteTraps"):InvertBoolean())
				:SetAction("OnClick", "ACTION_START_FAVORITE_SCAN")
			)
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
	state.hasFavoriteTraps = TSM.MarketTrap.GetNumFavorites() > 0
	return frame
end

---@param state MarketTrapUIState
function private.GetOverviewFrame(state)
	return UIElements.New("Frame", "overview")
		:SetLayout("VERTICAL")
		:SetPadding(16)
		:SetBackgroundColor("PRIMARY_BG_ALT")
		:AddChild(private.CreateHeading("favoritesHeading", L["Favorite Traps"]))
		:AddChild(UIElements.New("Frame", "header")
			:SetLayout("HORIZONTAL")
			:SetHeight(22)
			:SetMargin(0, 0, 0, 4)
			:AddChild(UIElements.New("Text", "item")
				:SetHeight(18)
				:SetFont("BODY_BODY3_MEDIUM")
				:SetText(L["Item"])
			)
			:AddChild(UIElements.New("Text", "status")
				:SetWidth(80)
				:SetHeight(18)
				:SetFont("BODY_BODY3_MEDIUM")
				:SetJustifyH("RIGHT")
				:SetText(L["Status"])
			)
		)
		:AddChild(UIElements.New("MarketTrapFavoriteList", "favorites")
			:SetBackgroundColor("PRIMARY_BG_ALT")
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
		:AddChild(UIElements.New("DividedContainer", "content")
			:SetContextTable(private.scanDividedContainer, SCAN_DIVIDED_CONTAINER_DEFAULT)
			:SetMinWidth(520, 300)
			:SetBackgroundColor("PRIMARY_BG_ALT")
			:SetLeftChild(UIElements.New("AuctionScrollTable", "auctions")
				:SetSettings(private.settings, "marketTrapAuctionScrollingTable")
				:SetCreatedGroupName(L["Market Trap"].." - "..state.searchName)
				:SetBrowseResultsVisible(true)
				:SetRowScoreFunction(TSM.MarketTrap.GetRowScore)
				:SetRowFilterFunction(state.favoriteScanOnly and TSM.MarketTrap.ShouldShowFavoriteRow or TSM.MarketTrap.ShouldShowRow)
				:SetRowFavoriteFunction(private.IsRowFavorite)
				:SetRowFavoriteChangedFunction(private.SetRowFavorite)
				:SetIsPlayerFunction(PlayerInfo.AuctionOwnerIsPlayer)
			)
			:SetRightChild(private.GetReviewPanel(state))
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
	private.auctionBuyScan:SetAuctionScrollTable(frame:GetElement("content.auctions"))
end

---@param state MarketTrapUIState
function private.GetReviewPanel(state)
	return UIElements.New("Frame", "review")
		:SetLayout("VERTICAL")
		:SetPadding(8)
		:SetBackgroundColor("PRIMARY_BG_ALT")
		:AddChild(private.CreateHeading("reviewHeading", L["Candidate Review"]))
		:AddChild(UIElements.New("Text", "candidateText")
			:SetHeight(170)
			:SetMargin(0, 0, 0, 8)
			:SetFont("BODY_BODY2")
			:SetJustifyV("TOP")
			:SetTextPublisher(state:PublisherForKeyChange("candidateText"))
		)
		:AddChild(UIElements.New("ActionButton", "reviewBtn")
			:SetHeight(24)
			:SetMargin(0, 0, 0, 8)
			:SetText(L["Review Candidate"])
			:SetAction("OnClick", "ACTION_REVIEW_CANDIDATE")
		)
		:AddChild(UIElements.New("ActionButton", "executeBtn")
			:SetHeight(24)
			:SetMargin(0, 0, 0, 12)
			:SetText(L["Controlled Execute"])
			:SetDisabledPublisher(state:PublisherForKeyChange("candidateIsValid"):InvertBoolean())
			:SetAction("OnClick", "ACTION_CONTROLLED_EXECUTE")
		)
		:AddChild(UIElements.New("HorizontalLine", "line"))
		:AddChild(private.CreateHeading("executeHeading", L["Execute Actions"]))
		:AddChild(UIElements.New("Text", "executeText")
			:SetHeight(120)
			:SetFont("BODY_BODY2")
			:SetJustifyV("TOP")
			:SetTextPublisher(state:PublisherForKeyChange("executeText"))
		)
end

---@param state MarketTrapUIState
function private.GetSelectedScanRow(state)
	return state.scanFrame and state.scanFrame:GetElement("content.auctions"):GetSelectedRow() or nil
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
		state.favoriteScanOnly = false
		manager:ProcessAction("ACTION_START_SEARCH", private.GetGroupSearchContext(state))
	elseif action == "ACTION_START_FAVORITE_SCAN" then
		state.favoriteScanOnly = true
		manager:ProcessAction("ACTION_START_SEARCH", private.GetFavoriteSearchContext())
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
		state.executeText = L["Controlled Execute actions will appear here."]
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
		state.executeText = ""
		state.candidateIsValid = false
		state.favoriteScanOnly = false
		state.frame:SetPath("selection", true)
		private.auctionBuyScan:EndSearch()
	elseif action == "ACTION_REVIEW_CANDIDATE" then
		local candidate, reason = TSM.MarketTrap.BuildCandidate(private.GetSelectedScanRow(state))
		local isValid, validationReason = TSM.MarketTrap.ValidateCandidate(candidate)
		state.candidateText = TSM.MarketTrap.GetCandidateText(candidate, reason or validationReason).."\n"..validationReason
		state.executeText = isValid and L["Candidate is ready for controlled execution."] or validationReason
		state.candidateIsValid = isValid
	elseif action == "ACTION_CONTROLLED_EXECUTE" then
		local candidate, reason = TSM.MarketTrap.BuildCandidate(private.GetSelectedScanRow(state))
		local isValid, validationReason = TSM.MarketTrap.ValidateCandidate(candidate)
		state.candidateText = TSM.MarketTrap.GetCandidateText(candidate, reason or validationReason).."\n"..validationReason
		state.candidateIsValid = isValid
		if isValid then
			state.executeText = L["Opening the post action for this candidate."]
			private.auctionBuyScan:PostAuction()
		else
			state.executeText = validationReason
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

function private.GetFavoriteSearchContext()
	local filterList = TempTable.Acquire()
	for itemString in TSM.MarketTrap.FavoriteIterator() do
		local itemName = ItemInfo.GetName(itemString)
		if itemName then
			tinsert(filterList, itemName.."/exact")
		end
	end
	local searchContext = #filterList > 0 and TSM.Shopping.FilterSearch.GetSearchContext(table.concat(filterList, ";")) or nil
	TempTable.Release(filterList)
	return searchContext
end

function private.IsRowFavorite(row)
	local itemString = row:GetItemString() or row:GetBaseItemString()
	return itemString and TSM.MarketTrap.IsFavorite(itemString) or false
end

function private.SetRowFavorite(row, isFavorite)
	local itemString = row:GetItemString() or row:GetBaseItemString()
	if not itemString then
		return
	end
	TSM.MarketTrap.SetFavorite(itemString, isFavorite)
	private.state.hasFavoriteTraps = TSM.MarketTrap.GetNumFavorites() > 0
end
