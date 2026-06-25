-- ------------------------------------------------------------------------------ --
--                                TradeSkillMaster                                --
--                          https://tradeskillmaster.com                          --
--    All Rights Reserved - Detailed license information included with addon.     --
-- ------------------------------------------------------------------------------ --

local TSM = select(2, ...) ---@type TSM
local MarketTrap = TSM:NewPackage("MarketTrap")
local L = TSM.Locale.GetTable()
local CustomPrice = TSM.LibTSMApp:Include("Service.CustomPrice")
local ItemInfo = TSM.LibTSMService:Include("Item.ItemInfo")
local Money = TSM.LibTSMUtil:Include("UI.Money")
local Math = TSM.LibTSMUtil:Include("Lua.Math")
local private = {
	settings = nil,
	totalSpend = 0,
	sellerTemp = {},
}
local SCORE_FORMULA_ENV = {
	min = min,
	max = max,
	floor = floor,
	ceil = ceil,
	abs = abs,
}
local OLD_DEFAULT_SCORE_FORMULA = "scarcity * 100 + valueGap"
local DEFAULT_SCORE_FORMULA = "quantityScarcity * 75 + sellerScarcity * 25"



-- ============================================================================
-- Module Functions
-- ============================================================================

function MarketTrap.OnInitialize(settingsDB)
	private.settings = settingsDB:NewView()
		:AddKey("global", "marketTrapOptions", "maxAuctions")
		:AddKey("global", "marketTrapOptions", "maxQuantity")
		:AddKey("global", "marketTrapOptions", "maxSpendPerItem")
		:AddKey("global", "marketTrapOptions", "maxTotalSpend")
		:AddKey("global", "marketTrapOptions", "maxDepositCost")
		:AddKey("global", "marketTrapOptions", "targetPrice")
		:AddKey("global", "marketTrapOptions", "scoreFormula")
		:AddKey("global", "marketTrapOptions", "minScore")
		:AddKey("global", "marketTrapOptions", "maxCandidates")
		:AddKey("global", "marketTrapOptions", "trapPostQuantity")
		:AddKey("global", "marketTrapOptions", "showBelowMinScore")
		:AddKey("global", "marketTrapOptions", "ignoreNoSaleData")
		:AddKey("global", "marketTrapOptions", "requireConfirmation")
		:AddKey("global", "userData", "marketTrapFavorites")
	if private.settings.scoreFormula == OLD_DEFAULT_SCORE_FORMULA then
		private.settings.scoreFormula = DEFAULT_SCORE_FORMULA
	end
end

function MarketTrap.ResetExecuteSession()
	private.totalSpend = 0
end

function MarketTrap.RecordSpend(amount)
	private.totalSpend = private.totalSpend + (amount or 0)
end

function MarketTrap.BuildCandidate(row)
	if not row then
		return nil, L["Select an auction first."]
	end
	local success, itemString, quantity, numAuctions, numSellers, buyout, itemBuyout, isCommodity = pcall(private.GetRowInfo, row)
	if not success then
		return nil, L["The selected auction is no longer available. Select it again after the scan updates."]
	end
	if not itemString then
		return nil, L["The selected auction does not have item information yet."]
	end
	if not isCommodity then
		return nil, L["Market Trap only supports commodities."]
	end
	local targetPrice = private.GetTargetPrice(itemString)
	if not quantity or not numAuctions or not itemBuyout then
		return nil, L["The selected auction does not have complete pricing data yet."]
	end
	local score = private.CalculateScore(quantity, numAuctions, numSellers, itemBuyout, targetPrice)
	return {
		itemString = itemString,
		itemName = ItemInfo.GetName(itemString) or itemString,
		quantity = quantity,
		numAuctions = numAuctions,
		numSellers = numSellers,
		buyout = buyout or (itemBuyout * quantity),
		itemBuyout = itemBuyout,
		targetPrice = targetPrice,
		score = score,
	}
end

function MarketTrap.ValidateCandidate(candidate)
	if not candidate then
		return false, L["Select an auction first."]
	end
	if candidate.numSellers > private.settings.maxAuctions then
		return false, format(L["Too many sellers: %d / %d."], candidate.numSellers, private.settings.maxAuctions)
	end
	if candidate.quantity > private.settings.maxQuantity then
		return false, format(L["Too much quantity: %d / %d."], candidate.quantity, private.settings.maxQuantity)
	end
	local minScore = Math.Bound(private.settings.minScore, 0, 100)
	if candidate.score < minScore then
		return false, format(L["Score too low: %d / %d."], candidate.score, minScore)
	end
	local maxSpendPerItem = Money.FromString(private.settings.maxSpendPerItem) or math.huge
	if candidate.buyout > maxSpendPerItem then
		return false, format(L["Candidate cost is above the per-item limit: %s / %s."], Money.ToStringForUI(candidate.buyout), Money.ToStringForUI(maxSpendPerItem))
	end
	local maxTotalSpend = Money.FromString(private.settings.maxTotalSpend) or math.huge
	if private.totalSpend + candidate.buyout > maxTotalSpend then
		return false, format(L["Controlled execute spend limit reached: %s / %s."], Money.ToStringForUI(private.totalSpend + candidate.buyout), Money.ToStringForUI(maxTotalSpend))
	end
	if private.settings.ignoreNoSaleData and not candidate.targetPrice then
		return false, L["Target price could not be evaluated for the selected item."]
	end
	return true, L["Candidate passed controlled execute checks."]
end

function MarketTrap.GetCandidateText(candidate, reason)
	if not candidate then
		return reason or L["No candidate selected."]
	end
	local targetPriceText = candidate.targetPrice and Money.ToStringForUI(candidate.targetPrice) or "---"
	return format(
		L["%s: score %d, %d sellers, %d quantity, current %s, target %s"],
		candidate.itemName,
		candidate.score,
		candidate.numSellers,
		candidate.quantity,
		Money.ToStringForUI(candidate.itemBuyout),
		targetPriceText
	)
end

function MarketTrap.GetPostQuantity(_, defaultQuantity)
	return Math.Bound(private.settings.trapPostQuantity, 1, defaultQuantity or 1)
end

function MarketTrap.IsFavorite(itemString)
	return private.settings.marketTrapFavorites[itemString] and true or false
end

function MarketTrap.SetFavorite(itemString, isFavorite)
	if isFavorite then
		private.settings.marketTrapFavorites[itemString] = true
	else
		private.settings.marketTrapFavorites[itemString] = nil
	end
end

function MarketTrap.GetNumFavorites()
	local numFavorites = 0
	for _ in pairs(private.settings.marketTrapFavorites) do
		numFavorites = numFavorites + 1
	end
	return numFavorites
end

function MarketTrap.FavoriteIterator()
	return pairs(private.settings.marketTrapFavorites)
end

function MarketTrap.IsFavoriteActive(itemString)
	return TSM.MyAuctions.IsItemPosted(itemString)
end

function MarketTrap.GetRowScore(row)
	local candidate = MarketTrap.BuildCandidate(row)
	return candidate and candidate.score or nil
end

function MarketTrap.ShouldShowRow(row)
	local candidate = MarketTrap.BuildCandidate(row)
	if not candidate then
		return false
	end
	return private.settings.showBelowMinScore or candidate.score >= Math.Bound(private.settings.minScore, 0, 100)
end

function MarketTrap.ShouldShowFavoriteRow(row)
	local candidate = MarketTrap.BuildCandidate(row)
	if not candidate or not MarketTrap.IsFavorite(candidate.itemString) then
		return false
	end
	return true
end



-- ============================================================================
-- Private Helper Functions
-- ============================================================================

function private.GetRowInfo(row)
	local itemString = row:GetItemString() or row:GetBaseItemString()
	local quantity, numAuctions, numSellers = private.GetRowStats(row)
	local buyout, itemBuyout, minPrice = row:GetBuyouts()
	itemBuyout = itemBuyout or minPrice
	return itemString, quantity, numAuctions, numSellers, buyout, itemBuyout, row:IsCommodity()
end

function private.GetTargetPrice(itemString)
	local value = CustomPrice.GetValue(private.settings.targetPrice, itemString)
	return value and max(value, 1) or nil
end

function private.CalculateScore(quantity, numAuctions, numSellers, itemBuyout, targetPrice)
	local maxAuctions = max(private.settings.maxAuctions, 1)
	local maxQuantity = max(private.settings.maxQuantity, 1)
	local sellerScarcity = private.CalculateScarcity(numSellers or numAuctions or maxAuctions, maxAuctions)
	local quantityScarcity = private.CalculateScarcity(quantity or maxQuantity, maxQuantity)
	local valueGap = targetPrice and max(0, (targetPrice - itemBuyout) / max(itemBuyout, 1)) or 0
	local formulaScore = private.EvaluateScoreFormula(private.settings.scoreFormula, {
		scarcity = sellerScarcity,
		sellerScarcity = sellerScarcity,
		quantityScarcity = quantityScarcity,
		valueGap = valueGap,
		numAuctions = numAuctions,
		numSellers = numSellers or numAuctions,
		quantity = quantity,
		itemBuyout = itemBuyout,
		targetPrice = targetPrice or 0,
	})
	return Math.Bound(floor(formulaScore or ((quantityScarcity * 75) + (sellerScarcity * 25))), 0, 100)
end

function private.CalculateScarcity(value, maxValue)
	if maxValue <= 1 then
		return value <= 1 and 1 or 0
	end
	return Math.Bound(1 - ((value - 1) / (maxValue - 1)), 0, 1)
end

function private.GetRowStats(row)
	local quantity, numAuctions = row:GetQuantities()
	local numSellers = nil
	local resultRow = row:IsSubRow() and row:GetResultRow() or row
	if resultRow and resultRow.SubRowIterator then
		quantity = 0
		numAuctions = 0
		for _, subRow in resultRow:SubRowIterator() do
			local subQuantity, subNumAuctions = subRow:GetQuantities()
			quantity = quantity + (subQuantity or 0) * (subNumAuctions or 1)
			numAuctions = numAuctions + (subNumAuctions or 1)
			local ownerStr = subRow:GetOwnerInfo()
			if ownerStr and ownerStr ~= "" then
				private.sellerTemp[ownerStr] = true
			end
		end
		numSellers = 0
		for _ in pairs(private.sellerTemp) do
			numSellers = numSellers + 1
		end
		if numSellers == 0 then
			numSellers = numAuctions
		end
		wipe(private.sellerTemp)
	end
	return quantity, numAuctions, numSellers or numAuctions
end

function private.EvaluateScoreFormula(formula, values)
	if type(formula) ~= "string" or formula == "" or strfind(formula, "[^%w%s_%.%+%-%*/%%%(%)<>=~,]") then
		return nil
	end
	local func = loadstring("return "..formula)
	if not func then
		return nil
	end
	local env = {}
	for key, value in pairs(SCORE_FORMULA_ENV) do
		env[key] = value
	end
	for key, value in pairs(values) do
		env[key] = value
	end
	setfenv(func, env)
	local success, result = pcall(func)
	return success and type(result) == "number" and result >= 0 and result or nil
end
