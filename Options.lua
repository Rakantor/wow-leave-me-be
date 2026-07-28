local _, LMB = ...

local function CreateTitle(panel, text)
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(text)
    return title
end

local function CreateDescription(panel, anchor, text)
    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    description:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    description:SetWidth(620)
    description:SetJustifyH("LEFT")
    description:SetText(text)
    return description
end

local function CreateCheckbox(panel, key, label, description, y, onChanged)
    local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", 16, y)
    checkbox:SetSize(26, 26)

    local labelText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    labelText:SetPoint("LEFT", checkbox, "RIGHT", 4, 1)
    labelText:SetText(label)

    local descriptionText = panel:CreateFontString(
        nil,
        "ARTWORK",
        "GameFontHighlightSmall"
    )
    descriptionText:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 0, -3)
    descriptionText:SetWidth(560)
    descriptionText:SetJustifyH("LEFT")
    descriptionText:SetText(description)

    checkbox:SetHitRectInsets(0, -240, 0, 0)
    checkbox:SetScript("OnClick", function(button)
        local checked = button:GetChecked() == true
        if onChanged then
            onChanged(checked)
        else
            LeaveMeBeDB[key] = checked
        end
    end)

    checkbox.labelText = labelText
    checkbox.descriptionText = descriptionText
    return checkbox
end

local function CreateMainPanel()
    local panel = CreateFrame("Frame")
    local title = CreateTitle(panel, "Leave Me Be")
    local intro = CreateDescription(
        panel,
        title,
        "Silently filter player whispers, save them to the log, and send an automatic reply."
    )

    local blockAll = CreateCheckbox(
        panel,
        "blockAllWhispers",
        "Block all whispers",
        "Block everyone except players allowed by the rules below or the allowlist.",
        -70,
        function(checked)
            LMB:SetBlockAllWhispers(checked)
        end
    )

    local autoBlockPremadeListing = CreateCheckbox(
        panel,
        "autoBlockPremadeListing",
        "Automatically block while listed in Premade Group Finder",
        "Turn blocking on while you own an active group listing, then turn it off shortly after the listing ends.",
        -125,
        function(checked)
            LMB:SetPremadeAutomationEnabled(checked)
        end
    )

    local exceptionsTitle = panel:CreateFontString(
        nil,
        "ARTWORK",
        "GameFontNormalMed2"
    )
    exceptionsTitle:SetPoint("TOPLEFT", 16, -180)
    exceptionsTitle:SetText("Allow these players when blocking all whispers")

    local allowByLevel = CreateCheckbox(
        panel,
        "allowByLevel",
        "Allow players at or above level",
        "Temporarily checks unknown players and allows them at this minimum level.",
        -210
    )
    allowByLevel:SetHitRectInsets(0, -205, 0, 0)
    allowByLevel.descriptionText:ClearAllPoints()
    allowByLevel.descriptionText:SetPoint(
        "TOPLEFT",
        allowByLevel.labelText,
        "BOTTOMLEFT",
        0,
        -8
    )

    local levelEditBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    levelEditBox:SetPoint(
        "LEFT",
        allowByLevel.labelText,
        "RIGHT",
        10,
        0
    )
    levelEditBox:SetSize(45, 24)
    levelEditBox:SetAutoFocus(false)
    levelEditBox:SetNumeric(true)
    levelEditBox:SetMaxLetters(3)
    levelEditBox:SetFontObject(ChatFontNormal)
    levelEditBox:SetJustifyH("CENTER")

    local allowFriends = CreateCheckbox(
        panel,
        "allowFriends",
        "Allow friends",
        "Always receive whispers from character friends and Battle.net friends.",
        -260
    )
    local allowGuild = CreateCheckbox(
        panel,
        "allowGuild",
        "Allow guild members",
        "Always receive whispers from members of your guild.",
        -310
    )
    local allowGroup = CreateCheckbox(
        panel,
        "allowGroup",
        "Allow group members",
        "Always receive whispers from members of your current party or raid.",
        -360
    )
    local allowContacts = CreateCheckbox(
        panel,
        "allowContacts",
        "Allow people you whisper",
        "Allow replies from people you whispered during this login session.",
        -410
    )

    local replyTitle = panel:CreateFontString(
        nil,
        "ARTWORK",
        "GameFontNormalMed2"
    )
    replyTitle:SetPoint("TOPLEFT", 16, -465)
    replyTitle:SetText("Automatic reply")

    local replyDescription = panel:CreateFontString(
        nil,
        "ARTWORK",
        "GameFontHighlightSmall"
    )
    replyDescription:SetPoint("TOPLEFT", replyTitle, "BOTTOMLEFT", 0, -7)
    replyDescription:SetWidth(620)
    replyDescription:SetJustifyH("LEFT")
    replyDescription:SetText(
        "Every reply begins with the fixed prefix \""
            .. LMB.autoReplyPrefix
            .. "\". Customize the text that follows it."
    )

    local prefix = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    prefix:SetPoint("TOPLEFT", replyDescription, "BOTTOMLEFT", 0, -15)
    prefix:SetText(LMB.autoReplyPrefix)

    local replyEditBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    replyEditBox:SetPoint("TOPLEFT", prefix, "BOTTOMLEFT", 4, -9)
    replyEditBox:SetSize(580, 30)
    replyEditBox:SetAutoFocus(false)
    replyEditBox:SetMaxLetters(200)
    replyEditBox:SetFontObject(ChatFontNormal)

    local function LoadMinimumLevel()
        local value = LeaveMeBeDB.minimumLevel or LMB.defaultMinimumLevel
        levelEditBox:SetText(tostring(value))
        levelEditBox:SetCursorPosition(0)
    end

    local function SaveMinimumLevel()
        local value = levelEditBox:GetNumber()
        if type(value) ~= "number" or value < 1 then
            value = LMB.defaultMinimumLevel
        end
        LeaveMeBeDB.minimumLevel = math.min(999, math.floor(value))
        LoadMinimumLevel()
    end

    levelEditBox:SetScript("OnEnterPressed", function(editBox)
        SaveMinimumLevel()
        editBox:ClearFocus()
    end)
    levelEditBox:SetScript("OnEscapePressed", function(editBox)
        LoadMinimumLevel()
        editBox:ClearFocus()
    end)
    levelEditBox:SetScript("OnEditFocusLost", SaveMinimumLevel)

    local function LoadReply()
        replyEditBox:SetText(LeaveMeBeDB.autoReplyMessage)
        replyEditBox:SetCursorPosition(0)
    end

    local function SaveReply()
        local value = replyEditBox:GetText()
        if LMB:IsSecretValue(value) then
            return
        end
        if value == "" then
            value = LMB.defaultAutoReplyMessage
        end
        LeaveMeBeDB.autoReplyMessage = value
        LoadReply()
    end

    replyEditBox:SetScript("OnEnterPressed", function(editBox)
        SaveReply()
        editBox:ClearFocus()
    end)
    replyEditBox:SetScript("OnEscapePressed", function(editBox)
        LoadReply()
        editBox:ClearFocus()
    end)
    replyEditBox:SetScript("OnEditFocusLost", SaveReply)

    local checkboxes = {
        blockAllWhispers = blockAll,
        autoBlockPremadeListing = autoBlockPremadeListing,
        allowByLevel = allowByLevel,
        allowFriends = allowFriends,
        allowGuild = allowGuild,
        allowGroup = allowGroup,
        allowContacts = allowContacts,
    }

    local function Refresh()
        for key, checkbox in pairs(checkboxes) do
            checkbox:SetChecked(LeaveMeBeDB[key])
        end
        LoadMinimumLevel()
        LoadReply()
    end

    panel:SetScript("OnShow", Refresh)
    LMB.RefreshMainOptions = Refresh
    Refresh()
    return panel
end

local function CreateListPanel(listKey, otherListKey, titleText, descriptionText)
    local panel = CreateFrame("Frame")
    local title = CreateTitle(panel, titleText)
    local description = CreateDescription(panel, title, descriptionText)

    local inputLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    inputLabel:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -20)
    inputLabel:SetText("Character name")

    local input = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", inputLabel, "BOTTOMLEFT", 4, -8)
    input:SetSize(330, 30)
    input:SetAutoFocus(false)
    input:SetMaxLetters(100)
    input:SetFontObject(ChatFontNormal)

    local addButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addButton:SetPoint("LEFT", input, "RIGHT", 12, 0)
    addButton:SetSize(90, 24)
    addButton:SetText("Add")

    local removeButton = CreateFrame(
        "Button",
        nil,
        panel,
        "UIPanelButtonTemplate"
    )
    removeButton:SetPoint("LEFT", addButton, "RIGHT", 8, 0)
    removeButton:SetSize(90, 24)
    removeButton:SetText("Remove")

    local status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -4, -7)
    status:SetWidth(550)
    status:SetJustifyH("LEFT")

    local listTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    listTitle:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -18)
    listTitle:SetText("Saved entries")

    local scrollFrame = CreateFrame(
        "ScrollFrame",
        nil,
        panel,
        "ScrollFrameTemplate"
    )
    scrollFrame:SetPoint("TOPLEFT", listTitle, "BOTTOMLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 18)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(560, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local emptyText = scrollChild:CreateFontString(
        nil,
        "ARTWORK",
        "GameFontDisable"
    )
    emptyText:SetPoint("TOPLEFT", 4, -6)
    emptyText:SetText("No entries.")

    local rows = {}

    local function Refresh()
        local entries = {}
        for name in pairs(LeaveMeBeDB[listKey]) do
            entries[#entries + 1] = name
        end
        table.sort(entries)

        emptyText:SetShown(#entries == 0)

        for index = 1, #entries do
            local row = rows[index]
            if not row then
                row = CreateFrame("Button", nil, scrollChild)
                row:SetSize(540, 24)
                row:SetPoint("TOPLEFT", 0, -((index - 1) * 24))

                row.text = row:CreateFontString(
                    nil,
                    "ARTWORK",
                    "GameFontHighlight"
                )
                row.text:SetPoint("LEFT", 4, 0)
                row.text:SetJustifyH("LEFT")

                row:SetScript("OnClick", function(button)
                    input:SetText(button.name)
                    input:SetCursorPosition(#button.name)
                end)
                row:SetScript("OnEnter", function(button)
                    button.text:SetTextColor(1, 0.82, 0)
                end)
                row:SetScript("OnLeave", function(button)
                    button.text:SetTextColor(1, 1, 1)
                end)
                rows[index] = row
            end

            row.name = entries[index]
            row.text:SetText(entries[index])
            row:Show()
        end

        for index = #entries + 1, #rows do
            rows[index]:Hide()
        end

        scrollChild:SetHeight(math.max(1, #entries * 24))
    end

    local function AddEntry()
        local name = input:GetText()
        if LMB:IsSecretValue(name) then
            status:SetText("That name cannot be accessed right now.")
            return
        end
        if not LMB:SetListed(LeaveMeBeDB[listKey], name, true) then
            status:SetText("Enter a character name first.")
            return
        end

        LMB:SetListed(LeaveMeBeDB[otherListKey], name, false)
        status:SetText(name .. " was added.")
        input:SetText("")
        Refresh()
    end

    local function RemoveEntry()
        local name = input:GetText()
        if LMB:IsSecretValue(name) then
            status:SetText("That name cannot be accessed right now.")
            return
        end
        if not LMB:SetListed(LeaveMeBeDB[listKey], name, false) then
            status:SetText("Enter or select a character name first.")
            return
        end

        status:SetText(name .. " was removed.")
        input:SetText("")
        Refresh()
    end

    addButton:SetScript("OnClick", AddEntry)
    removeButton:SetScript("OnClick", RemoveEntry)
    input:SetScript("OnEnterPressed", function(editBox)
        AddEntry()
        editBox:ClearFocus()
    end)
    input:SetScript("OnEscapePressed", function(editBox)
        editBox:SetText("")
        editBox:ClearFocus()
    end)
    panel:SetScript("OnShow", function()
        input:SetText("")
        status:SetText("")
        Refresh()
    end)

    Refresh()
    return panel
end

function LMB:RegisterOptions()
    local mainPanel = CreateMainPanel()
    local allowlistPanel = CreateListPanel(
        "allowlist",
        "blocklist",
        "Allowlist",
        "Players on this list are always allowed. Select an entry to remove it."
    )
    local blocklistPanel = CreateListPanel(
        "blocklist",
        "allowlist",
        "Blocklist",
        "Players on this list are always blocked. Select an entry to remove it."
    )

    local category = Settings.RegisterCanvasLayoutCategory(
        mainPanel,
        "Leave Me Be"
    )
    Settings.RegisterAddOnCategory(category)
    Settings.RegisterCanvasLayoutSubcategory(
        category,
        allowlistPanel,
        "Allowlist"
    )
    Settings.RegisterCanvasLayoutSubcategory(
        category,
        blocklistPanel,
        "Blocklist"
    )
    self.settingsCategoryID = category:GetID()
end
