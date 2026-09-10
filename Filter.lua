local _, LMB = ...

local TEMP_FRIEND_NOTE = "LeaveMeBe:level-check"
local FRIEND_ONLINE_SOUND = 567518
local LEVEL_LOOKUP_TIMEOUT = 5
local LEVEL_CACHE_TTL = 60
local FAILED_LOOKUP_RETRY_DELAY = 30
local FRIEND_MESSAGE_GRACE = 2
local AUTO_REPLY_COOLDOWN = 60

-- System messages an automatic friend add or remove can produce. Templates
-- take the friend's name; the plain strings are add failures, which the
-- addon explains itself where they matter.
local FRIEND_MESSAGE_KEYS = {
    "ERR_FRIEND_ADDED_S", "ERR_FRIEND_REMOVED_S", "ERR_FRIEND_ALREADY_S",
    "ERR_FRIEND_ONLINE_SS", "ERR_FRIEND_OFFLINE_S",
    "ERR_FRIEND_NOT_FOUND", "ERR_FRIEND_WRONG_FACTION", "ERR_FRIEND_SELF",
    "ERR_FRIEND_ERROR", "ERR_FRIEND_DB_ERROR", "ERR_FRIEND_LIST_FULL",
}

local autoReplyCooldowns = {}
local pendingLevelChecks = {}
local temporaryLevelChecks = {}
local levelsByGUID = {}
local levelsByName = {}
local reachableRealms = {}
local friendSoundMuted = false
local friendListFull = false
local friendListFullCount = 0
local friendListUnavailableReported = false
local suppressedSystemMessages = {}
local loggingOut = false

-- RequiresFriendList APIs may return nothing when character friends are
-- unavailable. A missing list is not an empty list that can accept friends.
local function GetFriendCount()
    if C_FriendList.IsLegacyFriendSystemEnabled
        and not C_FriendList.IsLegacyFriendSystemEnabled()
    then
        return nil
    end
    local count = C_FriendList.GetNumFriends()
    return type(count) == "number" and count or nil
end

-- An add is only confirmed asynchronously, so its messages are hidden for
-- the whole lookup lifetime; a removal only needs a short grace period. A
-- longer window already in place is never shortened.
local function SuppressFriendMessages(name, duration)
    local expiresAt = GetTime() + duration
    local messages = {}
    for _, key in ipairs(FRIEND_MESSAGE_KEYS) do
        local template = _G[key]
        if type(template) == "string" then
            local message = template:format(name, name)
            local current = suppressedSystemMessages[message]
            if not current or current < expiresAt then
                suppressedSystemMessages[message] = expiresAt
                messages[#messages + 1] = message
            end
        end
    end
    C_Timer.After(duration, function()
        for _, message in ipairs(messages) do
            if suppressedSystemMessages[message] == expiresAt then
                suppressedSystemMessages[message] = nil
            end
        end
    end)
end

local function NormalizeRealm(realm)
    if type(realm) ~= "string" or realm == "" then
        return nil
    end

    return (realm:gsub("%s+", "")):lower()
end

local function RefreshReachableRealms()
    wipe(reachableRealms)

    local GetRealms = C_AutoComplete and C_AutoComplete.GetAutoCompleteRealms
        or GetAutoCompleteRealms
    local realms = GetRealms and GetRealms()
    if type(realms) == "table" then
        for index = 1, #realms do
            local realm = NormalizeRealm(realms[index])
            if realm then
                reachableRealms[realm] = true
            end
        end
    end

    local playerRealm = LMB:GetPlayerRealmKey()
    if playerRealm then
        reachableRealms[playerRealm] = true
    end
end

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
    local lookupName = GetLookupName(sender)
    -- The live friends list can know about a level-up before our cache expires.
    local info = C_FriendList.GetFriendInfo(lookupName)
    if info and type(info.level) == "number" and info.level > 0 then
        return info.level
    end

    -- A level only ever rises, so a result that already passes the threshold
    -- never needs another lookup; only lower levels are re-checked.
    local cached = guid and levelsByGUID[guid] or levelsByName[lookupName]
    if cached
        and (
            cached.level >= LeaveMeBeDB.minimumLevel
            or GetTime() < cached.expiresAt
        )
    then
        return cached.level
    end
end

-- The level lookup works by briefly adding the sender as a character friend,
-- which only succeeds on our own realm or a connected one, and only while the
-- friends list has room. Anyone else can never be resolved, so do not start a
-- lookup that is guaranteed to time out.
local function CanResolveLevel(sender)
    if friendListFull or GetFriendCount() == nil or loggingOut then
        return false
    end

    local realm = NormalizeRealm(GetLookupName(sender):match("%-(.+)$"))
    if not realm then
        return true
    end

    return reachableRealms[realm] == true
end

function LMB:EvaluateWhisper(sender, guid, specialFlags, skipLevelLookup)
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
            and not skipLevelLookup
            and CanResolveLevel(sender)
    end

    if LeaveMeBeDB.allowContacts
        and self.sessionContacts[self:GetCharacterKey(sender)] ~= nil
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

local function LogWhisper(message, sender, guid, lineID, timestamp, reason)
    LeaveMeBeLog[#LeaveMeBeLog + 1] = {
        timestamp = timestamp or time(),
        character = GetPlayerName(),
        sender = sender,
        message = message,
        guid = guid,
        lineID = lineID,
        reason = reason,
    }
end

local function SendAutomaticReply(message, sender)
    -- Do not answer another Leave Me Be auto-reply. This prevents two users
    -- with the addon from creating an infinite whisper loop.
    if LMB:IsAutoReply(message) then
        return
    end

    local reply = LMB:GetAutoReply(sender)
    if not reply then
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

    C_ChatInfo.SendChatMessage(reply, "WHISPER", nil, sender)
end

local function BlockWhisper(message, sender, guid, lineID, timestamp)
    LogWhisper(message, sender, guid, lineID, timestamp)
    SendAutomaticReply(message, sender)
end

local function ReplayWhisper(entry)
    if LMB.PrepareWhisperWindow then
        LMB:PrepareWhisperWindow(entry.sender)
    end
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

local function FlushLevelCheck(record)
    for index = 1, #record.entries do
        local entry = record.entries[index]
        local decision = LMB:EvaluateWhisper(
            entry.sender,
            entry.guid,
            entry.specialFlags,
            true
        )
        if loggingOut then
            LogWhisper(entry.message, entry.sender, entry.guid, entry.lineID,
                entry.timestamp, "level-check-interrupted")
        elseif decision == "allow" then
            ReplayWhisper(entry)
        else
            BlockWhisper(entry.message, entry.sender, entry.guid,
                entry.lineID, entry.timestamp)
        end
    end

    C_Timer.After(2, function()
        if temporaryLevelChecks[record.key] == record then
            temporaryLevelChecks[record.key] = nil
        end
    end)
    FinishFriendSoundSuppression()
end

local function ResolveLevelCheck(record, level)
    if pendingLevelChecks[record.key] ~= record then
        return
    end

    pendingLevelChecks[record.key] = nil
    local resolvedLevel = type(level) == "number" and level > 0 and level or 0
    local duration = resolvedLevel > 0 and LEVEL_CACHE_TTL or FAILED_LOOKUP_RETRY_DELAY
    local cached = {
        level = resolvedLevel,
        expiresAt = GetTime() + duration,
    }
    if record.guid then
        levelsByGUID[record.guid] = cached
    end
    levelsByName[record.lookupName] = cached

    FlushLevelCheck(record)
end

-- Give up on a check without caching a level, so the sender can be looked up
-- again once the friends list has room.
local function AbandonLevelCheck(record)
    if pendingLevelChecks[record.key] ~= record then
        return
    end

    pendingLevelChecks[record.key] = nil
    FlushLevelCheck(record)
end

local function RemoveTemporaryFriend(record)
    for index = GetFriendCount() or 0, 1, -1 do
        local info = C_FriendList.GetFriendInfoByIndex(index)
        if info
            and info.notes == TEMP_FRIEND_NOTE
            and (
                (record.guid and info.guid == record.guid)
                or GetLookupName(info.name) == record.lookupName
            )
        then
            SuppressFriendMessages(info.name, FRIEND_MESSAGE_GRACE)
            C_FriendList.RemoveFriendByIndex(index)
            return
        end
    end
end

-- Nothing in flight can resolve any more, so stop hiding those whispers
-- instead of leaving them in limbo until the lookup times out.
local function AbandonAllLevelChecks()
    local records = {}
    for _, record in pairs(pendingLevelChecks) do
        records[#records + 1] = record
    end

    for index = 1, #records do
        RemoveTemporaryFriend(records[index])
        AbandonLevelCheck(records[index])
    end
end

local function HandleFriendListFull()
    friendListFullCount = GetFriendCount()

    if not friendListFull then
        friendListFull = true
        LMB:Print(
            "your friends list is full, so unknown players cannot be checked "
                .. "against the minimum level. Remove a friend to restore the "
                .. "level exception."
        )
    end

    AbandonAllLevelChecks()
end

-- Character friends can be unavailable altogether (12.1 without the legacy
-- friend system). Explain once why a blocked player was not level-checked,
-- as HandleFriendListFull does for a full list.
local function ReportUnavailableFriendList(sender, guid)
    if friendListUnavailableReported
        or loggingOut
        or not LeaveMeBeDB.allowByLevel
        or not LeaveMeBeDB.blockAllWhispers
        or GetCachedLevel(sender, guid) ~= nil
        or GetFriendCount() ~= nil
    then
        return
    end

    friendListUnavailableReported = true
    LMB:Print(
        "character friends are unavailable, so unknown players cannot be "
            .. "checked against the minimum level."
    )
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
        temporaryLevelChecks[key] = record
    end

    record.entries[#record.entries + 1] = {
        message = message,
        sender = sender,
        specialFlags = specialFlags,
        lineID = lineID,
        guid = guid,
        timestamp = time(),
        count = select("#", ...),
        args = { ... },
    }

    if isNew then
        if not friendSoundMuted then
            MuteSoundFile(FRIEND_ONLINE_SOUND)
            friendSoundMuted = true
        end
        -- Arm cleanup before requesting the asynchronous operation.
        C_Timer.After(LEVEL_LOOKUP_TIMEOUT, function()
            if pendingLevelChecks[key] == record then
                RemoveTemporaryFriend(record)
                ResolveLevelCheck(record)
            end
        end)
        SuppressFriendMessages(
            record.lookupName,
            LEVEL_LOOKUP_TIMEOUT + FRIEND_MESSAGE_GRACE
        )
        C_FriendList.AddFriend(record.lookupName, TEMP_FRIEND_NOTE)
    end
end

local function ProcessFriendListUpdate()
    -- Any change in size means a slot may have opened up, so allow lookups
    -- again. A still-full list simply reports the error once more.
    local count = GetFriendCount()
    if friendListFull and count and count ~= friendListFullCount then
        friendListFull = false
    end

    for index = count or 0, 1, -1 do
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
                SuppressFriendMessages(info.name, FRIEND_MESSAGE_GRACE)
                C_FriendList.RemoveFriendByIndex(index)
                ResolveLevelCheck(record, info.level)
            elseif not record then
                SuppressFriendMessages(info.name, FRIEND_MESSAGE_GRACE)
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
    return LMB:IsAutoReply(message)
end

local function SystemMessageFilter(_, _, message)
    if LMB:IsSecretValue(message) then
        return false
    end
    local expiresAt = suppressedSystemMessages[message]
    return expiresAt ~= nil and GetTime() < expiresAt
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
            ReportUnavailableFriendList(sender, guid)
        end
    elseif event == "FRIENDLIST_UPDATE" then
        ProcessFriendListUpdate()
    elseif event == "CHAT_MSG_SYSTEM" then
        -- The client only reports a failed friend add through this message, so
        -- it is the sole signal that the level lookup can no longer work.
        local message = ...
        if not LMB:IsSecretValue(message)
            and type(ERR_FRIEND_LIST_FULL) == "string"
            and message == ERR_FRIEND_LIST_FULL
        then
            HandleFriendListFull()
        end
    elseif event == "PLAYER_LOGOUT" then
        -- Logout ends the lookup just like a timeout. Preserve the filtered
        -- messages before SavedVariables are written, without sending replies.
        loggingOut = true
        AbandonAllLevelChecks()
        if friendSoundMuted then
            UnmuteSoundFile(FRIEND_ONLINE_SOUND)
            friendSoundMuted = false
        end
    end
end)

local contactFrame = CreateFrame("Frame")
contactFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
contactFrame:SetScript("OnEvent", function(_, _, message, recipient)
    if LMB:IsSecretValue(message)
        or LMB:IsSecretValue(recipient)
        or LMB:IsAutoReply(message)
    then
        return
    end
    local key = LMB:GetCharacterKey(recipient)
    if key then
        LMB.sessionContacts[key] = true
    end
end)

function LMB:RegisterWhisperFilter()
    local AddMessageEventFilter = ChatFrameUtil
        and ChatFrameUtil.AddMessageEventFilter
        or ChatFrame_AddMessageEventFilter

    RefreshReachableRealms()

    AddMessageEventFilter("CHAT_MSG_WHISPER", IncomingWhisperFilter)
    AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", OutgoingWhisperFilter)
    AddMessageEventFilter("CHAT_MSG_SYSTEM", SystemMessageFilter)
    eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
    eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    eventFrame:RegisterEvent("FRIENDLIST_UPDATE")
    eventFrame:RegisterEvent("PLAYER_LOGOUT")
    C_FriendList.ShowFriends()
end
