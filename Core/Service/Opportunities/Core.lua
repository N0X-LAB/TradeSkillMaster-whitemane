--                                TradeSkillMaster                                --
--                          https://tradeskillmaster.com                          --
--    All Rights Reserved - Detailed license information included with addon.     --
-- ------------------------------------------------------------------------------ --

local TSM = select(2, ...) ---@type TSM
local Opportunities = TSM:NewPackage("Opportunities")
local L = TSM.Locale.GetTable()
local ChatMessage = TSM.LibTSMService:Include("UI.ChatMessage")
local Threading = TSM.LibTSMTypes:Include("Threading")
local CustomString = TSM.LibTSMTypes:Include("CustomString")
local Money = TSM.LibTSMUtil:Include("UI.Money")
local Math = TSM.LibTSMUtil:Include("Lua.Math")
local AuctionSearchContext = TSM.LibTSMService:IncludeClassType("AuctionSearchContext")
local LibTSMClass = LibStub("LibTSMClass")
local OpportunitiesSearchContext = LibTSMClass.DefineClass("OpportunitiesSearchContext", AuctionSearchContext)
local private = {
	settings = nil,
	scanThreadId = nil,
	searchContext = nil,
	itemList = {},
	itemScore = {},
	maxQuantity = {},
}



-- ============================================================================
-- Module Functions
-- ============================================================================

function Opportunities.OnInitialize(settingsDB)
	private.settings = settingsDB:NewView()
		:AddKey("global", "opportunitiesOptions", "valueSource")
		:AddKey("global", "opportunitiesOptions", "maxPricePct")
		:AddKey("global", "opportunitiesOptions", "minMarketValue")
		:AddKey("global", "opportunitiesOptions", "minAuctions")
		:AddKey("global", "opportunitiesOptions", "maxCandidates")
		:AddKey("global", "opportunitiesOptions", "maxBuyQuantity")

	private.scanThreadId = Threading.New("OPPORTUNITIES_SCAN", private.ScanThread)
	private.searchContext = OpportunitiesSearchContext(private.scanThreadId, private.MarketValueFunction)
end

function Opportunities.GetSearchContext()
	return private.searchContext:SetScanContext("Opportunities", nil, nil, private.settings.valueSource)
end



-- ============================================================================
-- Search Context Class
-- ============================================================================

function OpportunitiesSearchContext.GetMaxCanBuy(self, itemString)
	return private.maxQuantity[itemString]
end

function OpportunitiesSearchContext.OnBuy(self, itemString, quantity)
	self.__super:OnBuy(itemString, quantity)
	if not private.maxQuantity[itemString] then
		return
	end
	private.maxQuantity[itemString] = private.maxQuantity[itemString] - quantity
	if private.maxQuantity[itemString] <= 0 then
		private.maxQuantity[itemString] = nil
	end
end



-- ============================================================================
-- Scan Thread
-- ============================================================================

function private.ScanThread(auctionScan)
	local lastScanTime = TSM.AuctionDB.GetAppDataUpdateTimes()
	if lastScanTime == 0 then
		ChatMessage.PrintUser(L["No recent AuctionDB scan data found."])
		return false
	end

	wipe(private.itemList)
	wipe(private.itemScore)
	wipe(private.maxQuantity)

	local minMarketValue = Money.FromString(private.settings.minMarketValue) or 0
	local maxPricePct = Math.Bound(private.settings.maxPricePct, 1, 1000) / 100
	local minAuctions = max(private.settings.minAuctions, 0)
	for itemString, minBuyout in TSM.AuctionDB.LastScanIteratorThreaded() do
		local marketValue = private.GetMarketValue(itemString)
		local numAuctions = TSM.AuctionDB.GetRealmItemData(itemString, "numAuctions") or 0
		if minBuyout and minBuyout > 0 and marketValue and marketValue >= minMarketValue and numAuctions >= minAuctions and minBuyout <= marketValue * maxPricePct then
			tinsert(private.itemList, itemString)
			private.itemScore[itemString] = minBuyout / marketValue
			private.maxQuantity[itemString] = private.settings.maxBuyQuantity
		end
		Threading.Yield()
	end

	if #private.itemList == 0 then
		ChatMessage.PrintUser("No opportunities matched your current settings.")
		return false
	end

	sort(private.itemList, private.ItemSort)
	while #private.itemList > private.settings.maxCandidates do
		private.maxQuantity[tremove(private.itemList)] = nil
	end

	auctionScan:AddItemListQueriesThreaded(private.itemList)
	for _, query in auctionScan:QueryIterator() do
		query:AddCustomFilter(private.QueryFilter)
	end

	if not auctionScan:ScanQueriesThreaded() then
		ChatMessage.PrintUser(L["TSM failed to scan some auctions. Please rerun the scan."])
	end
	return true
end

function private.QueryFilter(_, row)
	local itemString = row:GetItemString()
	if not itemString then
		return true
	end
	local _, itemBuyout = row:GetBuyouts()
	if not itemBuyout or itemBuyout == 0 then
		return true
	end
	local marketValue = private.GetMarketValue(itemString)
	if not marketValue or marketValue == 0 then
		return true
	end
	return itemBuyout > marketValue * (Math.Bound(private.settings.maxPricePct, 1, 1000) / 100)
end

function private.MarketValueFunction(row)
	return private.GetMarketValue(row:GetItemString() or row:GetBaseItemString())
end

function private.GetMarketValue(itemString)
	return CustomString.GetValue(private.settings.valueSource, itemString)
end

function private.ItemSort(a, b)
	local aScore = private.itemScore[a] or math.huge
	local bScore = private.itemScore[b] or math.huge
	if aScore ~= bScore then
		return aScore < bScore
	end
	return a < b
end
