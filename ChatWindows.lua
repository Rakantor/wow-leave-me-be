local _, LMB = ...

local newWindows = {}

-- Blizzard opens popouts before applying message filters. Track newly opened
-- windows and close empty, filtered ones in the manager's post-hook, before
-- the next render. Keep the original handler intact for secret chat payloads.
local function TrackWindow(frame, chatType, target)
    if LMB:IsSecretValue(chatType) or chatType ~= "WHISPER" then
        return
    end
    local key = LMB:GetCharacterKey(target)
    if not key then
        return
    end
    local record = { key = key, previousSelection = SELECTED_DOCK_FRAME }
    newWindows[frame] = record
    C_Timer.After(0, function()
        if newWindows[frame] == record then
            newWindows[frame] = nil
        end
    end)
end

local function AfterChatEvent(_, event, ...)
    if event ~= "CHAT_MSG_WHISPER" and event ~= "CHAT_MSG_WHISPER_INFORM" then
        return
    end
    local message, sender, _, _, _, flags, _, _, _, _, _, guid = ...
    if LMB:IsSecretValue(message) or LMB:IsSecretValue(sender) then
        return
    end
    local key = LMB:GetCharacterKey(sender)
    if not key then
        return
    end
    local filtered
    if event == "CHAT_MSG_WHISPER" then
        filtered = LMB:ShouldBlockWhisper(sender, guid, flags)
    else
        filtered = LMB:IsAutoReply(message)
    end
    for frame, record in pairs(newWindows) do
        if record.key == key then
            newWindows[frame] = nil
            if filtered and not frame:IsForbidden()
                and frame:GetNumMessages() == 0
            then
                local restoreSelection = SELECTED_DOCK_FRAME == frame
                FCF_Close(frame)
                local previous = record.previousSelection
                if restoreSelection and previous and previous ~= frame
                    and not previous:IsForbidden()
                then
                    FCF_SelectDockFrame(previous)
                end
            end
        end
    end
end

function LMB:PrepareWhisperWindow(sender)
    if not FCF_OpenTemporaryWindow or not FCFManager_GetNumDedicatedFrames then
        return
    end
    local mode = GetCVar("whisperMode")
    if (mode == "popout" or mode == "popout_and_inline")
        and FCFManager_GetNumDedicatedFrames("WHISPER", sender) == 0
    then
        -- The original popout was closed while the level was unknown. Open a
        -- replacement now; ReplayWhisper will deliver the message exactly once.
        FCF_OpenTemporaryWindow("WHISPER", sender)
    end
end

function LMB:RegisterWhisperWindows()
    if not FloatingChatFrameManager or not FCF_SetTemporaryWindowType
        or not FCF_Close or not FCF_SelectDockFrame
    then
        return
    end
    hooksecurefunc("FCF_SetTemporaryWindowType", TrackWindow)
    FloatingChatFrameManager:HookScript("OnEvent", AfterChatEvent)
end
