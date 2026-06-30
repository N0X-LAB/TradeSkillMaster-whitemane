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
local Math = TSM.LibTSMUtil:Include("Lua.Math")
local AuctionSearchContext = TSM.LibTSMService:IncludeClassType("AuctionSearchContext")
local LibTSMClass = LibStub("LibTSMClass")
local OpportunitiesSearchContext = LibTSMClass.DefineClass("OpportunitiesSearchContext", AuctionSearchContext)
local private = {
	settings = nil,
	scanThreadId = nil,
	searchContext = nil,
	maxQuantity = {},
	numMatches = 0,
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
	return private.maxQuantity[itemString] or private.settings.maxBuyQuantity
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
	wipe(private.maxQuantity)
	private.numMatches = 0

	auctionScan:NewQuery()
		:SetStr("")
		:SetIsBrowseDoneFunction(private.QueryIsBrowseDoneFunction)
		:AddCustomFilter(private.QueryFilter)

	if not auctionScan:ScanQueriesThreaded() then
		ChatMessage.PrintUser(L["TSM failed to scan some auctions. Please rerun the scan."])
	end
	return true
end

function private.QueryFilter(_, row, isSubRow, itemKey)
	if isSubRow and row.HasRawData and not row:HasRawData() then
		return false
	end

	local itemString = private.GetRowItemString(row)
	if not itemString then
		return false
	end

	local _, itemBuyout, minItemBuyout = row:GetBuyouts(itemKey)
	itemBuyout = itemBuyout or minItemBuyout
	if not itemBuyout then
		return false
	elseif itemBuyout == 0 then
		return true
	end

	local marketValue = private.GetMarketValue(itemString)
	if not marketValue or marketValue == 0 then
		return true
	end

	local minMarketValue = CustomString.GetValue(private.settings.minMarketValue, itemString) or 0
	if marketValue < minMarketValue then
		return true
	end

	local totalQuantity, numAuctions = row:GetQuantities()
	local availableCount = isSubRow and numAuctions or totalQuantity
	if availableCount and availableCount < max(private.settings.minAuctions, 0) then
		return true
	end

	local isFiltered = itemBuyout > marketValue * (Math.Bound(private.settings.maxPricePct, 1, 1000) / 100)
	if not isFiltered then
		if not private.maxQuantity[itemString] then
			private.numMatches = private.numMatches + 1
		end
		private.maxQuantity[itemString] = private.maxQuantity[itemString] or private.settings.maxBuyQuantity
	end
	return isFiltered
end

function private.QueryIsBrowseDoneFunction()
	return private.numMatches >= private.settings.maxCandidates
end

function private.MarketValueFunction(row)
	return private.GetMarketValue(private.GetRowItemString(row))
end

function private.GetRowItemString(row)
	if row:IsSubRow() and row.HasRawData and not row:HasRawData() then
		return nil
	end
	return row:GetItemString() or row:GetBaseItemString()
end

function private.GetMarketValue(itemString)
	if not itemString then
		return nil
	end
	return CustomString.GetValue(private.settings.valueSource, itemString)
end
