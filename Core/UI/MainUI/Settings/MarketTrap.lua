-- ------------------------------------------------------------------------------ --
--                                TradeSkillMaster                                --
--                          https://tradeskillmaster.com                          --
--    All Rights Reserved - Detailed license information included with addon.     --
-- ------------------------------------------------------------------------------ --

local TSM = select(2, ...) ---@type TSM
local MarketTrap = TSM.MainUI.Settings:NewPackage("MarketTrap") ---@type AddonPackage
local L = TSM.Locale.GetTable()
local UIElements = TSM.LibTSMUI:Include("Util.UIElements")
local UIUtils = TSM.LibTSMUI:Include("Util.UIUtils")
local private = {
	settings = nil,
}
local SETTING_TOOLTIPS = {
	maxAuctions = L["The maximum number of auctions an item can have before it stops being considered a Market Trap candidate."],
	maxQuantity = L["The maximum total quantity an item can have before it stops being considered a Market Trap candidate."],
	maxSpendPerItem = L["The maximum gold Market Trap should allow for a single candidate during controlled execute."],
	maxTotalSpend = L["The maximum total gold Market Trap should allow during a controlled execute session."],
	maxDepositCost = L["The maximum deposit cost Market Trap should allow when reviewing controlled execute candidates."],
	targetPrice = L["The price source used as the target repost price for Market Trap candidates."],
	scoreFormula = L["The Market Trap scoring formula. Available variables include scarcity, quantityScarcity, valueGap, numAuctions, quantity, itemBuyout, and targetPrice."],
	minScore = L["The minimum Market Trap score required for controlled execute."],
	maxCandidates = L["The maximum number of candidates to review from a discovery scan."],
	trapPostQuantity = L["The number of items to post when reposting a Market Trap candidate."],
	ignoreNoSaleData = L["If enabled, Market Trap will reject candidates when required sale data is missing."],
	requireConfirmation = L["If enabled, Market Trap keeps controlled execute actions behind the normal TSM and Auction House confirmation flow."],
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
		:AddKey("global", "marketTrapOptions", "ignoreNoSaleData")
		:AddKey("global", "marketTrapOptions", "requireConfirmation")

	TSM.MainUI.Settings.RegisterSettingPage(L["Market Trap"], "middle", private.GetMarketTrapSettingsFrame)
end



-- ============================================================================
-- Market Trap Settings UI
-- ============================================================================

function private.GetMarketTrapSettingsFrame()
	UIUtils.AnalyticsRecordPathChange("main", "settings", "marketTrap")
	return UIElements.New("ScrollFrame", "marketTrapSettings")
		:SetPadding(8, 8, 8, 0)
		:AddChild(TSM.MainUI.Settings.CreateExpandableSection("MarketTrap", "discovery", L["Discovery Scan"], L["Controls which auctions are considered during a Market Trap discovery scan."])
			:AddChild(private.CreateNumberInput("maxAuctions", L["Maximum auctions"], "0:9999", SETTING_TOOLTIPS.maxAuctions))
			:AddChild(private.CreateNumberInput("maxQuantity", L["Maximum quantity"], "0:999999", SETTING_TOOLTIPS.maxQuantity))
			:AddChild(private.CreateNumberInput("maxCandidates", L["Maximum candidates"], "0:9999", SETTING_TOOLTIPS.maxCandidates))
			:AddChild(private.CreateCheckbox("ignoreNoSaleData", L["Ignore candidates with missing sale data"], SETTING_TOOLTIPS.ignoreNoSaleData))
		)
		:AddChild(TSM.MainUI.Settings.CreateExpandableSection("MarketTrap", "review", L["Candidate Review"], L["Controls how Market Trap scores and prices candidates."])
			:AddChild(private.CreateTextInput("scoreFormula", L["Score formula"], SETTING_TOOLTIPS.scoreFormula))
			:AddChild(private.CreateNumberInput("minScore", L["Minimum score"], "0:999999", SETTING_TOOLTIPS.minScore))
			:AddChild(TSM.MainUI.Settings.CreateInputWithReset("targetPrice", L["Target repost price"], private.settings, "targetPrice", nil, nil, SETTING_TOOLTIPS.targetPrice)
				:SetMargin(0, 0, 0, 12)
			)
		)
		:AddChild(TSM.MainUI.Settings.CreateExpandableSection("MarketTrap", "execute", L["Controlled Execute"], L["Controls Market Trap spend limits and execution safeguards."])
			:AddChild(TSM.MainUI.Settings.CreateInputWithReset("maxSpendPerItem", L["Maximum spend per item"], private.settings, "maxSpendPerItem", nil, nil, SETTING_TOOLTIPS.maxSpendPerItem)
				:SetMargin(0, 0, 0, 12)
			)
			:AddChild(TSM.MainUI.Settings.CreateInputWithReset("maxTotalSpend", L["Maximum total spend"], private.settings, "maxTotalSpend", nil, nil, SETTING_TOOLTIPS.maxTotalSpend)
				:SetMargin(0, 0, 0, 12)
			)
			:AddChild(TSM.MainUI.Settings.CreateInputWithReset("maxDepositCost", L["Maximum deposit cost"], private.settings, "maxDepositCost", nil, nil, SETTING_TOOLTIPS.maxDepositCost)
				:SetMargin(0, 0, 0, 12)
			)
			:AddChild(private.CreateNumberInput("trapPostQuantity", L["Trap post quantity"], "1:999999", SETTING_TOOLTIPS.trapPostQuantity))
			:AddChild(private.CreateCheckbox("requireConfirmation", L["Require confirmation flow"], SETTING_TOOLTIPS.requireConfirmation))
		)
end



-- ============================================================================
-- Private Helper Functions
-- ============================================================================

function private.CreateNumberInput(settingKey, label, range, tooltip)
	return UIElements.New("Frame", settingKey)
		:SetLayout("VERTICAL")
		:SetMargin(0, 0, 0, 12)
		:AddChild(UIElements.New("Text", "label")
			:SetHeight(18)
			:SetMargin(0, 0, 0, 4)
			:SetFont("BODY_BODY2_MEDIUM")
			:SetText(label)
		)
		:AddChild(UIElements.New("Frame", "content")
			:SetLayout("HORIZONTAL")
			:SetHeight(24)
			:AddChild(UIElements.New("Input", "input")
				:SetMargin(0, 8, 0, 0)
				:SetBackgroundColor("ACTIVE_BG")
				:SetFont("BODY_BODY2_MEDIUM")
				:SetValidateFunc("NUMBER", range)
				:SetSettingInfo(private.settings, settingKey)
				:SetTooltip(tooltip, "__parent")
			)
			:AddChild(UIElements.New("ActionButton", "resetButton")
				:SetWidth(108)
				:SetText(L["Reset"])
				:SetScript("OnClick", private.ResetButtonOnClick)
				:SetContext(settingKey)
			)
		)
end

function private.CreateTextInput(settingKey, label, tooltip)
	return UIElements.New("Frame", settingKey)
		:SetLayout("VERTICAL")
		:SetMargin(0, 0, 0, 12)
		:AddChild(UIElements.New("Text", "label")
			:SetHeight(18)
			:SetMargin(0, 0, 0, 4)
			:SetFont("BODY_BODY2_MEDIUM")
			:SetText(label)
		)
		:AddChild(UIElements.New("Frame", "content")
			:SetLayout("HORIZONTAL")
			:SetHeight(24)
			:AddChild(UIElements.New("Input", "input")
				:SetMargin(0, 8, 0, 0)
				:SetBackgroundColor("ACTIVE_BG")
				:SetFont("BODY_BODY2_MEDIUM")
				:SetSettingInfo(private.settings, settingKey)
				:SetTooltip(tooltip, "__parent")
			)
			:AddChild(UIElements.New("ActionButton", "resetButton")
				:SetWidth(108)
				:SetText(L["Reset"])
				:SetScript("OnClick", private.ResetButtonOnClick)
				:SetContext(settingKey)
			)
		)
end

function private.CreateCheckbox(settingKey, label, tooltip)
	return UIElements.New("Frame", settingKey)
		:SetLayout("HORIZONTAL")
		:SetHeight(20)
		:SetMargin(0, 0, 0, 12)
		:AddChild(UIElements.New("Checkbox", "checkbox")
			:SetWidth("AUTO")
			:SetFont("BODY_BODY2_MEDIUM")
			:SetText(label)
			:SetSettingInfo(private.settings, settingKey)
			:SetTooltip(tooltip)
		)
		:AddChild(UIElements.New("Spacer", "spacer"))
end

function private.ResetButtonOnClick(button)
	local settingKey = button:GetContext()
	private.settings:ResetToDefault(settingKey)
	button:GetElement("__parent.input")
		:SetValue(private.settings[settingKey])
		:Draw()
end
