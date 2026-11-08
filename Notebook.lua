-- Notebook: iOS-Notes-style notes, account-wide or character-specific.
-- Slash commands: /nb, /notebook

local DB, CDB          -- account-wide / per-character saved variables
local S                -- active settings table (account-wide, or this character's overrides)
local mainFrame, noteFrame, settingsFrame
local rows = {}
local currentId        -- id of the note open in noteFrame

local ROW_HEIGHT = 22
local BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
local INPUT_BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local SETTING_DEFAULTS = {
    defaultCharacterOnly = false,
    openOnLogin = false,
    listBorder = true,
    noteBorder = true,
    listOpacity = 1,
    noteOpacity = 1,
    noteSide = "RIGHT",
    strata = "MEDIUM",
}
local SETTING_KEYS = {}
for key in pairs(SETTING_DEFAULTS) do SETTING_KEYS[#SETTING_KEYS + 1] = key end

local function UseSettings()
    S = CDB.useCharSettings and CDB.settings or DB.settings
end

local function NewFrame(frameType, name, parent, template)
    -- Modern Classic clients need BackdropTemplate for SetBackdrop.
    if BackdropTemplateMixin and template == nil then
        template = "BackdropTemplate"
    end
    return CreateFrame(frameType, name, parent, template)
end

local STRATA = {
    { "BACKGROUND", "Background" },
    { "LOW", "Low" },
    { "MEDIUM", "Medium" },
    { "HIGH", "High" },
    { "DIALOG", "Dialog" },
    { "FULLSCREEN", "Fullscreen" },
    { "FULLSCREEN_DIALOG", "Fullscreen Dialog" },
    { "TOOLTIP", "Tooltip (always on top)" },
}
local FLAT_BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

local function StrataIndex()
    for i, s in ipairs(STRATA) do
        if s[1] == S.strata then return i end
    end
    return 3
end

-- Apply layer, border and opacity to a window. f.styleKey ("list" or "note")
-- selects its own border/opacity settings; windows without one (settings)
-- always get a border and full opacity.
local function ApplyStyle(f)
    if not f then return end
    local border, alpha = true, 1
    if f.styleKey then
        border, alpha = S[f.styleKey .. "Border"], S[f.styleKey .. "Opacity"]
    end
    f:SetFrameStrata(f.fixedStrata or S.strata)
    if border then
        f:SetBackdrop(BACKDROP)
        f:SetBackdropColor(1, 1, 1, alpha)
        f:SetBackdropBorderColor(1, 1, 1, alpha)
    else
        f:SetBackdrop(FLAT_BACKDROP)
        f:SetBackdropColor(0, 0, 0, alpha)
    end
    -- text boxes inside the window fade with it
    if f.inputBgs then
        for _, box in ipairs(f.inputBgs) do
            box:SetBackdropColor(0, 0, 0, 0.6 * alpha)
            box:SetBackdropBorderColor(1, 1, 1, alpha)
        end
    end
    -- scroll bars fade too
    if f.scrollFrames then
        for _, sf in ipairs(f.scrollFrames) do
            local bar = sf.ScrollBar or _G[sf:GetName() .. "ScrollBar"]
            if bar then bar:SetAlpha(alpha) end
        end
    end
end

local function ApplyAllStyles()
    ApplyStyle(mainFrame)
    ApplyStyle(noteFrame)
    ApplyStyle(settingsFrame)
end

-- Remember window positions and sizes (per character)
local function SavePosition(f, key)
    f:StopMovingOrSizing()
    local point, _, relPoint, x, y = f:GetPoint()
    CDB.pos[key] = { point, relPoint, x, y }
end

-- Returns true if a saved position was applied
local function RestorePosition(f, key)
    local p = CDB.pos[key]
    if not p then return false end
    f:ClearAllPoints()
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    return true
end

local function RestoreSize(f, key, defaultW, defaultH)
    local size = CDB.size[key]
    f:SetSize(size and size[1] or defaultW, size and size[2] or defaultH)
end

-- Adds a drag handle in the bottom-right corner and remembers the new size
local function MakeResizable(f, key, minW, minH)
    -- the only upper limit is the screen itself
    local maxW, maxH = UIParent:GetWidth(), UIParent:GetHeight()
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(minW, minH, maxW, maxH)
    else
        f:SetMinResize(minW, minH)
        f:SetMaxResize(maxW, maxH)
    end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -5, 5)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        SavePosition(f, key) -- also stops the sizing
        CDB.size[key] = { f:GetWidth(), f:GetHeight() }
    end)
    return grip
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

local function NewId()
    return time() .. "-" .. math.random(100000, 999999)
end

-- Returns note, store (the table that holds it), isCharacterOnly
local function FindNote(id)
    if DB.notes[id] then return DB.notes[id], DB.notes, false end
    if CDB.notes[id] then return CDB.notes[id], CDB.notes, true end
end

-- Notes are listed by `order` (ascending), which the user can rearrange.
-- New notes get an order above every existing one so they appear at the top.
local function TopOrder()
    local top = 1
    for _, store in ipairs({ DB.notes, CDB.notes }) do
        for _, n in pairs(store) do
            if n.order and n.order < top then top = n.order end
        end
    end
    return top - 1
end

local function CreateNote()
    local id = NewId()
    local store = S.defaultCharacterOnly and CDB.notes or DB.notes
    store[id] = { id = id, subject = "", text = "", modified = time(), order = TopOrder() }
    return id
end

-- Subject as displayed (links reduced to their [Name], colors removed)
local function PlainText(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    return text
end

local function SortedNotes()
    local list = {}
    for _, n in pairs(DB.notes) do list[#list + 1] = { note = n, char = false } end
    for _, n in pairs(CDB.notes) do list[#list + 1] = { note = n, char = true } end
    table.sort(list, function(a, b)
        if a.note.order ~= b.note.order then return a.note.order < b.note.order end
        return a.note.modified > b.note.modified
    end)
    return list
end

---------------------------------------------------------------------------
-- Note window
---------------------------------------------------------------------------

StaticPopupDialogs["NOTEBOOK_DELETE"] = {
    text = "Delete note \"%s\"?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        local _, store = FindNote(data)
        if store then store[data] = nil end
        if currentId == data then
            currentId = nil
            noteFrame:Hide()
        end
        Notebook_Refresh()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function SaveCurrent()
    if not currentId then return end
    local note = FindNote(currentId)
    if not note then return end
    note.subject = noteFrame.subject:GetText()
    note.text = noteFrame.body:GetText()
    note.modified = time()
    Notebook_Refresh()
end

-- A sticky note ignores Escape: take the window out of UISpecialFrames while one is shown
local function UpdateEscapeClose()
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == "NotebookNoteFrame" then table.remove(UISpecialFrames, i) end
    end
    local note = currentId and FindNote(currentId)
    if not (note and note.sticky) then tinsert(UISpecialFrames, "NotebookNoteFrame") end
end

-- Remember (per character) that a sticky note is open, so it comes back after a reload/login
local function RememberStickyOpen()
    local note = currentId and FindNote(currentId)
    CDB.stickyOpen = (note and note.sticky) and currentId or nil
end

local function CreateNoteFrame()
    local f = NewFrame("Frame", "NotebookNoteFrame", UIParent)
    f.styleKey = "note"
    f.fixedStrata = "HIGH" -- the note always sits above the list, whatever the layer setting
    f:SetClampedToScreen(true)
    RestoreSize(f, "note", 320, 340)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) SavePosition(self, "note") end)
    ApplyStyle(f)
    f:Hide()
    MakeResizable(f, "note", 240, 220)
    tinsert(UISpecialFrames, "NotebookNoteFrame")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    -- Character-only toggle (top corner)
    local check = CreateFrame("CheckButton", "NotebookCharCheck", f, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", 16, -14)
    _G["NotebookCharCheckText"]:SetText("Character only")
    check:SetScript("OnClick", function(self)
        if not currentId then return end
        local note, store, isChar = FindNote(currentId)
        if not note then return end
        local wantChar = self:GetChecked() and true or false
        if wantChar ~= isChar then
            store[currentId] = nil
            local target = wantChar and CDB.notes or DB.notes
            target[currentId] = note
            Notebook_Refresh()
        end
    end)
    f.check = check

    -- Sticky: ignores Escape and reopens on this character if it was open
    local sticky = CreateFrame("CheckButton", "NotebookStickyCheck", f, "UICheckButtonTemplate")
    sticky:SetSize(24, 24)
    sticky:SetPoint("TOPLEFT", 136, -14)
    _G["NotebookStickyCheckText"]:SetText("Sticky")
    sticky:SetScript("OnClick", function(self)
        local note = currentId and FindNote(currentId)
        if not note then return end
        note.sticky = self:GetChecked() and true or nil
        UpdateEscapeClose()
        RememberStickyOpen()
    end)
    sticky:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sticky")
        GameTooltip:AddLine("Escape no longer closes this note, and it stays open when you close the list.", 1, 1, 1, true)
        GameTooltip:AddLine("If it was open, it reopens on a character after a /reload or relog.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    sticky:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.sticky = sticky

    -- Subject
    local subject = NewFrame("EditBox", nil, f)
    subject:SetBackdrop(INPUT_BACKDROP)
    subject:SetFontObject("GameFontNormalLarge")
    subject:SetAutoFocus(false)
    subject:SetMaxLetters(300)
    subject:SetTextInsets(6, 6, 0, 0)
    subject:SetPoint("TOPLEFT", 18, -46)
    subject:SetPoint("TOPRIGHT", -18, -46)
    subject:SetHeight(28)
    subject:SetScript("OnTextChanged", function(self, userInput) if userInput then SaveCurrent() end end)
    subject:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    subject:SetScript("OnEnterPressed", function(self) f.EditBody() end)
    subject:SetScript("OnTabPressed", function(self) f.EditBody() end)
    f.subject = subject

    -- Body, inside a scroll frame
    local scroll = CreateFrame("ScrollFrame", "NotebookBodyScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", subject, "BOTTOMLEFT", 2, -8)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -36, 48)

    local bg = NewFrame("Frame", nil, f)
    bg:SetBackdrop(INPUT_BACKDROP)
    bg:SetPoint("TOPLEFT", scroll, "TOPLEFT", -4, 4)
    bg:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 4, -4)
    bg:SetFrameLevel(scroll:GetFrameLevel() - 1)

    local body = CreateFrame("EditBox", nil, scroll)
    body:SetMultiLine(true)
    body:SetFontObject("ChatFontNormal")
    body:SetAutoFocus(false)
    body:SetWidth(250)
    body:SetTextInsets(2, 2, 2, 2)
    body:SetScript("OnTextChanged", function(self, userInput) if userInput then SaveCurrent() end end)
    body:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    body:SetScript("OnCursorChanged", function(self, x, y, w, h)
        -- keep the cursor visible while typing
        y = -y
        local offset = scroll:GetVerticalScroll()
        local height = scroll:GetHeight()
        if y < offset then
            scroll:SetVerticalScroll(y)
        elseif y + h > offset + height then
            scroll:SetVerticalScroll(y + h - height)
        end
    end)
    scroll:SetScrollChild(body)
    f.body = body

    -- EditBoxes show item/quest links but can't show tooltips for them. So when
    -- a field isn't being edited and contains a link, a read-only SimpleHTML
    -- "view" takes over (hover = tooltip, click = link action, click empty
    -- space = back to editing).
    local function ToHTML(text)
        text = text:gsub("&", "&amp;")
        text = text:gsub("<", "&lt;")
        text = text:gsub(">", "&gt;")
        text = text:gsub("\n", "<br/>")
        return "<html><body><p>" .. text .. "</p></body></html>"
    end

    local function MakeView(parent, fontObject, onEdit)
        local v = CreateFrame("SimpleHTML", nil, parent)
        v:SetFontObject("p", fontObject)
        if v.SetHyperlinksEnabled then v:SetHyperlinksEnabled(true) end
        v:EnableMouse(true)
        v:SetScript("OnHyperlinkEnter", function(self, link)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
                GameTooltip:Show()
            else
                GameTooltip:Hide()
            end
        end)
        v:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
        v:SetScript("OnHyperlinkClick", function(self, link, text, button)
            self.linkClicked = true
            SetItemRef(link, text, button)
        end)
        v:SetScript("OnHide", function() GameTooltip:Hide() end)
        -- a click on a link also reaches OnMouseUp; only plain clicks start editing
        v:SetScript("OnMouseUp", function(self)
            local function go()
                if self.linkClicked then self.linkClicked = false else onEdit() end
            end
            if C_Timer then C_Timer.After(0, go) else go() end
        end)
        v:Hide()
        return v
    end

    local function HasLink(text) return text:find("|H", 1, true) ~= nil end

    local bodyView, subjectView
    function f.EditBody()
        bodyView:Hide()
        body:Show()
        scroll:SetScrollChild(body)
        body:SetFocus()
        body:SetCursorPosition(body:GetNumLetters())
    end
    local sr, sg, sb = subject:GetTextColor()
    function f.EditSubject()
        subjectView:Hide()
        subject:SetTextColor(sr, sg, sb, 1)
        subject:SetFocus()
        subject:SetCursorPosition(subject:GetNumLetters())
    end

    bodyView = MakeView(scroll, ChatFontNormal, function() f.EditBody() end)
    subjectView = MakeView(f, GameFontNormalLarge, function() f.EditSubject() end)
    subjectView:SetPoint("TOPLEFT", subject, "TOPLEFT", 6, -6)
    subjectView:SetPoint("BOTTOMRIGHT", subject, "BOTTOMRIGHT", -6, 4)
    subjectView:SetFrameLevel(subject:GetFrameLevel() + 2)

    local function UpdateBodyView()
        local text = body:GetText()
        if HasLink(text) then
            bodyView:SetWidth(scroll:GetWidth())
            bodyView:SetText(ToHTML(text))
            bodyView:SetHeight(math.max(bodyView:GetContentHeight() + 4, scroll:GetHeight()))
            scroll:SetScrollChild(bodyView)
            bodyView:Show()
            body:Hide()
        else
            bodyView:Hide()
            body:Show()
            scroll:SetScrollChild(body)
        end
    end
    local function UpdateSubjectView()
        local text = subject:GetText()
        if HasLink(text) then
            subjectView:SetText(ToHTML(text))
            subjectView:Show()
            subject:SetTextColor(sr, sg, sb, 0) -- hide the editbox's own copy
        else
            subjectView:Hide()
            subject:SetTextColor(sr, sg, sb, 1)
        end
    end
    function f.UpdateViews()
        UpdateBodyView()
        UpdateSubjectView()
    end
    f.bodyView, f.subjectView = bodyView, subjectView

    -- Track which field has focus (shift-click link insertion targets it)
    for _, box in ipairs({ subject, body }) do
        box:SetScript("OnEditFocusGained", function(self) f.focused = self end)
        box:SetScript("OnEditFocusLost", function(self)
            if f.focused == self then f.focused = nil end
            if self == body then UpdateBodyView() else UpdateSubjectView() end
        end)
    end

    scroll:SetScript("OnSizeChanged", function(self, w, h)
        body:SetWidth(w)
        body:SetHeight(h)
        if bodyView:IsShown() then UpdateBodyView() end
    end)
    -- clicking empty space below the text focuses the body
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() f.EditBody() end)
    f.inputBgs = { subject, bg }
    f.scrollFrames = { scroll }
    ApplyStyle(f)

    -- Delete
    local del = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    del:SetSize(90, 24)
    del:SetPoint("BOTTOMLEFT", 18, 16)
    del:SetText("Delete")
    del:SetScript("OnClick", function()
        if not currentId then return end
        local note = FindNote(currentId)
        local name = (note and note.subject ~= "" and note.subject) or "Untitled"
        StaticPopup_Show("NOTEBOOK_DELETE", name, nil, currentId)
    end)

    -- Drop notes that were never filled in (like iOS Notes)
    f:SetScript("OnHide", function()
        CDB.stickyOpen = nil
        if currentId then
            local note, store = FindNote(currentId)
            if note and note.subject == "" and note.text == "" then
                store[currentId] = nil
            end
            currentId = nil
            Notebook_Refresh()
        end
    end)

    return f
end

local NOTE_SIDES = {
    { "RIGHT", "Right" },
    { "LEFT", "Left" },
    { "ABOVE", "Above" },
    { "BELOW", "Below" },
}

-- Default spot for the note window: beside the list window on the chosen
-- side, or screen center if the list isn't showing.
local function PlaceNote()
    noteFrame:ClearAllPoints()
    if not (mainFrame and mainFrame:IsShown()) then
        noteFrame:SetPoint("CENTER")
        return
    end
    local side = S.noteSide
    if side == "LEFT" then
        noteFrame:SetPoint("TOPRIGHT", mainFrame, "TOPLEFT", 0, 0)
    elseif side == "ABOVE" then
        noteFrame:SetPoint("BOTTOMLEFT", mainFrame, "TOPLEFT", 0, 0)
    elseif side == "BELOW" then
        noteFrame:SetPoint("TOPLEFT", mainFrame, "BOTTOMLEFT", 0, 0)
    else
        noteFrame:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 0, 0)
    end
end

local function OpenNote(id)
    if not noteFrame then noteFrame = CreateNoteFrame() end
    -- Switching notes: let OnHide-style cleanup run for the old one
    if currentId and currentId ~= id then
        local old, store = FindNote(currentId)
        if old and old.subject == "" and old.text == "" then store[currentId] = nil end
    end
    local note, _, isChar = FindNote(id)
    if not note then return end
    currentId = id
    noteFrame.subject:ClearFocus()
    noteFrame.body:ClearFocus()
    noteFrame.subject:SetText(note.subject)
    noteFrame.body:SetText(note.text)
    noteFrame.UpdateViews()
    noteFrame.check:SetChecked(isChar)
    noteFrame.sticky:SetChecked(note.sticky)
    UpdateEscapeClose()
    RememberStickyOpen()
    -- A position the user dragged the note to wins over the default side
    if not noteFrame:IsShown() and not RestorePosition(noteFrame, "note") then
        PlaceNote()
    end
    noteFrame:Show()
    if note.subject == "" then noteFrame.subject:SetFocus() end
    Notebook_Refresh()
end

---------------------------------------------------------------------------
-- Main (list) window
---------------------------------------------------------------------------

-- Drag-and-drop reordering (only while the list is unlocked and not filtered)
local dragRow, dropSlot
local dragWatcher = CreateFrame("Frame")

-- Which gap (0 = above the first row ... n = below the last) the cursor is over
local function DropSlotAtCursor()
    local content = mainFrame.content
    local cursorY = select(2, GetCursorPosition()) / content:GetEffectiveScale()
    local slot = math.floor((content:GetTop() - cursorY) / ROW_HEIGHT + 0.5)
    return math.max(0, math.min(mainFrame.rowCount, slot))
end

local function StopRowDrag(row)
    if row ~= dragRow then return end
    dragWatcher:SetScript("OnUpdate", nil)
    mainFrame.dropLine:Hide()
    row:SetAlpha(1)
    dragRow = nil

    -- remove the dragged note and re-insert it at the drop slot
    local entries = SortedNotes()
    local from
    for i, entry in ipairs(entries) do
        if entry.note.id == row.noteId then from = i end
    end
    if from and dropSlot then
        local moved = table.remove(entries, from)
        local to = dropSlot >= from and dropSlot or dropSlot + 1
        table.insert(entries, to, moved)
        for i, entry in ipairs(entries) do entry.note.order = i end
    end
    dropSlot = nil
    -- a drag also ends in a click on the row; ignore that one
    if C_Timer then
        C_Timer.After(0.1, function() row.wasDragged = false end)
    else
        row.wasDragged = false
    end
    Notebook_Refresh()
end

local function StartRowDrag(row)
    if CDB.listLocked or mainFrame.search:GetText() ~= "" then return end
    dragRow = row
    row.wasDragged = true
    row:SetAlpha(0.4)
    mainFrame.dropLine:Show()
    dragWatcher:SetScript("OnUpdate", function()
        dropSlot = DropSlotAtCursor()
        local line = mainFrame.dropLine
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", mainFrame.content, "TOPLEFT", 0, -dropSlot * ROW_HEIGHT + 1)
        line:SetPoint("TOPRIGHT", mainFrame.content, "TOPRIGHT", 0, -dropSlot * ROW_HEIGHT + 1)
    end)
end

function Notebook_Refresh()
    if not mainFrame or not mainFrame:IsShown() then return end
    local all = SortedNotes()
    local list = all
    local query = strlower(mainFrame.search:GetText())
    if query ~= "" then
        list = {}
        for _, entry in ipairs(all) do
            if strfind(strlower(PlainText(entry.note.subject)), query, 1, true) then
                list[#list + 1] = entry
            end
        end
    end
    local content = mainFrame.content

    for i, entry in ipairs(list) do
        local row = rows[i]
        if not row then
            row = CreateFrame("Button", nil, content)
            row:SetHeight(ROW_HEIGHT)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
            row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            row.text:SetPoint("LEFT", 4, 0)
            row.text:SetPoint("RIGHT", -34, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false) -- one line, long subjects end in "..."
            row.text:SetMaxLines(1)
            row.tag = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            row.tag:SetPoint("RIGHT", -2, 0)
            row:SetScript("OnClick", function(self)
                if self.wasDragged then return end
                OpenNote(self.noteId)
            end)
            row:RegisterForDrag("LeftButton")
            row:SetScript("OnDragStart", StartRowDrag)
            row:SetScript("OnDragStop", StopRowDrag)
            rows[i] = row
        end
        row.noteId = entry.note.id
        local s = entry.note.subject
        row.text:SetText(s ~= "" and s or "Untitled")
        row.tag:SetText(entry.char and "char" or "")
        row:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end

    content:SetHeight(math.max(#list * ROW_HEIGHT, 1))
    mainFrame.rowCount = #list
    mainFrame.empty:SetText(#all == 0 and "No notes yet" or "No matching notes")
    if #list == 0 then mainFrame.empty:Show() else mainFrame.empty:Hide() end
end

local function CreateMainFrame()
    local f = NewFrame("Frame", "NotebookMainFrame", UIParent)
    f.styleKey = "list"
    RestoreSize(f, "main", 260, 340)
    if not RestorePosition(f, "main") then f:SetPoint("CENTER", -200, 0) end
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not CDB.listLocked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self) SavePosition(self, "main") end)
    ApplyStyle(f)
    f:Hide()
    f.grip = MakeResizable(f, "main", 310, 200)

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetText("Notebook")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    local new = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    new:SetSize(50, 22)
    new:SetPoint("TOPRIGHT", -34, -15)
    new:SetText("New")
    new:SetScript("OnClick", function() OpenNote(CreateNote()) end)

    -- Lock the list's position and size (hides the resize grip, blocks dragging)
    local lock = CreateFrame("Button", nil, f)
    lock:SetSize(34, 34)
    lock:SetPoint("LEFT", title, "RIGHT", 6, 0)
    lock:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local function UpdateLock()
        local locked = CDB.listLocked
        lock:SetNormalTexture(locked and "Interface\\Buttons\\LockButton-Locked-Up"
                                      or "Interface\\Buttons\\LockButton-Unlocked-Up")
        if locked then f.grip:Hide() else f.grip:Show() end
    end
    lock:SetScript("OnClick", function(self)
        CDB.listLocked = not CDB.listLocked
        UpdateLock()
        if GameTooltip:GetOwner() == self then self:GetScript("OnEnter")(self) end
    end)
    lock:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(CDB.listLocked and "Unlock position, size and note order"
                                          or "Lock position, size and note order")
        GameTooltip:Show()
    end)
    lock:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.UpdateLock = UpdateLock

    -- Settings button, in the title row next to New
    local settings = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    settings:SetSize(66, 22)
    settings:SetPoint("TOPRIGHT", -88, -15)
    settings:SetText("Settings")
    settings:SetScript("OnClick", function() Notebook_ToggleSettings() end)

    -- Subject search
    local searchLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    searchLabel:SetPoint("TOPLEFT", 20, -52)
    searchLabel:SetText("Search:")

    local search = NewFrame("EditBox", nil, f)
    search:SetBackdrop(INPUT_BACKDROP)
    search:SetFontObject("ChatFontNormal")
    search:SetAutoFocus(false)
    search:SetTextInsets(6, 6, 0, 0)
    search:SetPoint("LEFT", searchLabel, "RIGHT", 6, 0)
    search:SetPoint("RIGHT", f, "RIGHT", -20, 0)
    search:SetHeight(22)
    search:SetScript("OnTextChanged", function() Notebook_Refresh() end)
    -- Esc clears the search first, then leaves the box
    search:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    f.search = search

    local scroll = CreateFrame("ScrollFrame", "NotebookListScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -76)
    scroll:SetPoint("BOTTOMRIGHT", -36, 36)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(200, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w) end)
    f.content = content
    f.rowCount = 0
    f.dropLine = content:CreateTexture(nil, "OVERLAY")
    f.dropLine:SetHeight(2)
    local setColor = f.dropLine.SetColorTexture or f.dropLine.SetTexture
    setColor(f.dropLine, 1, 0.82, 0, 1)
    f.dropLine:Hide()
    f.inputBgs = { search }
    f.scrollFrames = { scroll }
    ApplyStyle(f)

    f.empty = f:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    f.empty:SetPoint("CENTER", scroll, "CENTER")
    f.empty:SetText("No notes yet")

    f:SetScript("OnShow", function(self)
        CDB.listOpen = true
        self.UpdateLock()
        Notebook_Refresh()
    end)
    f:SetScript("OnHide", function() CDB.listOpen = false end)

    return f
end

local function CreateSettingsFrame()
    local f = NewFrame("Frame", "NotebookSettingsFrame", UIParent)
    f:SetSize(400, 470)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    f.fixedStrata = "DIALOG" -- settings never follow the layer setting
    ApplyStyle(f)
    tinsert(UISpecialFrames, "NotebookSettingsFrame")

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetText("Notebook Settings")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    local charCheck = CreateFrame("CheckButton", "NotebookSetCharSpecific", f, "UICheckButtonTemplate")
    charCheck:SetSize(24, 24)
    charCheck:SetPoint("TOPLEFT", 190, -15)
    _G["NotebookSetCharSpecificText"]:SetText("Character specific settings")
    charCheck:SetScript("OnClick", function(self)
        CDB.useCharSettings = self:GetChecked() and true or false
        UseSettings()
        ApplyAllStyles()
        f:Refresh()
    end)
    f.charCheck = charCheck

    f.checks = {}
    local function AddCheck(name, label, y, dbKey, onChange)
        local c = CreateFrame("CheckButton", name, f, "UICheckButtonTemplate")
        c:SetSize(24, 24)
        c:SetPoint("TOPLEFT", 18, y)
        _G[name .. "Text"]:SetText(label)
        c:SetScript("OnClick", function(self)
            S[dbKey] = self:GetChecked() and true or false
            if onChange then onChange() end
        end)
        c.dbKey = dbKey
        f.checks[#f.checks + 1] = c
    end

    local function AddHeader(text, y)
        local h = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        h:SetPoint("TOPLEFT", 20, y)
        h:SetText(text)
    end

    local function AddLabel(text, y)
        local l = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        l:SetPoint("TOPLEFT", 22, y)
        l:SetText(text)
    end

    -- "<  value  >" selector; onStep(delta) is called with -1 / +1.
    local function AddCycler(label, y, onStep)
        AddLabel(label, y)
        local prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        prev:SetSize(26, 22)
        prev:SetPoint("TOPLEFT", 22, y - 22)
        prev:SetText("<")
        prev:SetScript("OnClick", function() onStep(-1) end)
        local nextb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        nextb:SetSize(26, 22)
        nextb:SetPoint("TOPRIGHT", -22, y - 22)
        nextb:SetText(">")
        nextb:SetScript("OnClick", function() onStep(1) end)
        local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        text:SetPoint("RIGHT", nextb, "LEFT", -4, 0)
        return text
    end

    -- "-  [slider with %]  +" for an opacity setting (dbKey, e.g. "listOpacity")
    f.sliders = {}
    local function AddOpacity(sliderName, dbKey, y)
        AddLabel("Opacity", y)
        local function SetOpacity(v)
            S[dbKey] = math.min(1, math.max(0, math.floor(v * 20 + 0.5) / 20))
            ApplyAllStyles()
            f:Refresh()
        end

        local less = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        less:SetSize(26, 22)
        less:SetPoint("TOPLEFT", 22, y - 22)
        less:SetText("-")
        less:SetScript("OnClick", function() SetOpacity(S[dbKey] - 0.1) end)

        local more = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        more:SetSize(26, 22)
        more:SetPoint("TOPRIGHT", -22, y - 22)
        more:SetText("+")
        more:SetScript("OnClick", function() SetOpacity(S[dbKey] + 0.1) end)

        -- Slider with the percentage embedded in it
        local slider = NewFrame("Slider", sliderName, f)
        slider:SetOrientation("HORIZONTAL")
        slider:SetHeight(20)
        slider:SetPoint("LEFT", less, "RIGHT", 8, 0)
        slider:SetPoint("RIGHT", more, "LEFT", -8, 0)
        slider:SetBackdrop({
            bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 3, right = 3, top = 6, bottom = 6 },
        })
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        slider:SetMinMaxValues(0, 1)
        slider:SetValueStep(0.05)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        slider.text = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        slider.text:SetPoint("CENTER", 0, 0)
        slider.dbKey = dbKey
        slider:SetScript("OnValueChanged", function(self, value, userInput)
            if userInput then SetOpacity(value) end
        end)
        f.sliders[#f.sliders + 1] = slider
    end

    AddHeader("General", -50)
    AddCheck("NotebookSetCharDefault", "New notes are character-only", -68, "defaultCharacterOnly")
    AddCheck("NotebookSetLogin", "Open window on login", -94, "openOnLogin")
    f.layerText = AddCycler("Notes list layer", -126, function(delta)
        local i = StrataIndex() + delta
        if i < 1 or i > #STRATA then return end
        S.strata = STRATA[i][1]
        ApplyAllStyles()
        f:Refresh()
    end)

    local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 22, -176)
    hint:SetText("Higher layers appear over more other windows.")

    AddHeader("Notes list window", -206)
    AddCheck("NotebookSetListBorder", "Show border", -224, "listBorder", ApplyAllStyles)
    AddOpacity("NotebookListOpacitySlider", "listOpacity", -252)

    AddHeader("Note window", -308)
    AddCheck("NotebookSetNoteBorder", "Show border", -326, "noteBorder", ApplyAllStyles)
    AddOpacity("NotebookNoteOpacitySlider", "noteOpacity", -354)

    local function NoteSideIndex()
        for i, v in ipairs(NOTE_SIDES) do
            if v[1] == S.noteSide then return i end
        end
        return 1
    end
    f.sideText = AddCycler("Opens on this side of the list", -406, function(delta)
        local i = (NoteSideIndex() - 1 + delta) % #NOTE_SIDES + 1
        S.noteSide = NOTE_SIDES[i][1]
        -- Forget a dragged position so the new side takes effect, and move an open note now
        CDB.pos.note = nil
        if noteFrame and noteFrame:IsShown() then PlaceNote() end
        f:Refresh()
    end)

    function f:Refresh()
        self.charCheck:SetChecked(CDB.useCharSettings)
        for _, c in ipairs(self.checks) do c:SetChecked(S[c.dbKey]) end
        for _, sl in ipairs(self.sliders) do
            sl:SetValue(S[sl.dbKey])
            sl.text:SetText(math.floor(S[sl.dbKey] * 100 + 0.5) .. "%")
        end
        self.sideText:SetText(NOTE_SIDES[NoteSideIndex()][2])
        self.layerText:SetText(STRATA[StrataIndex()][2])
    end
    f:SetScript("OnShow", function(self) self:Refresh() end)

    return f
end

function Notebook_ToggleSettings()
    if not settingsFrame then settingsFrame = CreateSettingsFrame() end
    if settingsFrame:IsShown() then
        settingsFrame:Hide()
    else
        settingsFrame:Show()
        settingsFrame:Raise()
    end
end

local function Toggle()
    if not mainFrame then mainFrame = CreateMainFrame() end
    if mainFrame:IsShown() then
        mainFrame:Hide()
        local note = currentId and FindNote(currentId)
        if noteFrame and not (note and note.sticky) then noteFrame:Hide() end
    else
        mainFrame:Show()
    end
end

---------------------------------------------------------------------------
-- Shift-click links (items, quests, spells, ...) into the focused note field
---------------------------------------------------------------------------

-- Returns true if the link went into a note field
local debugLinks = false

local function Esc(text) return (tostring(text):gsub("|", "||")) end

local function InsertIntoNote(text)
    if debugLinks then
        local focused = noteFrame and noteFrame.focused
        print("Notebook debug: link insert called with", Esc(text),
            "| note shown:", tostring(noteFrame and noteFrame:IsShown()),
            "| focused field:", tostring(focused and focused:HasFocus()))
    end
    if not text or not noteFrame or not noteFrame:IsShown() then return false end
    local box = noteFrame.focused
    if not (box and box:HasFocus()) then return false end
    box:Insert(text)
    if debugLinks then print("Notebook debug: field now contains", Esc(box:GetText())) end
    SaveCurrent()
    -- Stop editing so the field switches to its link-aware view (tooltips and
    -- clicks); clicking the text resumes editing at the end.
    box:ClearFocus()
    if debugLinks then
        print("Notebook debug: after clearing focus -> body view shown:",
            tostring(noteFrame.bodyView:IsShown()), "| subject view shown:",
            tostring(noteFrame.subjectView:IsShown()),
            "| hyperlinks enabled:", tostring(noteFrame.bodyView.IsHyperlinksEnabled
                and noteFrame.bodyView:IsHyperlinksEnabled()))
    end
    return true
end

-- Wrap the game's link-insert function (rather than just hooking it) so it
-- reports the click as handled; otherwise shift-clicking a stack in your bags
-- would also pop up the split-stack dialog. Newer clients moved the function
-- onto ChatFrameUtil, so wrap whichever exist.
local function WrapInsertLink(owner, name)
    local original = owner and owner[name]
    if type(original) ~= "function" then return end
    owner[name] = function(text, ...)
        if InsertIntoNote(text) then return true end
        return original(text, ...)
    end
end
WrapInsertLink(_G, "ChatEdit_InsertLink")
WrapInsertLink(ChatFrameUtil, "InsertLink")

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

local init = CreateFrame("Frame")
init:RegisterEvent("ADDON_LOADED")
init:SetScript("OnEvent", function(self, event, name)
    if name ~= "Notebook" then return end
    NotebookDB = NotebookDB or {}
    NotebookCharDB = NotebookCharDB or {}
    DB, CDB = NotebookDB, NotebookCharDB
    DB.notes = DB.notes or {}
    CDB.notes = CDB.notes or {}
    CDB.size = CDB.size or {}
    -- Notes saved before manual ordering get an order: newest first, above existing ones
    do
        local legacy, lowest = {}, 1
        for _, store in ipairs({ DB.notes, CDB.notes }) do
            for _, n in pairs(store) do
                if n.order then lowest = math.min(lowest, n.order) else legacy[#legacy + 1] = n end
            end
        end
        table.sort(legacy, function(a, b) return a.modified > b.modified end)
        for i, n in ipairs(legacy) do n.order = lowest - #legacy + i - 1 end
    end
    -- Positions are per character; seed a new character from the old account-wide ones
    if not CDB.pos then
        CDB.pos = {}
        for key, p in pairs(DB.pos or {}) do CDB.pos[key] = { p[1], p[2], p[3], p[4] } end
    end
    DB.state = nil -- open windows are no longer restored
    -- Settings used to live directly on DB; move them into DB.settings
    DB.settings = DB.settings or {}
    local A = DB.settings
    for _, key in ipairs(SETTING_KEYS) do
        if DB[key] ~= nil then
            if A[key] == nil then A[key] = DB[key] end
            DB[key] = nil
        end
    end
    for key, default in pairs(SETTING_DEFAULTS) do
        if A[key] == nil then A[key] = default end
    end
    -- Character-specific settings override the account-wide ones key by key:
    -- anything not set for this character falls through to the account value.
    -- (The game keeps the two saved tables separate; this layering is ours.)
    CDB.settings = CDB.settings or {}
    setmetatable(CDB.settings, { __index = A })
    UseSettings()
    self:UnregisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
end)
init:HookScript("OnEvent", function(self, event, isInitialLogin, isReloadingUi)
    if event ~= "PLAYER_ENTERING_WORLD" then return end
    self:UnregisterEvent("PLAYER_ENTERING_WORLD") -- also fires on every zone change
    -- A real login honours "open on login"; a /reload restores the list's last state
    local openList
    if isReloadingUi then openList = CDB.listOpen else openList = S.openOnLogin end
    if openList then
        if not mainFrame then mainFrame = CreateMainFrame() end
        mainFrame:Show()
    end
    -- the one other thing that reopens: a sticky note that was open
    local stickyId = CDB.stickyOpen
    if stickyId then
        local note = FindNote(stickyId)
        if note and note.sticky then OpenNote(stickyId) else CDB.stickyOpen = nil end
    end
end)

SLASH_NOTEBOOK1 = "/nb"
SLASH_NOTEBOOK2 = "/notebook"
local function SetListLocked(locked)
    if not mainFrame then mainFrame = CreateMainFrame() end
    CDB.listLocked = locked
    mainFrame.UpdateLock()
    print("|cff33ff99Notebook|r list " .. (locked and "locked" or "unlocked"))
end

local function PrintHelp()
    print("|cff33ff99Notebook|r commands:")
    print("  /nb or /nb toggle - show or hide the notes list")
    print("  /nb settings (or config, options) - open the settings window")
    print("  /nb lock, /nb unlock - lock or unlock the list's position, size and note order")
    print("  /nb debug - toggle link-insert debug output")
    print("  /nb help - show this list")
end

SlashCmdList["NOTEBOOK"] = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "" or msg == "toggle" then
        Toggle()
    elseif msg == "settings" or msg == "config" or msg == "options" then
        Notebook_ToggleSettings()
    elseif msg == "lock" then
        SetListLocked(true)
    elseif msg == "unlock" then
        SetListLocked(false)
    elseif msg == "debug" then
        debugLinks = not debugLinks
        print("Notebook link debug " .. (debugLinks and "on" or "off"))
    else
        PrintHelp() -- "help" or anything unrecognized
    end
end
