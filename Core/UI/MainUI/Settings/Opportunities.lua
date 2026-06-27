--                                TradeSkillMaster                                --
--                          https://tradeskillmaster.com                          --
--    All Rights Reserved - Detailed license information included with addon.     --
-- ------------------------------------------------------------------------------ --

local TSM = select(2, ...) ---@type TSM
local Opportunities = TSM.MainUI.Settings:NewPackage("Opportunities") ---@type AddonPackage
local L = TSM.Locale.GetTable()
local UIElements = TSM.LibTSMUI:Include("Util.UIElements")
local UIUtils = TSM.LibTSMUI:Include("Util.UIUtils")
local private = {
	settings = nil,
}
local SETTING_TOOLTIPS = {
	valueSource = "The market value source Opportunities compares against.",
	maxPricePct = "Auctions must be at or below this percentage of the configured value source.",
	minMarketValue = "Items below this market value are ignored.",
	minAuctions = "Items must have at least this many auctions in your local AuctionDB data.",
	maxCandidates = "The maximum number of locally-matched items to scan.",
	maxBuyQuantity = "The maximum quantity TSM will suggest buying for a single item.",
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

	TSM.MainUI.Settings.RegisterSettingPage("Opportunities", "middle", private.GetSettingsFrame)
end



-- ============================================================================
-- Opportunities Settings UI
-- ============================================================================

function private.GetSettingsFrame()
	UIUtils.AnalyticsRecordPathChange("main", "settings", "opportunities")
	return UIElements.New("ScrollFrame", "opportunitiesSettings")
		:SetPadding(8, 8, 8, 0)
		:AddChild(TSM.MainUI.Settings.CreateExpandableSection("Opportunities", "scan", L["Scan"], "Controls which locally-known items are scanned for buying opportunities.")
			:AddChild(TSM.MainUI.Settings.CreateInputWithReset("valueSource", "Value source", private.settings, "valueSource", nil, nil, SETTING_TOOLTIPS.valueSource)
				:SetMargin(0, 0, 0, 12)
			)
			:AddChild(private.CreateNumberInput("maxPricePct", "Maximum price percent", "1:1000", SETTING_TOOLTIPS.maxPricePct))
			:AddChild(TSM.MainUI.Settings.CreateInputWithReset("minMarketValue", "Minimum market value", private.settings, "minMarketValue", nil, nil, SETTING_TOOLTIPS.minMarketValue)
				:SetMargin(0, 0, 0, 12)
			)
			:AddChild(private.CreateNumberInput("minAuctions", "Minimum auctions", "0:999999", SETTING_TOOLTIPS.minAuctions))
			:AddChild(private.CreateNumberInput("maxCandidates", L["Maximum candidates"], "1:9999", SETTING_TOOLTIPS.maxCandidates))
			:AddChild(private.CreateNumberInput("maxBuyQuantity", "Maximum buy quantity", "1:999999", SETTING_TOOLTIPS.maxBuyQuantity))
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

function private.ResetButtonOnClick(button)
	local settingKey = button:GetContext()
	private.settings:ResetToDefault(settingKey)
	button:GetElement("__parent.input")
		:SetValue(private.settings[settingKey])
		:Draw()
end
