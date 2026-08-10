local _, LMB = ...

local AUTOMATIC_DISABLE_DELAY = 15
-- Listing state and group state arrive from separate subsystems and can be
-- read mid-transition, which briefly looks like "listed and not grouped".
-- Requiring the state to hold for a moment rejects those false positives.
local AUTOMATIC_ENABLE_DELAY = 1

local disablePending = false
local disableGeneration = 0
local enablePending = false
local enableGeneration = 0
local evaluationPending = false

local function CancelPendingDisable()
    disablePending = false
    disableGeneration = disableGeneration + 1
end

local function CancelPendingEnable()
    enablePending = false
    enableGeneration = enableGeneration + 1
end

local function IsLeadingActiveListing()
    if not C_LFGList.HasActiveEntryInfo() then
        return false
    end

    local isInHomeGroup = IsInGroup(LE_PARTY_CATEGORY_HOME)
    return not isInHomeGroup
        or UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME)
end

local function SetBlockingAutomatically(enabled)
    if LeaveMeBeDB.blockAllWhispers == enabled then
        return
    end

    LMB:SetBlockAllWhispers(enabled, true)
    LMB:Print(
        "Premade Group Finder automation turned blocking all whispers "
            .. (enabled and "|cff33ff99on|r." or "|cffff6666off|r.")
    )
end

local function ScheduleEnable()
    if enablePending then
        return
    end

    enablePending = true
    enableGeneration = enableGeneration + 1
    local generation = enableGeneration

    C_Timer.After(AUTOMATIC_ENABLE_DELAY, function()
        if generation ~= enableGeneration then
            return
        end
        enablePending = false

        -- Only act if the listing still looks like ours once the group and
        -- listing state have settled.
        if not LeaveMeBeDB.autoBlockPremadeListing
            or not IsLeadingActiveListing()
            or LeaveMeBeDB.blockAllWhispers
        then
            return
        end

        LeaveMeBeDB.premadeAutomationOwnsBlock = true
        SetBlockingAutomatically(true)
    end)
end

local function ScheduleDisable()
    if disablePending or not LeaveMeBeDB.premadeAutomationOwnsBlock then
        return
    end

    disablePending = true
    disableGeneration = disableGeneration + 1
    local generation = disableGeneration

    C_Timer.After(AUTOMATIC_DISABLE_DELAY, function()
        if generation ~= disableGeneration then
            return
        end
        disablePending = false

        if not LeaveMeBeDB.autoBlockPremadeListing
            or IsLeadingActiveListing()
            or not LeaveMeBeDB.premadeAutomationOwnsBlock
        then
            return
        end

        LeaveMeBeDB.premadeAutomationOwnsBlock = nil
        SetBlockingAutomatically(false)
    end)
end

local function EvaluateAutomation()
    if not LeaveMeBeDB.autoBlockPremadeListing then
        CancelPendingEnable()
        CancelPendingDisable()
        LeaveMeBeDB.premadeAutomationOwnsBlock = nil
        return
    end

    if IsLeadingActiveListing() then
        CancelPendingDisable()
        if not LeaveMeBeDB.blockAllWhispers then
            ScheduleEnable()
        end
    else
        -- A listing that stops looking like ours before the delay elapses was
        -- a transition, not something to act on.
        CancelPendingEnable()
        ScheduleDisable()
    end
end

-- Joining or leaving a group fires several of these events at once. Collapse
-- a burst into a single evaluation so the state is only read once it settles.
local function ScheduleEvaluation()
    if evaluationPending then
        return
    end

    evaluationPending = true
    C_Timer.After(0, function()
        evaluationPending = false
        EvaluateAutomation()
    end)
end

function LMB:ReleasePremadeAutomationControl()
    CancelPendingEnable()
    CancelPendingDisable()
    LeaveMeBeDB.premadeAutomationOwnsBlock = nil
end

function LMB:SetPremadeAutomationEnabled(enabled)
    LeaveMeBeDB.autoBlockPremadeListing = enabled == true
    if LeaveMeBeDB.autoBlockPremadeListing then
        EvaluateAutomation()
    else
        -- Hand back a blocking state that automation turned on, so switching
        -- the automation off does not leave blocking stuck on.
        local ownedBlock = LeaveMeBeDB.premadeAutomationOwnsBlock
        self:ReleasePremadeAutomationControl()
        if ownedBlock then
            SetBlockingAutomatically(false)
        end
    end
    if self.RefreshMainOptions then
        self:RefreshMainOptions()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", ScheduleEvaluation)

function LMB:RegisterPremadeAutomation()
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    eventFrame:RegisterEvent("LFG_GROUP_DELISTED_LEADERSHIP_CHANGE")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
    ScheduleEvaluation()
end
