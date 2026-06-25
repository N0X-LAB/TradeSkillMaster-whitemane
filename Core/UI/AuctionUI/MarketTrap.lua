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
local BagTracking = TSM.LibTSMService:Include("Inventory.BagTracking")
local ChatMessage = TSM.LibTSMService:Include("UI.ChatMessage")
local AuctionHouseWrapper = TSM.LibTSMWoW:Include("API.AuctionHouseWrapper")
local Item = TSM.LibTSMWoW:Include("API.Item")
local ItemClass = TSM.LibTSMWoW:Include("Util.ItemClass")
local Tooltip = TSM.LibTSMUI:Include("Tooltip")
local PlayerInfo = TSM.LibTSMApp:Include("Service.PlayerInfo")
local UIElements = TSM.LibTSMUI:Include("Util.UIElements")
local UIUtils = TSM.LibTSMUI:Include("Util.UIUtils")
local TempTable = TSM.LibTSMUtil:Include("BaseType.TempTable")
local Reactive = TSM.LibTSMUtil:Include("Reactive")
local UIManager = TSM.LibTSMUtil:IncludeClassType("UIManager")
local AuctionBuyScan = TSM.LibTSMUI:IncludeClassType("AuctionBuyScan")
local DEFAULT_ITEM_LEVEL_RANGE = "0,"..Item.GetMaxItemLevel()
local private = {
	auctionBuyScan = nil,
	manager = nil,
	state = nil,
	settings = nil,
	selectedGroups = {},
	updateCallbacks = {},
	recentPostedFavorites = {},
	rarityList = {},
}
local STATE_SCHEMA = Reactive.CreateStateSchema("MARKET_TRAP_UI_STATE")
	:AddOptionalTableField("frame")
	:AddOptionalTableField("scanFrame")
	:AddStringField("contentPath", "selection")
	:AddStringField("searchName", "")
	:AddBooleanField("groupSelectionCleared", true)
	:AddBooleanField("hasFavoriteTraps", false)
	:AddBooleanField("favoriteScanOnly", false)
	:AddStringField("advancedKeyword", "")
	:AddOptionalStringField("advancedClass")
	:AddOptionalStringField("advancedSubClass")
	:AddStringField("advancedItemLevelRange", DEFAULT_ITEM_LEVEL_RANGE)
	:AddOptionalStringField("advancedMinRarity")
	:AddOptionalTableField("pendingPostFuture")
	:AddOptionalStringField("pendingPostItemString")
	:AddNumberField("postDuration", 3)
	:Commit()
local FavoriteList = UIElements.Define("MarketTrapFavoriteList", "List")
FavoriteList:_AddActionScripts("OnPostTrap")
local FAVORITE_LIST_ROW_HEIGHT = 24
local ACTION_WIDTH = 118
local ACTION_BUTTON_WIDTH = 88
local STATUS_WIDTH = 90

function FavoriteList:__init()
	self.__super:__init()
	self._itemStrings = {}
	self._status = {}
	self._bagQuantity = {}
end

function FavoriteList:Acquire()
	self.__super:Acquire(FAVORITE_LIST_ROW_HEIGHT)
	self:UpdateData()
end

function FavoriteList:Release()
	wipe(self._itemStrings)
	wipe(self._status)
	wipe(self._bagQuantity)
	self.__super:Release()
end

function FavoriteList:UpdateData()
	wipe(self._itemStrings)
	wipe(self._status)
	wipe(self._bagQuantity)
	for itemString in TSM.MarketTrap.FavoriteIterator() do
		tinsert(self._itemStrings, itemString)
		self._status[itemString] = (TSM.MarketTrap.IsFavoriteActive(itemString) or private.recentPostedFavorites[itemString]) and L["Active"] or L["Inactive"]
		self._bagQuantity[itemString] = BagTracking.GetBagQuantity(itemString)
	end
	sort(self._itemStrings)
	self:_SetNumRows(#self._itemStrings)
	self:Draw()
end

---@param row ListRow
function FavoriteList.__protected:_HandleRowAcquired(row)
	local colSpacing = Theme.GetColSpacing()
	row:SetHighlightEnabled(true)
	local actionBg = row:AddTexture("actionBg")
	actionBg:SetHeight(20)
	actionBg:SetWidth(ACTION_BUTTON_WIDTH)
	actionBg:SetPoint("RIGHT", -colSpacing, 0)
	local actionOverlay = row:AddTexture("actionOverlay")
	actionOverlay:SetHeight(18)
	actionOverlay:SetWidth(ACTION_BUTTON_WIDTH - 2)
	actionOverlay:SetPoint("CENTER", actionBg, "CENTER")
	local actionText = row:AddText("actionText")
	actionText:SetHeight(20)
	actionText:SetWidth(ACTION_BUTTON_WIDTH)
	actionText:TSMSetFont("BODY_BODY3_MEDIUM")
	actionText:SetJustifyH("CENTER")
	actionText:SetPoint("CENTER", actionBg, "CENTER")
	row:AddMouseRegion("actionBtn", actionText, self:__closure("_GetPostTrapTooltip"), self:__closure("_HandlePostTrapClick"))
	local status = row:AddText("status")
	status:SetHeight(FAVORITE_LIST_ROW_HEIGHT)
	status:TSMSetFont("TABLE_TABLE1")
	status:SetJustifyH("RIGHT")
	status:SetPoint("RIGHT", actionBg, "LEFT", -colSpacing, 0)
	status:SetWidth(STATUS_WIDTH)
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
	local hasBagQuantity = self._bagQuantity[itemString] > 0
	row:GetTexture("actionBg"):TSMSetColorTexture("ACTIVE_BG")
	row:GetTexture("actionOverlay"):TSMSetShown(not hasBagQuantity)
	row:GetTexture("actionOverlay"):TSMSetColorTexture("PRIMARY_BG_ALT")
	row:GetText("actionText"):SetText((hasBagQuantity and Theme.GetColor("TEXT") or Theme.GetColor("ACTIVE_BG_ALT")):ColorText(L["Post Trap"]))
end

---@param row ListRow
function FavoriteList.__protected:_HandleRowEnter(row)
	row:ShowTooltip(self._itemStrings[row:GetDataIndex()])
	local itemString = self._itemStrings[row:GetDataIndex()]
	if self._bagQuantity[itemString] > 0 then
		row:GetTexture("actionBg"):TSMSetColorTexture("ACTIVE_BG+HOVER")
	end
end

---@param row ListRow
function FavoriteList.__protected:_HandleRowLeave(row)
	local itemString = self._itemStrings[row:GetDataIndex()]
	if self._bagQuantity[itemString] > 0 then
		row:GetTexture("actionBg"):TSMSetColorTexture("ACTIVE_BG")
	end
	Tooltip.Hide()
end

function FavoriteList.__private:_GetPostTrapTooltip(dataIndex)
	return self._itemStrings[dataIndex] and L["Post Trap"] or nil
end

function FavoriteList.__private:_HandlePostTrapClick(mouseButton, dataIndex)
	if mouseButton ~= "LeftButton" then
		return
	end
	local itemString = self._itemStrings[dataIndex]
	if itemString and self._bagQuantity[itemString] > 0 then
		self:_SendActionScript("OnPostTrap", itemString)
	end
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
	private.auctionBuyScan = AuctionBuyScan.NewBrose(L["Market Trap"], PlayerInfo.AuctionOwnerIsPlayer, nil, nil, nil, TSM.MarketTrap.GetPostQuantity, TSM.MarketTrap.GetPostQuantity, private.HandleBoughtItem)
	for i = 1, 7 do
		tinsert(private.rarityList, _G["ITEM_QUALITY"..i.."_DESC"])
	end
	state.advancedItemLevelRange = DEFAULT_ITEM_LEVEL_RANGE

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
		:AddChild(private.GetAdvancedSearchFrame(state))
		:AddChild(UIElements.New("HorizontalLine", "advancedLine")
			:SetMargin(0, 0, 12, 12)
		)
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
				:SetWidth(STATUS_WIDTH)
				:SetHeight(18)
				:SetMargin(0, 8, 0, 0)
				:SetFont("BODY_BODY3_MEDIUM")
				:SetJustifyH("RIGHT")
				:SetText(L["Status"])
			)
			:AddChild(UIElements.New("Text", "action")
				:SetWidth(ACTION_WIDTH)
				:SetHeight(18)
				:SetMargin(0, 8, 0, 0)
				:SetFont("BODY_BODY3_MEDIUM")
				:SetJustifyH("RIGHT")
				:SetText(L["Action"])
			)
		)
		:AddChild(UIElements.New("MarketTrapFavoriteList", "favorites")
			:SetBackgroundColor("PRIMARY_BG_ALT")
			:SetAction("OnPostTrap", "ACTION_POST_FAVORITE_TRAP")
		)
end

---@param state MarketTrapUIState
function private.GetAdvancedSearchFrame(state)
	return UIElements.New("Frame", "advancedSearch")
		:SetLayout("VERTICAL")
		:SetHeight(142)
		:SetMargin(0, 0, 0, 12)
		:AddChild(UIElements.New("Frame", "keywordRow")
			:SetLayout("HORIZONTAL")
			:SetHeight(24)
			:SetMargin(0, 0, 0, 8)
			:AddChild(UIElements.New("Input", "keyword")
				:SetIconTexture("iconPack.18x18/Search")
				:SetClearButtonEnabled(true)
				:SetHintText(L["Filter by Keyword"])
				:SetValuePublisher(state:PublisherForKeyChange("advancedKeyword"))
				:SetAction("OnValueChanged", "ACTION_ADVANCED_KEYWORD_CHANGED")
				:SetAction("OnEnterPressed", "ACTION_START_ADVANCED_DISCOVERY_SCAN")
			)
			:AddChild(UIElements.New("ActionButton", "runScanBtn")
				:SetWidth(120)
				:SetMargin(8, 0, 0, 0)
				:SetText(L["Run Scan"])
				:SetAction("OnClick", "ACTION_START_ADVANCED_DISCOVERY_SCAN")
			)
		)
		:AddChild(UIElements.New("Frame", "classLabels")
			:SetLayout("HORIZONTAL")
			:SetHeight(18)
			:AddChild(UIElements.New("Text", "classLabel")
				:SetFont("BODY_BODY2_MEDIUM")
				:SetText(L["Item Class"])
			)
			:AddChild(UIElements.New("Text", "subClassLabel")
				:SetMargin(8, 0, 0, 0)
				:SetFont("BODY_BODY2_MEDIUM")
				:SetText(L["Item Subclass"])
			)
		)
		:AddChild(UIElements.New("Frame", "classRow")
			:SetLayout("HORIZONTAL")
			:SetHeight(24)
			:SetMargin(0, 0, 0, 8)
			:AddChild(UIElements.New("ListDropdown", "class")
				:SetMargin(0, 8, 0, 0)
				:SetItems(ItemClass.GetClasses())
				:SetHintText(L["All Item Classes"])
				:SetSelectedItemSilentPublisher(state:PublisherForKeyChange("advancedClass"))
				:SetAction("OnSelectionChanged", "ACTION_ADVANCED_CLASS_CHANGED")
			)
			:AddChild(UIElements.New("ListDropdown", "subClass")
				:SetHintText(L["All Subclasses"])
				:SetDisabledPublisher(state:PublisherForKeyChange("advancedClass")
					:MapBooleanEquals(nil)
				)
				:SetSelectedItemSilentPublisher(state:PublisherForKeyChange("advancedSubClass"))
				:SetAction("OnSelectionChanged", "ACTION_ADVANCED_SUB_CLASS_CHANGED")
			)
		)
		:AddChild(UIElements.New("Frame", "filterLabels")
			:SetLayout("HORIZONTAL")
			:SetHeight(18)
			:AddChild(UIElements.New("Text", "itemLevelLabel")
				:SetFont("BODY_BODY2_MEDIUM")
				:SetText(L["Item Level Range"])
			)
			:AddChild(UIElements.New("Text", "rarityLabel")
				:SetWidth(180)
				:SetMargin(8, 0, 0, 0)
				:SetFont("BODY_BODY2_MEDIUM")
				:SetText(L["Minimum Rarity"])
			)
		)
		:AddChild(UIElements.New("Frame", "filterRow")
			:SetLayout("HORIZONTAL")
			:SetHeight(24)
			:AddChild(UIElements.New("RangeInput", "itemLevel")
				:SetRange(DEFAULT_ITEM_LEVEL_RANGE)
				:SetValuePublisher(state:PublisherForKeyChange("advancedItemLevelRange"))
				:SetAction("OnValueChanged", "ACTION_ADVANCED_ITEM_LEVEL_CHANGED")
			)
			:AddChild(UIElements.New("ListDropdown", "minRarity")
				:SetWidth(180)
				:SetMargin(8, 0, 0, 0)
				:SetItems(private.rarityList)
				:SetHintText(L["All"])
				:SetSelectedItemSilentPublisher(state:PublisherForKeyChange("advancedMinRarity"))
				:SetAction("OnSelectionChanged", "ACTION_ADVANCED_MIN_RARITY_CHANGED")
			)
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
			:SetRowFilterFunction(state.favoriteScanOnly and TSM.MarketTrap.ShouldShowFavoriteRow or TSM.MarketTrap.ShouldShowRow)
			:SetRowFavoriteFunction(private.IsRowFavorite)
			:SetRowFavoriteChangedFunction(private.SetRowFavorite)
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

---@param state MarketTrapUIState
function private.GetSelectedScanRow(state)
	return state.scanFrame and state.scanFrame:GetElement("auctions"):GetSelectedRow() or nil
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
	elseif action == "ACTION_ADVANCED_KEYWORD_CHANGED" then
		state.advancedKeyword = state.frame:GetElement("selection.overview.advancedSearch.keywordRow.keyword"):GetValue()
	elseif action == "ACTION_ADVANCED_CLASS_CHANGED" then
		state.advancedClass = state.frame:GetElement("selection.overview.advancedSearch.classRow.class"):GetSelectedItem()
		state.advancedSubClass = nil
		local subClassDropdown = state.frame:GetElement("selection.overview.advancedSearch.classRow.subClass")
		if state.advancedClass then
			subClassDropdown:SetItems(ItemClass.GetSubClasses(state.advancedClass))
		end
	elseif action == "ACTION_ADVANCED_SUB_CLASS_CHANGED" then
		state.advancedSubClass = state.frame:GetElement("selection.overview.advancedSearch.classRow.subClass"):GetSelectedItem()
	elseif action == "ACTION_ADVANCED_ITEM_LEVEL_CHANGED" then
		state.advancedItemLevelRange = state.frame:GetElement("selection.overview.advancedSearch.filterRow.itemLevel"):GetValue()
	elseif action == "ACTION_ADVANCED_MIN_RARITY_CHANGED" then
		state.advancedMinRarity = state.frame:GetElement("selection.overview.advancedSearch.filterRow.minRarity"):GetSelectedItem()
	elseif action == "ACTION_START_ADVANCED_DISCOVERY_SCAN" then
		state.favoriteScanOnly = false
		manager:ProcessAction("ACTION_START_SEARCH", private.GetAdvancedSearchContext(state))
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
		state.searchName = name ~= "" and name or L["Commodity Search"]
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
		state.favoriteScanOnly = false
		state.frame:SetPath("selection", true)
		private.auctionBuyScan:EndSearch()
	elseif action == "ACTION_POST_FAVORITE_TRAP" then
		private.ShowPostTrapDialog(state, ...)
	elseif action == "ACTION_POST_TRAP_CONFIRMED" then
		private.PostTrapConfirmed(manager, state, ...)
	elseif action == "ACTION_POST_TRAP_FUTURE_DONE" then
		local result = ...
		local itemString = state.pendingPostItemString
		state.pendingPostFuture = nil
		state.pendingPostItemString = nil
		if result then
			if itemString then
				TSM.MarketTrap.SetFavorite(itemString, true)
				private.recentPostedFavorites[itemString] = true
			end
			AuctionHouseWrapper.AutoQueryOwnedAuctions()
			private.RefreshFavoriteList(state)
		else
			ChatMessage.PrintUser(L["Failed to post auction due to the auction house being busy. Ensure no other addons are scanning the AH and try again."])
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
	local searchContext = TSM.Shopping.GroupSearch.GetSearchContext(private.selectedGroups, true)
	assert(searchContext)
	return searchContext
end

function private.GetFavoriteSearchContext()
	local filterList = TempTable.Acquire()
	for itemString in TSM.MarketTrap.FavoriteIterator() do
		local itemName = ItemInfo.GetName(itemString)
		if itemName and ItemInfo.IsCommodity(itemString) then
			tinsert(filterList, itemName.."/exact")
		end
	end
	local searchContext = #filterList > 0 and TSM.Shopping.FilterSearch.GetSearchContext(table.concat(filterList, ";"), nil, true, true) or nil
	TempTable.Release(filterList)
	return searchContext
end

---@param state MarketTrapUIState
function private.GetAdvancedSearchContext(state)
	local filterParts = TempTable.Acquire()
	local keyword = strtrim(state.advancedKeyword)
	if keyword ~= "" then
		tinsert(filterParts, keyword)
	end
	if state.advancedItemLevelRange ~= DEFAULT_ITEM_LEVEL_RANGE then
		local minItemLevel, maxItemLevel = strsplit(",", state.advancedItemLevelRange)
		assert(minItemLevel and maxItemLevel)
		tinsert(filterParts, "i"..minItemLevel)
		tinsert(filterParts, "i"..maxItemLevel)
	end
	if state.advancedClass then
		tinsert(filterParts, state.advancedClass)
	end
	if state.advancedSubClass then
		tinsert(filterParts, state.advancedSubClass)
	end
	if state.advancedMinRarity then
		tinsert(filterParts, state.advancedMinRarity)
	end
	local filter = table.concat(filterParts, " ")
	TempTable.Release(filterParts)
	return TSM.Shopping.FilterSearch.GetSearchContext(filter, nil, true, true)
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

function private.HandleBoughtItem(itemString, itemBuyout)
	TSM.MarketTrap.SetFavorite(itemString, true)
	local price = TSM.MarketTrap.GetPostPrice(itemString, itemBuyout)
	if price then
		TSM.MarketTrap.SetFavoritePostPrice(itemString, price)
	end
	private.state.hasFavoriteTraps = TSM.MarketTrap.GetNumFavorites() > 0
end

function private.ShowPostTrapDialog(state, itemString)
	local bagQuantity = BagTracking.GetBagQuantity(itemString)
	if bagQuantity <= 0 then
		ChatMessage.PrintUser(L["No auctionable quantity for this favorite trap item."])
		return
	end
	local price, errMsg = TSM.MarketTrap.GetPostPrice(itemString)
	if not price then
		ChatMessage.PrintUser(errMsg)
		return
	end
	local quantity = TSM.MarketTrap.GetPostQuantity(itemString, bagQuantity)
	state.frame:GetBaseElement():ShowDialogFrame(UIElements.New("ShoppingPostDialog", "dialog")
		:SetSize(326, 344)
		:AddAnchor("CENTER")
		:SetAuction(itemString, price, price, quantity, 0, 0, state.postDuration)
		:SetManager(private.manager)
		:SetAction("OnPostClicked", "ACTION_POST_TRAP_CONFIRMED")
	)
end

function private.PostTrapConfirmed(manager, state, itemString, duration, stackSize, numStacks, bid, buyout)
	state.postDuration = duration
	state.pendingPostItemString = itemString
	local postBag, postSlot = BagTracking.CreateQueryBagsItemAuctionable(itemString)
		:OrderBy("slotId", true)
		:Select("bag", "slot")
		:GetFirstResultAndRelease()
	if not postBag or not postSlot then
		state.pendingPostItemString = nil
		ChatMessage.PrintUser(L["No auctionable quantity for this favorite trap item."])
		return
	end
	numStacks = 1
	local future = AuctionHouseWrapper.PostAuction(postBag, postSlot, duration, stackSize, numStacks, bid, buyout)
	if future then
		manager:ManageFuture("pendingPostFuture", future, "ACTION_POST_TRAP_FUTURE_DONE")
	else
		manager:ProcessAction("ACTION_POST_TRAP_FUTURE_DONE", false)
	end
end

function private.RefreshFavoriteList(state)
	if state.frame and state.contentPath == "selection" then
		local favorites = state.frame:GetElement("selection.overview.favorites")
		favorites:UpdateData()
	end
end
