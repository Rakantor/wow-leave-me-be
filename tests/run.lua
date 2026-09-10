-- Run from the repository root with Lua 5.1: lua5.1 tests/run.lua
local passed = 0
local function Test(name, body)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    local function Load(path, ...)
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)(...)
    end
    Load("tests/harness.lua")
    for _, path in ipairs({ "Core.lua", "Automation.lua", "Filter.lua", "ChatWindows.lua" }) do
        Load(path, "LeaveMeBe", env.LMB)
    end
    env.Initialize()
    local ok, err = pcall(setfenv(body, env))
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
    print("PASS " .. name)
end

Test("lookup defers side effects and replays each message once", function()
    Whisper("Alice", "Player-A", "first")
    Whisper("Alice", "Player-A", "second")
    Expect(#ADDS == 1 and #LeaveMeBeLog == 0 and #SENT == 0 and #DISPLAYED == 0)
    Resolve("Alice", "Player-A", 90)
    Expect(#DISPLAYED == 2 and #FRIENDS == 0 and #SENT == 0)
    Advance(10)
    Expect(#DISPLAYED == 2 and #LeaveMeBeLog == 0)
end)

Test("unreachable realm is blocked without a lookup", function()
    Whisper("Alice-FarRealm", "Player-A")
    Expect(#ADDS == 0 and #LeaveMeBeLog == 1 and #SENT == 1)
end)

Test("unavailable character friends cannot start a lookup", function()
    C_FriendList.GetNumFriends = function() return nil end
    Whisper("Alice", "Player-A")
    Emit("FRIENDLIST_UPDATE")
    Advance(10)
    Expect(#ADDS == 0 and #LeaveMeBeLog == 1)
    C_FriendList.GetNumFriends = function() return 0 end
    Whisper("Alice", "Player-A")
    Expect(#ADDS == 1)
end)

Test("disabled legacy friends cannot start a lookup and are explained once", function()
    LEGACY_FRIENDS_ENABLED = false
    Whisper("Alice", "Player-A")
    Expect(#ADDS == 0 and #LeaveMeBeLog == 1)
    Expect(#PRINTED == 1 and PRINTED[1]:find("unavailable", 1, true))
    Whisper("Bob", "Player-B")
    Expect(#PRINTED == 1 and #LeaveMeBeLog == 2)
end)

Test("blocklist and manual blocking do not report an unavailable friend list", function()
    LEGACY_FRIENDS_ENABLED = false
    LeaveMeBeDB.blockAllWhispers = false
    LMB:SetListed(LeaveMeBeDB.blocklist, "Alice", true)
    Whisper("Alice", "Player-A")
    Expect(#LeaveMeBeLog == 1 and #PRINTED == 0)
end)

Test("12.0.7 works without the legacy-system query", function()
    C_FriendList.IsLegacyFriendSystemEnabled = nil
    Whisper("Alice", "Player-A")
    Resolve("Alice", "Player-A", 90)
    Expect(#DISPLAYED == 1 and #FRIENDS == 0)
end)

Test("friend API disappearing during lookup does not strand messages", function()
    Whisper("Alice", "Player-A")
    C_FriendList.GetNumFriends = function() return nil end
    Emit("FRIENDLIST_UPDATE")
    Advance(5)
    Expect(#LeaveMeBeLog == 1 and #SENT == 1)
    Whisper("Alice", "Player-A")
    Expect(#LeaveMeBeLog == 2)
end)

Test("full-list failure abandons all checks without caching levels", function()
    Whisper("Alice", "Player-A")
    Whisper("Bob", "Player-B")
    FRIENDS = {{ name = "Existing", guid = "Player-E", level = 90 }}
    Emit("CHAT_MSG_SYSTEM", ERR_FRIEND_LIST_FULL)
    Expect(#LeaveMeBeLog == 2)
    Whisper("Carol", "Player-C")
    Expect(#ADDS == 2 and #LeaveMeBeLog == 3)
    FRIENDS = {}
    Emit("FRIENDLIST_UPDATE")
    Whisper("Alice", "Player-A")
    Expect(#ADDS == 3)
    Resolve("Alice", "Player-A", 90)
    Expect(#DISPLAYED == 1)
end)

Test("timeout removes the temporary friend and hides its removal", function()
    Whisper("Alice", "Player-A")
    FRIENDS = {{ name = "Alice", guid = "Player-A", level = 0, notes = "LeaveMeBe:level-check" }}
    Advance(5)
    Expect(#FRIENDS == 0 and #REMOVES == 1 and #LeaveMeBeLog == 1)
    Expect(FILTERS.CHAT_MSG_SYSTEM(nil, nil, ERR_FRIEND_REMOVED_S:format("Alice")))
    Advance(2)
    Expect(not FILTERS.CHAT_MSG_SYSTEM(nil, nil, ERR_FRIEND_REMOVED_S:format("Alice")))
end)

Test("timeout retries after a short cooldown", function()
    Whisper("Alice", "Player-A")
    Advance(5)
    Expect(#LeaveMeBeLog == 1)
    Whisper("Alice", "Player-A")
    Expect(#ADDS == 1 and #LeaveMeBeLog == 2)
    Advance(30)
    Whisper("Alice", "Player-A")
    Expect(#ADDS == 2 and #LeaveMeBeLog == 2)
    Resolve("Alice", "Player-A", 90)
    Expect(#DISPLAYED == 1)
end)

Test("fresh friend levels override cached failures and low levels", function()
    LeaveMeBeDB.allowFriends = false
    Whisper("Alice", "Player-A")
    Advance(5)
    FRIENDS = {{ name = "Alice", guid = "Player-A", level = 90 }}
    Expect(LMB:EvaluateWhisper("Alice", "Player-A", "") == "allow")
    FRIENDS = {}
    Whisper("Bob", "Player-B")
    Resolve("Bob", "Player-B", 41)
    FRIENDS = {{ name = "Bob", guid = "Player-B", level = 42 }}
    Expect(LMB:EvaluateWhisper("Bob", "Player-B", "") == "allow")
end)

Test("cached levels expire so a level-up can be discovered", function()
    Whisper("Alice", "Player-A")
    Resolve("Alice", "Player-A", 41)
    Expect(#LeaveMeBeLog == 1)
    Advance(60)
    Whisper("Alice", "Player-A")
    Expect(#ADDS == 2)
    Resolve("Alice", "Player-A", 42)
    Expect(#DISPLAYED == 1 and #LeaveMeBeLog == 1)
end)

Test("levels above the minimum are never looked up again", function()
    Whisper("Alice", "Player-A")
    Resolve("Alice", "Player-A", 90)
    Advance(600)
    Whisper("Alice", "Player-A")
    Expect(#ADDS == 1 and #DISPLAYED == 2 and #LeaveMeBeLog == 0)
    -- Raising the minimum above the known level re-checks it.
    LeaveMeBeDB.minimumLevel = 100
    Whisper("Alice", "Player-A")
    Expect(#ADDS == 2 and #DISPLAYED == 2)
end)

Test("filters remain side-effect free across chat frames", function()
    for _ = 1, 4 do
        Expect(FILTERS.CHAT_MSG_WHISPER(nil, "CHAT_MSG_WHISPER", "hello", "Alice",
            "", "", "", "", 0, 0, "", 0, 1, "Player-A"))
    end
    Expect(#ADDS == 0 and #LeaveMeBeLog == 0 and #SENT == 0)
    LeaveMeBeDB.allowByLevel = false
    Whisper("Alice", "Player-A")
    for _ = 1, 4 do
        LMB:ShouldBlockWhisper("Alice", "Player-A", "")
    end
    Expect(#LeaveMeBeLog == 1 and #SENT == 1)
end)

Test("only the temporary friend's notifications are suppressed", function()
    Whisper("Alice", "Player-A")
    local filter = FILTERS.CHAT_MSG_SYSTEM
    Expect(filter(nil, nil, ERR_FRIEND_ADDED_S:format("Alice")))
    Expect(filter(nil, nil, ERR_FRIEND_ONLINE_SS:format("Alice", "Alice")))
    Expect(filter(nil, nil, ERR_FRIEND_NOT_FOUND))
    Expect(filter(nil, nil, ERR_FRIEND_LIST_FULL))
    Expect(not filter(nil, nil, ERR_FRIEND_ADDED_S:format("Bob")))
    Expect(not filter(nil, nil, "Server shutdown in 15 minutes."))
    -- A slow server can confirm the add any time before the lookup times out.
    Advance(4)
    Expect(filter(nil, nil, ERR_FRIEND_ADDED_S:format("Alice")))
    Resolve("Alice", "Player-A", 90)
    Expect(filter(nil, nil, ERR_FRIEND_REMOVED_S:format("Alice")))
    Advance(3)
    Expect(not filter(nil, nil, ERR_FRIEND_ADDED_S:format("Alice")))
    Expect(not filter(nil, nil, ERR_FRIEND_REMOVED_S:format("Alice")))
    Expect(not filter(nil, nil, ERR_FRIEND_NOT_FOUND))
end)

Test("manual outgoing whispers remain visible and establish contacts", function()
    LeaveMeBeDB.allowByLevel = false
    Whisper("Blocked", "Player-B")
    Expect(not FILTERS.CHAT_MSG_WHISPER_INFORM(nil, nil, "hello", "Carol"))
    Emit("CHAT_MSG_WHISPER_INFORM", "hello", "Carol")
    Expect(LMB:EvaluateWhisper("Carol", "Player-C", "") == "allow")
    Expect(FILTERS.CHAT_MSG_WHISPER_INFORM(nil, nil, SENT[1].message))
    Emit("CHAT_MSG_WHISPER_INFORM", SENT[1].message, "Blocked")
    Expect(LMB:EvaluateWhisper("Blocked", "Player-B", "") == "block")
end)

Test("contacts match only the character's realm", function()
    LeaveMeBeDB.allowByLevel = false
    Emit("CHAT_MSG_WHISPER_INFORM", "hello", "Alice")
    Expect(LMB:EvaluateWhisper("Alice", "Player-A", "") == "allow")
    Expect(LMB:EvaluateWhisper("Alice-HomeRealm", "Player-A", "") == "allow")
    Expect(LMB:EvaluateWhisper("Alice-FarRealm", "Player-B", "") == "block")
    Emit("CHAT_MSG_WHISPER_INFORM", "hello", "Bob-ConnectedRealm")
    Expect(LMB:EvaluateWhisper("Bob-ConnectedRealm", "Player-C", "") == "allow")
    Expect(LMB:EvaluateWhisper("Bob", "Player-D", "") == "block")
end)

Test("explicit lists retain case, spacing, realm, and legacy-value rules", function()
    local list = {}
    LMB:SetListed(list, "A lIcE-Home Realm", true)
    Expect(LMB:IsNameListed(list, "Alice"))
    Expect(not LMB:IsNameListed(list, "Alice-FarRealm"))
    list.bob = true
    Expect(LMB:IsNameListed(list, "Bob-FarRealm"))
    list.carol = false
    Expect(LMB:IsNameListed(list, "Carol"))
end)

Test("blocklist, staff exceptions, reply prefix, and cooldown survive", function()
    LeaveMeBeDB.blockAllWhispers = false
    LMB:SetListed(LeaveMeBeDB.blocklist, "Alice", true)
    Expect(LMB:EvaluateWhisper("Alice", "Player-A", "GM") == "allow")
    Expect(LMB:EvaluateWhisper("Alice", "Player-A", "DEV") == "allow")
    Whisper("Alice", "Player-A")
    Whisper("Alice-HomeRealm", "Player-A")
    Expect(#SENT == 1 and LMB:IsAutoReply(SENT[1].message))
    Advance(60)
    Whisper("Alice", "Player-A")
    Expect(#SENT == 2)
    Advance(60)
    Whisper("Alice", "Player-A", "Leave Me Be (Addon): unavailable")
    Expect(#SENT == 2)
end)

Test("logout preserves queued messages and cleans friends without replying", function()
    local original = { message = "older entry" }
    LeaveMeBeLog[1] = original
    Whisper("Alice", "Player-A", "first")
    Whisper("Alice", "Player-A", "second")
    FRIENDS = {{name = "Alice", guid = "Player-A", level = 0, notes = "LeaveMeBe:level-check"}}
    Advance(1)
    Emit("PLAYER_LOGOUT")
    Expect(#FRIENDS == 0 and #SENT == 0 and #LeaveMeBeLog == 3)
    Expect(LeaveMeBeLog[1] == original)
    Expect(LeaveMeBeLog[2].timestamp == 100010)
    Expect(LeaveMeBeLog[3].reason == "level-check-interrupted")
    Advance(10)
    Expect(#LeaveMeBeLog == 3 and #SENT == 0)
end)

Test("logout still preserves messages if friend APIs disappeared", function()
    Whisper("Alice", "Player-A")
    C_FriendList.GetNumFriends = function() return nil end
    Emit("PLAYER_LOGOUT")
    Expect(#LeaveMeBeLog == 1 and #SENT == 0)
end)

Test("late and orphaned temporary friends are cleaned up", function()
    Whisper("Alice", "Player-A")
    Advance(5)
    Resolve("Alice", "Player-A", 90)
    Expect(#FRIENDS == 0 and #LeaveMeBeLog == 1)
    FRIENDS = {{name = "Bob", guid = "Player-B", level = 90, notes = "LeaveMeBe:level-check"}}
    Emit("FRIENDLIST_UPDATE")
    Expect(#FRIENDS == 0)
end)

Test("blocked popouts close before the manager event finishes", function()
    MODE = "popout"
    LeaveMeBeDB.allowByLevel = false
    Whisper("Alice", "Player-A")
    Expect(#WINDOWS == 1 and not WINDOWS[1].inUse)
    Expect(#LeaveMeBeLog == 1 and #DISPLAYED == 0)
    Emit("CHAT_MSG_WHISPER_INFORM", SENT[1].message, "Alice")
    Expect(not WINDOWS[2].inUse and SELECTED_DOCK_FRAME == DEFAULT_CHAT_FRAME)
end)

Test("allowed level lookup restores the popout and replays once per frame", function()
    MODE = "popout_and_inline"
    Whisper("Alice", "Player-A")
    Expect(not WINDOWS[1].inUse and #DISPLAYED == 0)
    Resolve("Alice", "Player-A", 90)
    Expect(#WINDOWS == 2 and WINDOWS[2].inUse)
    Expect(#WINDOWS[2].messages == 1 and #CHAT.messages == 1)
    Advance(1)
    Expect(WINDOWS[2].inUse)
end)

Test("replay uses an existing dedicated window instead of opening another", function()
    MODE = "popout"
    LeaveMeBeDB.allowContacts = false
    Emit("CHAT_MSG_WHISPER_INFORM", "hello", "Alice")
    Expect(#WINDOWS == 1 and WINDOWS[1].inUse and #WINDOWS[1].messages == 1)
    Whisper("Alice", "Player-A")
    -- Only the outgoing echo has been shown so far.
    Expect(#WINDOWS == 1 and WINDOWS[1].inUse and #DISPLAYED == 1)
    Resolve("Alice", "Player-A", 90)
    Expect(#WINDOWS == 1 and WINDOWS[1].inUse and #WINDOWS[1].messages == 2)
    Expect(#CLOSED_WINDOWS == 0)
end)

Test("existing conversation tabs and manual popouts stay open", function()
    MODE = "popout"
    LeaveMeBeDB.allowByLevel = false
    Emit("CHAT_MSG_WHISPER_INFORM", "hello", "Alice")
    Expect(WINDOWS[1].inUse)
    LMB:SetListed(LeaveMeBeDB.blocklist, "Alice", true)
    Whisper("Alice", "Player-A")
    Expect(WINDOWS[1].inUse)
    local manual = FCF_OpenTemporaryWindow("WHISPER", "Bob")
    Advance(0)
    Whisper("Bob", "Player-B")
    Expect(manual.inUse)
end)

Test("secret chat is untouched by filters, contacts, and window hooks", function()
    MODE = "popout"
    local secret = "secret sender"
    SECRETS[secret] = true
    Whisper(secret, "Player-A", secret)
    Emit("CHAT_MSG_WHISPER_INFORM", secret, secret)
    Expect(#LeaveMeBeLog == 0 and #ADDS == 0 and #SENT == 0)
    Expect(next(LMB.sessionContacts) == nil and #CLOSED_WINDOWS == 0)
    Expect(not FILTERS.CHAT_MSG_SYSTEM(nil, nil, secret))
end)

Test("automation waits for a stable listing and respects its 15-second grace", function()
    LeaveMeBeDB.blockAllWhispers = false
    LISTED = true
    LMB:SetPremadeAutomationEnabled(true)
    Expect(not LeaveMeBeDB.blockAllWhispers)
    Advance(1)
    Expect(LeaveMeBeDB.blockAllWhispers and LeaveMeBeDB.premadeAutomationOwnsBlock)
    LISTED = false
    Emit("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    Advance(14)
    Expect(LeaveMeBeDB.blockAllWhispers)
    Advance(1)
    Expect(not LeaveMeBeDB.blockAllWhispers)
end)

Test("relisting cancels the disable and turning automation off hands back control", function()
    LeaveMeBeDB.blockAllWhispers = false
    LISTED = true
    LMB:SetPremadeAutomationEnabled(true)
    Advance(1)
    LISTED = false
    Emit("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    Advance(10)
    LISTED = true
    Emit("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    Advance(10)
    Expect(LeaveMeBeDB.blockAllWhispers)
    LMB:SetPremadeAutomationEnabled(false)
    Expect(not LeaveMeBeDB.blockAllWhispers)
end)

Test("automation preserves manual blocking and requires home-group leadership", function()
    LISTED = true
    LMB:SetPremadeAutomationEnabled(true)
    LMB:SetPremadeAutomationEnabled(false)
    Expect(LeaveMeBeDB.blockAllWhispers)
    LMB:SetBlockAllWhispers(false)
    GROUPED = true
    LEADER = false
    LMB:SetPremadeAutomationEnabled(true)
    Expect(not LeaveMeBeDB.blockAllWhispers)
    LEADER = true
    Emit("PARTY_LEADER_CHANGED")
    Advance(1)
    Expect(LeaveMeBeDB.blockAllWhispers)
    LMB:SetBlockAllWhispers(true)
    LISTED = false
    Emit("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    Advance(20)
    Expect(LeaveMeBeDB.blockAllWhispers)
end)

Test("accepting an invite does not mistake the listed group for a solo listing", function()
    LeaveMeBeDB.blockAllWhispers = false
    LMB:SetPremadeAutomationEnabled(true)
    -- The listing update arrives before the group roster, across frames.
    LISTED = true
    Emit("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    Advance(0.25)
    Expect(not LeaveMeBeDB.blockAllWhispers)
    GROUPED = true
    LEADER = false
    Emit("GROUP_ROSTER_UPDATE")
    Advance(2)
    Expect(not LeaveMeBeDB.blockAllWhispers)
    Expect(not LeaveMeBeDB.premadeAutomationOwnsBlock)
end)

Test("a transient solo listing disappears without enabling blocking", function()
    LeaveMeBeDB.blockAllWhispers = false
    LISTED = true
    LMB:SetPremadeAutomationEnabled(true)
    Advance(0.25)
    LISTED = false
    Emit("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    Advance(2)
    Expect(not LeaveMeBeDB.blockAllWhispers)
end)

Test("turning automation off cancels a pending enable", function()
    LeaveMeBeDB.blockAllWhispers = false
    LISTED = true
    LMB:SetPremadeAutomationEnabled(true)
    Advance(0.25)
    LMB:SetPremadeAutomationEnabled(false)
    Advance(2)
    Expect(not LeaveMeBeDB.blockAllWhispers)
end)

print(("%d regression tests passed"):format(passed))
