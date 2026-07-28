local _, LMB = ...

local TEMP_FRIEND_NOTE = "LeaveMeBe:level-check"
local FRIEND_ONLINE_SOUND = 567518
local LEVEL_LOOKUP_TIMEOUT = 5
local AUTO_REPLY_COOLDOWN = 60

local pendingAutoReplies = 0
local autoReplyCooldowns = {}
local pendingLevelChecks = {}
local temporaryLevelChecks = {}
local levelsByGUID = {}
local levelsByName = {}
local friendSoundMuted = false
local suppressSystemMessagesUntil = 0

local function IsGroupMember(guid)
    if not guid then
        return false
    end

    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            if UnitGUID("raid" .. index) == guid then
                return true
            end
        end
    else
        for index = 1, GetNumSubgroupMembers() do
            if UnitGUID("party" .. index) == guid then
                return true
            end
        end
    end

    return false
end

local function IsFriend(guid)
    if not guid then
        return false
    end

    return C_FriendList.IsFriend(guid)
        or C_BattleNet.GetGameAccountInfoByGUID(guid) ~= nil
end

local function GetLookupName(name)
    return Ambiguate(name, "none")
end

local function GetLookupKey(sender, guid)
    return guid or GetLookupName(sender):lower()
end

local function GetCachedLevel(sender, guid)
    if guid and levelsByGUID[guid] ~= nil then
        return levelsByGUID[guid]
    end

    local lookupName = GetLookupName(sender)
    if levelsByName[lookupName] ~= nil then
        return levelsByName[lookupName]
    end

    local info = C_FriendList.GetFriendInfo(lookupName)
    if info and type(info.level) == "number" and info.level > 0 then
        return info.level
    end
end

function LMB:EvaluateWhisper(sender, guid, specialFlags)
    -- Chat payloads can be secret during Midnight's messaging lockdown.
    -- Secret values cannot safely be compared, indexed, or transformed.
    if self:IsSecretValue(sender)
        or self:IsSecretValue(guid)
        or self:IsSecretValue(specialFlags)
    then
        return "allow"
    end

    if specialFlags == "GM" or specialFlags == "DEV" then
        return "allow"
    end

    if self:IsNameListed(LeaveMeBeDB.blocklist, sender) then
        return "block"
    end

    if self:IsNameListed(LeaveMeBeDB.allowlist, sender) then
        return "allow"
    end

    if not LeaveMeBeDB.blockAllWhispers then
        return "allow"
    end

    local lookupKey = GetLookupKey(sender, guid)
    if pendingLevelChecks[lookupKey] then
        return "lookup"
    end

    local needsLevelLookup = false
    if LeaveMeBeDB.allowByLevel then
        local level = GetCachedLevel(sender, guid)
        if level and level >= LeaveMeBeDB.minimumLevel then
            return "allow"
        end
        needsLevelLookup = not level
    end

    if LeaveMeBeDB.allowContacts
        and self:IsNameListed(self.sessionContacts, sender)
    then
        return "allow"
    end

    if LeaveMeBeDB.allowFriends
        and guid
        and not temporaryLevelChecks[lookupKey]
        and IsFriend(guid)
    then
        return "allow"
    end

    if LeaveMeBeDB.allowGuild and guid and IsGuildMember(guid) then
        return "allow"
    end

    if LeaveMeBeDB.allowGroup and IsGroupMember(guid) then
        return "allow"
    end

    if LeaveMeBeDB.allowByLevel and needsLevelLookup then
        return "lookup"
    end

    return "block"
end

function LMB:ShouldBlockWhisper(sender, guid, specialFlags)
    return self:EvaluateWhisper(sender, guid, specialFlags) ~= "allow"
end

local function GetPlayerName()
    local name, realm = UnitFullName("player")
    if not name then
        return "Unknown"
    end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function LogWhisper(message, sender, guid, lineID)
    LeaveMeBeLog[#LeaveMeBeLog + 1] = {
        timestamp = time(),
        character = GetPlayerName(),
        sender = sender,
        message = message,
        guid = guid,
        lineID = lineID,
    }
end

local function SendAutomaticReply(message, sender)
    -- Do not answer another Leave Me Be auto-reply. This prevents two users
    -- with the addon from creating an infinite whisper loop.
    if LMB:IsAutoReply(message) then
        return
    end

    local senderKey = GetLookupName(sender):lower()
    if autoReplyCooldowns[senderKey] then
        return
    end
    autoReplyCooldowns[senderKey] = true
    C_Timer.After(AUTO_REPLY_COOLDOWN, function()
        autoReplyCooldowns[senderKey] = nil
    end)

    pendingAutoReplies = pendingAutoReplies + 1
    C_ChatInfo.SendChatMessage(LMB:GetAutoReply(), "WHISPER", nil, sender)
    C_Timer.After(1, function()
        pendingAutoReplies = math.max(0, pendingAutoReplies - 1)
    end)
end

local function BlockWhisper(message, sender, guid, lineID)
    LogWhisper(message, sender, guid, lineID)
    SendAutomaticReply(message, sender)
end

local function ReplayWhisper(entry)
    local frames = { GetFramesRegisteredForEvent("CHAT_MSG_WHISPER") }
    for index = 1, #frames do
        local frame = frames[index]
        local name = frame.GetName and frame:GetName()
        if type(name) == "string"
            and name:find("^ChatFrame")
            and not frame:IsForbidden()
        then
            if ChatFrame_MessageEventHandler then
                ChatFrame_MessageEventHandler(
                    frame,
                    "CHAT_MSG_WHISPER",
                    unpack(entry.args, 1, entry.count)
                )
            else
                frame:MessageEventHandler(
                    "CHAT_MSG_WHISPER",
                    unpack(entry.args, 1, entry.count)
                )
            end
        end
    end
end

local function FinishFriendSoundSuppression()
    if next(pendingLevelChecks) or not friendSoundMuted then
        return
    end

    C_Timer.After(1, function()
        if not next(pendingLevelChecks) and friendSoundMuted then
            UnmuteSoundFile(FRIEND_ONLINE_SOUND)
            friendSoundMuted = false
        end
    end)
end

local function ResolveLevelCheck(record, level)
    if pendingLevelChecks[record.key] ~= record then
        return
    end

    pendingLevelChecks[record.key] = nil
    local resolvedLevel = type(level) == "number" and level > 0 and level or 0
    if record.guid then
        levelsByGUID[record.guid] = resolvedLevel
    end
    levelsByName[record.lookupName] = resolvedLevel

    for index = 1, #record.entries do
        local entry = record.entries[index]
        local decision = LMB:EvaluateWhisper(
            entry.sender,
            entry.guid,
            entry.specialFlags
        )
        if decision == "allow" then
            ReplayWhisper(entry)
        else
            BlockWhisper(
                entry.message,
                entry.sender,
                entry.guid,
                entry.lineID
            )
        end
    end

    C_Timer.After(2, function()
        temporaryLevelChecks[record.key] = nil
    end)
    FinishFriendSoundSuppression()
end

local function RemoveTemporaryFriend(record)
    for index = C_FriendList.GetNumFriends(), 1, -1 do
        local info = C_FriendList.GetFriendInfoByIndex(index)
        if info
            and info.notes == TEMP_FRIEND_NOTE
            and (
                (record.guid and info.guid == record.guid)
                or GetLookupName(info.name) == record.lookupName
            )
        then
            suppressSystemMessagesUntil = math.max(
                suppressSystemMessagesUntil,
                GetTime() + 2
            )
            C_FriendList.RemoveFriendByIndex(index)
            return
        end
    end
end

local function QueueLevelCheck(...)
    local message, sender, _, _, _, specialFlags, _, _, _, _, lineID, guid = ...
    local key = GetLookupKey(sender, guid)
    local record = pendingLevelChecks[key]
    local isNew = not record

    if not record then
        record = {
            key = key,
            sender = sender,
            lookupName = GetLookupName(sender),
            guid = guid,
            entries = {},
        }
        pendingLevelChecks[key] = record
        temporaryLevelChecks[key] = true
    end

    record.entries[#record.entries + 1] = {
        message = message,
        sender = sender,
        specialFlags = specialFlags,
        lineID = lineID,
        guid = guid,
        count = select("#", ...),
        args = { ... },
    }

    if isNew then
        if not friendSoundMuted then
            MuteSoundFile(FRIEND_ONLINE_SOUND)
            friendSoundMuted = true
        end
        suppressSystemMessagesUntil = math.max(
            suppressSystemMessagesUntil,
            GetTime() + 2
        )
        C_FriendList.AddFriend(record.lookupName, TEMP_FRIEND_NOTE)

        C_Timer.After(LEVEL_LOOKUP_TIMEOUT, function()
            if pendingLevelChecks[key] == record then
                RemoveTemporaryFriend(record)
                ResolveLevelCheck(record)
            end
        end)
    end
end

local function ProcessFriendListUpdate()
    for index = C_FriendList.GetNumFriends(), 1, -1 do
        local info = C_FriendList.GetFriendInfoByIndex(index)
        if info and info.notes == TEMP_FRIEND_NOTE then
            local lookupName = GetLookupName(info.name)
            local key = info.guid or lookupName:lower()
            local record = pendingLevelChecks[key]

            if not record then
                for _, candidate in pairs(pendingLevelChecks) do
                    if candidate.lookupName == lookupName then
                        record = candidate
                        break
                    end
                end
            end

            if record and type(info.level) == "number" and info.level > 0 then
                suppressSystemMessagesUntil = math.max(
                    suppressSystemMessagesUntil,
                    GetTime() + 2
                )
                C_FriendList.RemoveFriendByIndex(index)
                ResolveLevelCheck(record, info.level)
            elseif not record then
                suppressSystemMessagesUntil = math.max(
                    suppressSystemMessagesUntil,
                    GetTime() + 2
                )
                C_FriendList.RemoveFriendByIndex(index)
            end
        end
    end
end

local function IncomingWhisperFilter(
    _,
    _,
    _,
    sender,
    _,
    _,
    _,
    specialFlags,
    _,
    _,
    _,
    _,
    _,
    guid
)
    return LMB:ShouldBlockWhisper(sender, guid, specialFlags)
end

local function OutgoingWhisperFilter(_, _, message)
    return pendingAutoReplies > 0 or LMB:IsAutoReply(message)
end

local function SystemMessageFilter()
    return GetTime() < suppressSystemMessagesUntil
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_WHISPER" then
        local message, sender, _, _, _, specialFlags, _, _, _, _, lineID, guid = ...
        if LMB:IsSecretValue(message)
            or LMB:IsSecretValue(sender)
            or LMB:IsSecretValue(lineID)
            or LMB:IsSecretValue(guid)
            or LMB:IsSecretValue(specialFlags)
        then
            return
        end

        if type(message) ~= "string"
            or type(sender) ~= "string"
            or type(lineID) ~= "number"
        then
            return
        end

        local decision = LMB:EvaluateWhisper(sender, guid, specialFlags)
        if decision == "lookup" then
            QueueLevelCheck(...)
        elseif decision == "block" then
            BlockWhisper(message, sender, guid, lineID)
        end
    elseif event == "FRIENDLIST_UPDATE" then
        ProcessFriendListUpdate()
    elseif event == "PLAYER_LOGOUT" and friendSoundMuted then
        UnmuteSoundFile(FRIEND_ONLINE_SOUND)
        friendSoundMuted = false
    end
end)

local contactFrame = CreateFrame("Frame")
contactFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
contactFrame:SetScript("OnEvent", function(_, _, message, recipient)
    if LMB:IsSecretValue(message)
        or LMB:IsSecretValue(recipient)
        or pendingAutoReplies > 0
        or LMB:IsAutoReply(message)
    then
        return
    end
    LMB:SetListed(LMB.sessionContacts, recipient, true)
end)

function LMB:RegisterWhisperFilter()
    local AddMessageEventFilter = ChatFrameUtil
        and ChatFrameUtil.AddMessageEventFilter
        or ChatFrame_AddMessageEventFilter

    AddMessageEventFilter("CHAT_MSG_WHISPER", IncomingWhisperFilter)
    AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", OutgoingWhisperFilter)
    AddMessageEventFilter("CHAT_MSG_SYSTEM", SystemMessageFilter)
    eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
    eventFrame:RegisterEvent("FRIENDLIST_UPDATE")
    eventFrame:RegisterEvent("PLAYER_LOGOUT")
    C_FriendList.ShowFriends()
end
