local _, LMB = ...

local AUTOMATIC_DISABLE_DELAY = 15

local disablePending = false
local disableGeneration = 0

local function CancelPendingDisable()
    disablePending = false
    disableGeneration = disableGeneration + 1
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
        CancelPendingDisable()
        LeaveMeBeDB.premadeAutomationOwnsBlock = nil
        return
    end

    if IsLeadingActiveListing() then
        CancelPendingDisable()
        if not LeaveMeBeDB.blockAllWhispers then
            LeaveMeBeDB.premadeAutomationOwnsBlock = true
            SetBlockingAutomatically(true)
        end
    else
        ScheduleDisable()
    end
end

function LMB:ReleasePremadeAutomationControl()
    CancelPendingDisable()
    LeaveMeBeDB.premadeAutomationOwnsBlock = nil
end

function LMB:SetPremadeAutomationEnabled(enabled)
    LeaveMeBeDB.autoBlockPremadeListing = enabled == true
    if LeaveMeBeDB.autoBlockPremadeListing then
        EvaluateAutomation()
    else
        self:ReleasePremadeAutomationControl()
    end
    if self.RefreshMainOptions then
        self:RefreshMainOptions()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", EvaluateAutomation)

function LMB:RegisterPremadeAutomation()
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    eventFrame:RegisterEvent("LFG_GROUP_DELISTED_LEADERSHIP_CHANGE")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
    EvaluateAutomation()
end
