--                                TradeSkillMaster                                --
--                          https://tradeskillmaster.com                          --
--    All Rights Reserved - Detailed license information included with addon.     --
-- ------------------------------------------------------------------------------ --

local TSM = select(2, ...) ---@type TSM
local CancelTracker = TSM.Auctioning:NewPackage("CancelTracker") ---@type AddonPackage
local private = {
	data = nil,
	callbacks = {},
}
local DEFAULT_THRESHOLD = 1000



-- ============================================================================
-- Module Functions
-- ============================================================================

function CancelTracker.OnInitialize()
	private.data = private.GetDB()
	private.ResetIfNeeded()
end

function CancelTracker.RecordCancel()
	private.ResetIfNeeded()
	private.data.count = private.data.count + 1
	private.FireCallbacks()
end

function CancelTracker.GetCount()
	private.ResetIfNeeded()
	return private.data.count
end

function CancelTracker.GetThreshold()
	return max(private.GetDB().threshold or DEFAULT_THRESHOLD, 1)
end

function CancelTracker.SetThreshold(threshold)
	threshold = max(tonumber(threshold) or DEFAULT_THRESHOLD, 1)
	private.GetDB().threshold = threshold
	private.FireCallbacks()
end

function CancelTracker.GetShown()
	return private.GetDB().show
end

function CancelTracker.SetShown(show)
	private.GetDB().show = show and true or false
	private.FireCallbacks()
end

function CancelTracker.RegisterCallback(callback)
	tinsert(private.callbacks, callback)
end



-- ============================================================================
-- Private Helper Functions
-- ============================================================================

function private.GetDB()
	-- luacheck: globals TSMCancelTrackerDB
	TSMCancelTrackerDB = type(TSMCancelTrackerDB) == "table" and TSMCancelTrackerDB or {}
	TSMCancelTrackerDB.show = TSMCancelTrackerDB.show ~= false
	TSMCancelTrackerDB.threshold = max(tonumber(TSMCancelTrackerDB.threshold) or DEFAULT_THRESHOLD, 1)
	TSMCancelTrackerDB.count = tonumber(TSMCancelTrackerDB.count) or 0
	TSMCancelTrackerDB.date = type(TSMCancelTrackerDB.date) == "string" and TSMCancelTrackerDB.date or ""
	return TSMCancelTrackerDB
end

function private.ResetIfNeeded()
	local currentDate = date("%Y-%m-%d")
	local data = private.GetDB()
	if data.date == currentDate then
		return
	end
	data.date = currentDate
	data.count = 0
end

function private.FireCallbacks()
	for _, callback in ipairs(private.callbacks) do
		callback()
	end
end
