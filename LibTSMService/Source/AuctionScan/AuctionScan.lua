-- ------------------------------------------------------------------------------ --
--                                TradeSkillMaster                                --
--                          https://tradeskillmaster.com                          --
--    All Rights Reserved - Detailed license information included with addon.     --
-- ------------------------------------------------------------------------------ --

local LibTSMService = select(2, ...).LibTSMService
local AuctionScan = LibTSMService:Init("AuctionScan")
local AuctionScanManager = LibTSMService:IncludeClassType("AuctionScanManager")
local FindThread = LibTSMService:Include("AuctionScan.FindThread")
local Lock = LibTSMService:Include("AuctionScan.Lock")
local private = {
	queryDoneCallbacks = {},
}



-- ============================================================================
-- Module Functions
-- ============================================================================

---Gets an auction scan manager.
---@return AuctionScanManager
function AuctionScan.GetManager()
	local manager = AuctionScanManager.Get()
	for callback in pairs(private.queryDoneCallbacks) do
		manager:AddQueryDoneCallback(callback)
	end
	return manager
end

---Registers a callback which is called whenever an auction scan query completes.
---@param callback fun(manager: AuctionScanManager, query: AuctionQuery)
function AuctionScan.RegisterQueryDoneCallback(callback)
	private.queryDoneCallbacks[callback] = true
end

---Stops any in-progress find thread.
---@param noKill boolean Don't kill the thread
function AuctionScan.StopFindThread(noKill)
	return FindThread.StopFindAuction(noKill)
end

---Configures the auction scan lock code.
---@param errorMessage string The error message to display if another scan is ongoing.
---@param callback fun(name: string) The function to call when the active scan changes
function AuctionScan.ConfigureLock(errorMessage, callback)
	Lock.Configure(errorMessage, callback)
end

---Attempts to acquire the scan lock at the start of a scan.
---@param name string The name of the type of scan being started
---@return boolean
function AuctionScan.AcquireLock(name)
	return Lock.Acquire(name)
end

---Releases the scan lock and the end of a scan.
---@param name string The name of the type of scan which is ending
function AuctionScan.ReleaseLock(name)
	Lock.Release(name)
end
