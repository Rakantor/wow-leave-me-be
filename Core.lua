local addonName, LMB = ...

local defaults = {
    blockAllWhispers = false,
    autoBlockPremadeListing = false,
    autoReplyMessage = "Sorry, {me} doesn't receive whispers right now!",
    allowByLevel = true,
    minimumLevel = 42,
    allowFriends = true,
    allowGuild = true,
    allowGroup = true,
    allowContacts = true,
    allowlist = {},
    blocklist = {},
}

LMB.name = addonName
LMB.sessionContacts = {}
LMB.autoReplyPrefix = "Leave Me Be (Addon):"
LMB.defaultAutoReplyMessage = defaults.autoReplyMessage
LMB.defaultMinimumLevel = defaults.minimumLevel

local IsSecretValue = issecretvalue or function()
    return false
end

local function CopyDefaults(source, destination)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(destination[key]) ~= "table" then
                destination[key] = {}
            end
            CopyDefaults(value, destination[key])
        elseif destination[key] == nil then
            destination[key] = value
        end
    end
end

local function NormalizeName(name)
    if type(name) ~= "string" then
        return nil
    end

    name = name:match("^%s*(.-)%s*$")
    if name == "" then
        return nil
    end

    return name:lower()
end

function LMB:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff73c2fbLeave Me Be:|r " .. message)
end

function LMB:SetBlockAllWhispers(enabled, automatically)
    LeaveMeBeDB.blockAllWhispers = enabled == true
    if not automatically and self.ReleasePremadeAutomationControl then
        self:ReleasePremadeAutomationControl()
    end
    if self.RefreshMainOptions then
        self:RefreshMainOptions()
    end
end

function LMB:IsSecretValue(value)
    return IsSecretValue(value)
end

function LMB:GetAutoReply(sender)
    local playerName = UnitName("player")
    if self:IsSecretValue(playerName)
        or self:IsSecretValue(sender)
        or type(playerName) ~= "string"
        or type(sender) ~= "string"
    then
        return nil
    end

    local replacements = {
        player = playerName,
        me = playerName,
        myself = playerName,
        sender = sender,
        they = sender,
        them = sender,
    }
    local message = LeaveMeBeDB.autoReplyMessage:gsub(
        "{([%a]+)}",
        function(token)
            return replacements[token]
        end
    )
    return self.autoReplyPrefix .. " " .. message
end

function LMB:IsAutoReply(message)
    if self:IsSecretValue(message) or type(message) ~= "string" then
        return false
    end

    return message:sub(1, #self.autoReplyPrefix) == self.autoReplyPrefix
end

function LMB:IsNameListed(list, name)
    local normalized = NormalizeName(name)
    if not normalized then
        return false
    end

    if list[normalized] then
        return true
    end

    local shortName = normalized:match("^([^-]+)")
    return shortName ~= normalized and list[shortName] == true
end

function LMB:SetListed(list, name, value)
    local normalized = NormalizeName(name)
    if not normalized then
        return false
    end

    list[normalized] = value or nil
    return true
end

local function StateText(value)
    return value and "|cff33ff99on|r" or "|cffff6666off|r"
end

function LMB:PrintStatus()
    self:Print(
        ("block all whispers %s; premade automation %s; level exception %s at %d; %d allowed, %d blocked"):format(
            StateText(LeaveMeBeDB.blockAllWhispers),
            StateText(LeaveMeBeDB.autoBlockPremadeListing),
            StateText(LeaveMeBeDB.allowByLevel),
            LeaveMeBeDB.minimumLevel,
            self:CountEntries(LeaveMeBeDB.allowlist),
            self:CountEntries(LeaveMeBeDB.blocklist)
        )
    )
end

function LMB:CountEntries(list)
    local count = 0
    for _ in pairs(list) do
        count = count + 1
    end
    return count
end

function LMB:PrintHelp()
    self:Print("commands:")
    self:Print("/lmb help - show all commands")
    self:Print("/lmb status - show the current state")
    self:Print("/lmb on|off - turn blocking all whispers on or off")
    self:Print("/lmb allow <name> - always allow a player")
    self:Print("/lmb unallow <name> - remove an allowlist entry")
    self:Print("/lmb block <name> - always block a player")
    self:Print("/lmb unblock <name> - remove a blocklist entry")
    self:Print("/lmb reply <message> - customize the auto-reply")
    self:Print("/lmb reply reset - restore the default auto-reply")
end

function LMB:HandleSlashCommand(input)
    local command, argument = input:match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    local normalizedArgument = argument:lower()

    if command == "on" or command == "off" then
        self:SetBlockAllWhispers(command == "on")
        self:Print(
            "block all whispers "
                .. StateText(LeaveMeBeDB.blockAllWhispers)
                .. "."
        )
    elseif command == "allow" and self:SetListed(LeaveMeBeDB.allowlist, argument, true) then
        self:SetListed(LeaveMeBeDB.blocklist, argument, false)
        self:Print("|cffffffff" .. argument .. "|r added to the allowlist.")
    elseif command == "unallow" and self:SetListed(LeaveMeBeDB.allowlist, argument, false) then
        self:Print("|cffffffff" .. argument .. "|r removed from the allowlist.")
    elseif command == "block" and self:SetListed(LeaveMeBeDB.blocklist, argument, true) then
        self:SetListed(LeaveMeBeDB.allowlist, argument, false)
        self:Print("|cffffffff" .. argument .. "|r added to the blocklist.")
    elseif command == "unblock" and self:SetListed(LeaveMeBeDB.blocklist, argument, false) then
        self:Print("|cffffffff" .. argument .. "|r removed from the blocklist.")
    elseif command == "reply" and normalizedArgument == "reset" then
        LeaveMeBeDB.autoReplyMessage = defaults.autoReplyMessage
        self:Print("the auto-reply was reset.")
    elseif command == "reply" and argument ~= "" then
        LeaveMeBeDB.autoReplyMessage = argument
        self:Print("the auto-reply was updated.")
    elseif command == "status" then
        self:PrintStatus()
    elseif command == "help" or command == "" then
        self:PrintHelp()
    else
        self:PrintHelp()
    end
end

function LMB:Initialize()
    if type(LeaveMeBeDB) ~= "table" then
        LeaveMeBeDB = {}
    end
    if type(LeaveMeBeLog) ~= "table" then
        LeaveMeBeLog = {}
    end
    if LeaveMeBeDB.blockAllWhispers == nil then
        LeaveMeBeDB.blockAllWhispers = LeaveMeBeDB.enabled ~= false
            and LeaveMeBeDB.mode == "known"
    end
    LeaveMeBeDB.enabled = nil
    LeaveMeBeDB.mode = nil
    CopyDefaults(defaults, LeaveMeBeDB)
    if type(LeaveMeBeDB.minimumLevel) ~= "number"
        or LeaveMeBeDB.minimumLevel < 1
    then
        LeaveMeBeDB.minimumLevel = defaults.minimumLevel
    end
    LeaveMeBeDB.minimumLevel = math.floor(LeaveMeBeDB.minimumLevel)
    if type(LeaveMeBeDB.autoReplyMessage) ~= "string"
        or LeaveMeBeDB.autoReplyMessage == ""
    then
        LeaveMeBeDB.autoReplyMessage = defaults.autoReplyMessage
    end

    SLASH_LEAVEMEBE1 = "/leavemebe"
    SLASH_LEAVEMEBE2 = "/lmb"
    SlashCmdList.LEAVEMEBE = function(input)
        LMB:HandleSlashCommand(input)
    end

    self:RegisterWhisperFilter()
    self:RegisterPremadeAutomation()
    self:RegisterOptions()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        LMB:Initialize()
    end
end)
