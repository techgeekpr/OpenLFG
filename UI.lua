--[[ OpenLFG -- UI.lua  (v2, Classic-LFG style)
     Left pane : role checkboxes (Tank/Healer/DPS) + scrollable dungeon list
                 with checkboxes + "Set LFG" / "Clear".
     Right pane: scrollable player board with role badges, dungeons, age.
                 Left-click row = whisper, Inv button = invite. ]]

local A = OpenLFG
local _G = A._G

local FRAME_W, FRAME_H = 660, 520
local LEFT_W           = 236
local DROW_H, DROWS    = 18, 15    -- dungeon list
local PROW_H, PROWS    = 30, 13    -- player list (2 lines per row, needs height)

local frame, dScroll, pScroll, dRows, pRows, filterBox, roleChecks

local BACKDROP = {
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local function ageText(secs)
    secs = secs or 0
    if secs < 60 then return _G.string.format("%ds", secs) end
    return _G.string.format("%dm", math.floor(secs / 60))
end

-- coloured full-name role tags (e.g. "Tank Heal") from a role string
local function roleBadges(roleStr)
    if not roleStr or roleStr == "" then return "" end
    local parts = {}
    for i = 1, _G.string.len(roleStr) do
        local r = _G.string.sub(roleStr, i, i)
        local c = A.ROLE_COLOR[r]
        if c and A.ROLE_NAME[r] then
            _G.table.insert(parts, _G.string.format("|cff%02x%02x%02x%s|r",
                c[1] * 255, c[2] * 255, c[3] * 255, A.ROLE_NAME[r]))
        end
    end
    return _G.table.concat(parts, " ")
end

-- ---------------------------------------------------------------------------
-- Dungeon list (left)
-- ---------------------------------------------------------------------------
local function makeDungeonRow(parent, i)
    local r = _G.CreateFrame("Frame", nil, parent)
    r:SetHeight(DROW_H)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -(96 + (i - 1) * DROW_H))
    r:SetWidth(LEFT_W - 28)

    r.check = _G.CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetWidth(18); r.check:SetHeight(18)
    r.check:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.check:SetScript("OnClick", function(self)
        local cb = self or _G.this
        if r.key then
            A.db.selfDungeons = A.db.selfDungeons or {}
            if cb:GetChecked() then A.db.selfDungeons[r.key] = true
            else A.db.selfDungeons[r.key] = nil end
            if A.db.matchMyDungeons then A.UI_Refresh() end
        end
    end)

    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.name:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
    r.name:SetJustifyH("LEFT"); r.name:SetWidth(140)

    r.lvl = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.lvl:SetPoint("RIGHT", r, "RIGHT", 0, 0); r.lvl:SetJustifyH("RIGHT"); r.lvl:SetWidth(42)
    return r
end

function A.UI_RefreshDungeons()
    if not frame or not frame:IsShown() then return end
    if A._busyD then return end                        -- guard against scroll re-entrancy
    A._busyD = true
    local order = A.DUNGEON_ORDER
    local total = A.tlen(order)
    _G.FauxScrollFrame_Update(dScroll, total, DROWS, DROW_H)
    local offset = _G.FauxScrollFrame_GetOffset(dScroll)

    for i = 1, DROWS do
        local row = dRows[i]
        local key = order[i + offset]
        if key then
            local info = A.DUNGEON_INFO[key]
            row.key = key
            row.name:SetText(info.name)
            if info.raid then
                row.lvl:SetText("raid")
            else
                row.lvl:SetText(info.min .. "-" .. info.max)
            end
            row.check:SetChecked(A.db.selfDungeons and A.db.selfDungeons[key] or false)
            row:Show()
        else
            row.key = nil
            row:Hide()
        end
    end
    A._busyD = false
end

-- ---------------------------------------------------------------------------
-- Player row (right)
-- ---------------------------------------------------------------------------
local function makePlayerRow(parent, i)
    local r = _G.CreateFrame("Button", nil, parent)
    r:SetHeight(PROW_H)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_W + 14, -(90 + (i - 1) * PROW_H))
    r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -52, -(90 + (i - 1) * PROW_H))   -- clear the scrollbar

    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    if hl.SetBlendMode then hl:SetBlendMode("ADD") end
    hl:SetAlpha(0.3)

    -- top-right: action button (Invite for solo LFG, Whisper for group LFM) + age
    r.act = _G.CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.act:SetWidth(56); r.act:SetHeight(18); r.act:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.act:SetText("Inv")

    r.age = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.age:SetPoint("RIGHT", r.act, "LEFT", -6, 0); r.age:SetWidth(34); r.age:SetJustifyH("RIGHT")

    -- top-left line: LFG/LFM tag + name + roles
    r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.tag:SetPoint("TOPLEFT", r, "TOPLEFT", 2, -1); r.tag:SetWidth(34); r.tag:SetJustifyH("LEFT")

    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.name:SetPoint("LEFT", r.tag, "RIGHT", 2, 0); r.name:SetWidth(122); r.name:SetJustifyH("LEFT")

    r.roles = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.roles:SetPoint("LEFT", r.name, "RIGHT", 4, 0)
    r.roles:SetPoint("RIGHT", r.age, "LEFT", -8, 0); r.roles:SetJustifyH("LEFT")   -- stop before age

    -- second line: dungeons (colored) + free-text note, as one string
    r.line2 = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.line2:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, 1)
    r.line2:SetPoint("RIGHT", r.age, "LEFT", -8, 0); r.line2:SetJustifyH("LEFT")   -- stop before age/Inv
    -- Keep everything on one line. SetWordWrap exists only on the modern client;
    -- on 1.12 we additionally cap the text length in UI_Refresh so it can't wrap.
    if r.line2.SetWordWrap then r.line2:SetWordWrap(false) end
    if r.roles.SetWordWrap then r.roles:SetWordWrap(false) end
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    -- Group (LFM) -> whisper the leader to get in; solo (LFG) -> invite them.
    r.act:SetScript("OnClick", function()
        if not r.entryName then return end
        if r.isGroup then A.Whisper(r.entryName) else A.Invite(r.entryName) end
    end)

    r:SetScript("OnClick", function() if r.entryName then A.Whisper(r.entryName) end end)
    r:SetScript("OnEnter", function()
        if not r.entryName then return end
        _G.GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        _G.GameTooltip:AddLine(r.entryName)
        if r.fullDung and r.fullDung ~= "" then _G.GameTooltip:AddLine(r.fullDung, 0.8, 0.8, 1, true) end
        if r.fullNote then _G.GameTooltip:AddLine(r.fullNote, 1, 1, 1, true) end
        if r.isGroup then
            _G.GameTooltip:AddLine("Group (LFM) - whisper to ask for an invite", 0.6, 0.6, 0.6)
        else
            _G.GameTooltip:AddLine("Solo (LFG) - invite them to your group", 0.6, 0.6, 0.6)
        end
        _G.GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    return r
end

function A.UI_Refresh()
    A.UI_RefreshDungeons()
    if not frame or not frame:IsShown() then return end
    if A._busyP then return end                        -- guard against scroll re-entrancy
    A._busyP = true
    local list  = A.GetSortedEntries(filterBox and filterBox:GetText() or nil)
    local total = A.tlen(list)

    _G.FauxScrollFrame_Update(pScroll, total, PROWS, PROW_H)
    local offset = _G.FauxScrollFrame_GetOffset(pScroll)

    for i = 1, PROWS do
        local r = pRows[i]
        local e = list[i + offset]
        if e then
            local hex = A.ClassColorHex(e.class)
            local nm  = e.name
            if e.level then nm = nm .. " (" .. e.level .. ")" end
            -- LFG (solo, teal) vs LFM (group, gold)
            r.isGroup = (e.kind == "group")
            if r.isGroup then
                r.tag:SetText("|cffffcc33LFM|r")
                r.act:SetText("Whisper")
            else
                r.tag:SetText("|cff33ccffLFG|r")
                r.act:SetText("Inv")
            end
            r.name:SetText("|cff" .. hex .. nm .. "|r")
            r.roles:SetText(roleBadges(e.roles))
            -- second line: [count] dungeons (source-tinted) then note in grey.
            -- Cap the PLAIN text to a char budget before adding color codes, so it
            -- never wraps to a second visual line (which would overlap the next row).
            local dcolor = "ffd200"                         -- chat = gold
            if e.source == "sync" then dcolor = "8ccfff"    -- synced = blue
            elseif e.source == "self" then dcolor = "66ff66" end -- you = green

            local prefix = ""
            if e.count and e.count ~= "" then prefix = "(" .. e.count .. ") " end
            local dpart = e.dungeons or ""
            local npart = e.note or ""

            local budget = 52 - _G.string.len(prefix)
            if _G.string.len(dpart) > budget then dpart = _G.string.sub(dpart, 1, budget) end
            local rem = budget - _G.string.len(dpart)
            if dpart ~= "" and npart ~= "" then rem = rem - 2 end
            if rem < 0 then rem = 0 end
            if _G.string.len(npart) > rem then
                if rem > 3 then npart = _G.string.sub(npart, 1, rem - 3) .. "..." else npart = "" end
            end

            local line2 = ""
            if prefix ~= "" then line2 = "|cffffcc33" .. prefix .. "|r" end
            if dpart ~= "" then line2 = line2 .. "|cff" .. dcolor .. dpart .. "|r" end
            if npart ~= "" then
                if dpart ~= "" or prefix ~= "" then line2 = line2 .. " " end
                line2 = line2 .. "|cff9d9d9d" .. npart .. "|r"
            end
            r.line2:SetText(line2)
            r.age:SetText(ageText(math.floor(A.now() - (e.lastSeen or A.now()))))
            r.entryName = e.name
            r.fullNote  = e.note
            r.fullDung  = e.dungeons
            r:Show()
        else
            r.entryName = nil
            r:Hide()
        end
    end
    if frame.count then frame.count:SetText(total .. " listed") end
    if frame.update then
        if A.newestSeen then
            frame.update:SetText("|cffff4444Update available: v" .. A.newestSeen
                .. " (you have v" .. A.version .. ") - github.com/techgeekpr/OpenLFG|r")
        else
            frame.update:SetText("")
        end
    end
    A._busyP = false
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
local function build()
    if frame then return end
    frame = A.NewFrame("OpenLFGFrame")
    frame:SetWidth(FRAME_W); frame:SetHeight(FRAME_H); frame:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
    if frame.SetBackdrop then frame:SetBackdrop(BACKDROP) end
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local p, _, rp, x, y = frame:GetPoint()
        A.db.pos = { p, rp, x, y }
    end)
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    frame:SetFrameStrata("DIALOG")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -14)
    title:SetText("OpenLFG  -  Looking For Group")

    -- "update available" badge under the title (shown only when out of date)
    frame.update = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.update:SetPoint("TOP", title, "BOTTOM", 0, -1)
    frame.update:SetText("")

    local close = _G.CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- vertical divider between panes
    local div = frame:CreateTexture(nil, "ARTWORK")
    div:SetWidth(1); div:SetPoint("TOP", frame, "TOPLEFT", LEFT_W, -40)
    div:SetPoint("BOTTOM", frame, "BOTTOMLEFT", LEFT_W, 40)
    if div.SetColorTexture then div:SetColorTexture(1, 1, 1, 0.15) else div:SetTexture(1, 1, 1, 0.15) end

    -- ---- LEFT: roles ----
    local rLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -42); rLabel:SetText("I can play:")

    roleChecks = {}
    local prev
    for idx, r in ipairs(A.ROLE_ORDER) do
        local cb = _G.CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        cb:SetWidth(20); cb:SetHeight(20)
        if prev then cb:SetPoint("LEFT", prev.label, "RIGHT", 8, 0)
        else cb:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -60) end
        cb.role = r
        cb:SetChecked(A.db.selfRoles and A.db.selfRoles[r] or false)
        cb:SetScript("OnClick", function(self)
            local b = self or _G.this
            local role = b and b.role                 -- read from the button, NOT the
            if not role then return end               -- loop var (nil on Lua 5.0 / 1.12)
            A.db.selfRoles = A.db.selfRoles or {}
            if b:GetChecked() then A.db.selfRoles[role] = true else A.db.selfRoles[role] = nil end
        end)
        local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        local c = A.ROLE_COLOR[r]
        lbl:SetText(A.ROLE_NAME[r]); lbl:SetTextColor(c[1], c[2], c[3])
        cb.label = lbl
        roleChecks[r] = cb
        prev = cb
    end

    -- ---- LEFT: dungeon list ----
    local dLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -84); dLabel:SetText("Dungeons:")

    dScroll = _G.CreateFrame("ScrollFrame", "OpenLFGDScroll", frame, "FauxScrollFrameTemplate")
    dScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -96)
    dScroll:SetWidth(LEFT_W - 30); dScroll:SetHeight(DROWS * DROW_H)
    dScroll:SetScript("OnVerticalScroll", function()
        -- Bypass FauxScrollFrame_OnVerticalScroll (its arg order differs between
        -- clients). The scrollbar value is already current; just re-render.
        A.UI_RefreshDungeons()
    end)
    dRows = {}
    for i = 1, DROWS do dRows[i] = makeDungeonRow(frame, i) end

    -- ---- LEFT: note field ----
    local noteLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteLbl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 66)
    noteLbl:SetText("Note (e.g. \"LBRS first 3\"):")

    local noteBox = _G.CreateFrame("EditBox", "OpenLFGNote", frame, "InputBoxTemplate")
    noteBox:SetHeight(18); noteBox:SetWidth(LEFT_W - 40)
    noteBox:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 22, 44)
    noteBox:SetAutoFocus(false)
    noteBox:SetMaxLetters(120)
    noteBox:SetText(A.db.selfNote or "")
    noteBox:SetScript("OnTextChanged", function(self)
        A.db.selfNote = (self or _G.this):GetText()
    end)
    noteBox:SetScript("OnEnterPressed", function(self)
        local eb = self or _G.this
        A.db.selfNote = eb:GetText()
        A.AnnounceSelf(A.db.selfNote)
        eb:ClearFocus()
    end)
    noteBox:SetScript("OnEscapePressed", function(self) (self or _G.this):ClearFocus() end)
    frame.noteBox = noteBox

    -- ---- LEFT: buttons ----
    local setBtn = _G.CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    setBtn:SetWidth(96); setBtn:SetHeight(20)
    setBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
    setBtn:SetText("Set LFG")
    setBtn:SetScript("OnClick", function() A.AnnounceSelf(A.db.selfNote) end)

    local clrBtn = _G.CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clrBtn:SetWidth(96); clrBtn:SetHeight(20)
    clrBtn:SetPoint("LEFT", setBtn, "RIGHT", 6, 0)
    clrBtn:SetText("Clear")
    clrBtn:SetScript("OnClick", function() A.ClearSelf() end)

    -- ---- RIGHT: header / controls ----
    local pLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_W + 16, -42); pLabel:SetText("Players looking for group")

    filterBox = _G.CreateFrame("EditBox", "OpenLFGFilter", frame, "InputBoxTemplate")
    filterBox:SetWidth(120); filterBox:SetHeight(16)
    filterBox:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_W + 20, -58)
    filterBox:SetAutoFocus(false)
    filterBox:SetScript("OnTextChanged", function() A.UI_Refresh() end)
    filterBox:SetScript("OnEscapePressed", function() filterBox:ClearFocus() end)
    local fLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fLbl:SetPoint("LEFT", filterBox, "RIGHT", 4, 0); fLbl:SetText("filter")

    local matchCb = _G.CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    matchCb:SetWidth(18); matchCb:SetHeight(18)
    matchCb:SetPoint("LEFT", fLbl, "RIGHT", 10, 0)
    matchCb:SetChecked(A.db.matchMyDungeons)
    matchCb:SetScript("OnClick", function(self)
        local b = self or _G.this
        A.db.matchMyDungeons = b:GetChecked() and true or false
        A.UI_Refresh()
    end)
    local mLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mLbl:SetPoint("LEFT", matchCb, "RIGHT", 2, 0); mLbl:SetText("match my dungeons")

    pScroll = _G.CreateFrame("ScrollFrame", "OpenLFGPScroll", frame, "FauxScrollFrameTemplate")
    pScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_W + 12, -88)
    pScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 36)
    pScroll:SetScript("OnVerticalScroll", function()
        A.UI_Refresh()
    end)
    pRows = {}
    for i = 1, PROWS do pRows[i] = makePlayerRow(frame, i) end

    frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 18)

    if A.db.pos then
        frame:ClearAllPoints()
        frame:SetPoint(A.db.pos[1], _G.UIParent, A.db.pos[2], A.db.pos[3], A.db.pos[4])
    end
    frame:Hide()
end

function A.UI_Toggle()
    build()
    if frame:IsShown() then
        frame:Hide()
    else
        if frame.noteBox then frame.noteBox:SetText(A.db.selfNote or "") end
        frame:Show()
        A.UI_Refresh()
    end
end
