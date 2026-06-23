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
}
local SCORE_FORMULA_ENV = {
	min = min,
	max = max,
	floor = floor,
	ceil = ceil,
	abs = abs,
}



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
	local success, itemString, quantity, numAuctions, buyout, itemBuyout, isCommodity = pcall(private.GetRowInfo, row)
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
	local score = private.CalculateScore(quantity, numAuctions, itemBuyout, targetPrice)
	return {
		itemString = itemString,
		itemName = ItemInfo.GetName(itemString) or itemString,
		quantity = quantity,
		numAuctions = numAuctions,
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
	if candidate.numAuctions > private.settings.maxAuctions then
		return false, format(L["Too many auctions: %d / %d."], candidate.numAuctions, private.settings.maxAuctions)
	end
	if candidate.quantity > private.settings.maxQuantity then
		return false, format(L["Too much quantity: %d / %d."], candidate.quantity, private.settings.maxQuantity)
	end
	if candidate.score < private.settings.minScore then
		return false, format(L["Score too low: %d / %d."], candidate.score, private.settings.minScore)
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
		L["%s: score %d, %d auctions, %d quantity, current %s, target %s"],
		candidate.itemName,
		candidate.score,
		candidate.numAuctions,
		candidate.quantity,
		Money.ToStringForUI(candidate.itemBuyout),
		targetPriceText
	)
end

function MarketTrap.GetPostQuantity(_, defaultQuantity)
	return Math.Bound(private.settings.trapPostQuantity, 1, defaultQuantity or 1)
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
	return private.settings.showBelowMinScore or candidate.score >= private.settings.minScore
end



-- ============================================================================
-- Private Helper Functions
-- ============================================================================

function private.GetRowInfo(row)
	local itemString = row:GetItemString() or row:GetBaseItemString()
	local quantity, numAuctions = row:GetQuantities()
	local buyout, itemBuyout, minPrice = row:GetBuyouts()
	itemBuyout = itemBuyout or minPrice
	return itemString, quantity, numAuctions, buyout, itemBuyout, row:IsCommodity()
end

function private.GetTargetPrice(itemString)
	local value = CustomPrice.GetValue(private.settings.targetPrice, itemString)
	return value and max(value, 1) or nil
end

function private.CalculateScore(quantity, numAuctions, itemBuyout, targetPrice)
	local maxAuctions = max(private.settings.maxAuctions, 1)
	local maxQuantity = max(private.settings.maxQuantity, 1)
	local scarcity = max(0, (maxAuctions - numAuctions + 1) / maxAuctions)
	local quantityScarcity = max(0, (maxQuantity - quantity + 1) / maxQuantity)
	local valueGap = targetPrice and max(0, (targetPrice - itemBuyout) / max(itemBuyout, 1)) or 0
	local formulaScore = private.EvaluateScoreFormula(private.settings.scoreFormula, {
		scarcity = scarcity,
		quantityScarcity = quantityScarcity,
		valueGap = valueGap,
		numAuctions = numAuctions,
		quantity = quantity,
		itemBuyout = itemBuyout,
		targetPrice = targetPrice or 0,
	})
	return floor(formulaScore or ((scarcity * 60) + (quantityScarcity * 25) + min(valueGap * 15, 150)))
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
