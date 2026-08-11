--[[ OpenLFG -- Core.lua
     Saved data, the LFG entry board, expiry, slash commands, wiring. ]]

local A = OpenLFG
local _G = A._G

A.board = {}   -- board[name] = { name, level, class, dungeons, note, firstSeen, lastSeen, source, channel }

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------
local DEFAULTS = {
    enabled        = true,
    lifetime       = 720,     -- seconds an entry lives after last seen (12 min)
    sync           = true,    -- use the hidden sync channel
    syncChannel    = "OpenLFGsync",
    scanSayYell    = false,   -- also scan /say and /yell
    announceToWorld= false,   -- /lfg me also posts to the World channel
    worldChannel   = "World", -- name of the public channel to post to
    minimap        = true,
    autoShow       = false,   -- open the window on login
    pos            = nil,     -- saved window position
    selfDungeons   = {},      -- set of dungeon keys you're LFG for
    selfRoles      = {},      -- set of roles you can play (T/H/D)
    matchMyDungeons= false,   -- right-pane filter toggle
}

local function applyDefaults(db, defaults)
    for k, v in pairs(defaults) do
        if db[k] == nil then
            if type(v) == "table" then db[k] = {} else db[k] = v end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Board operations
-- ---------------------------------------------------------------------------
function A.now() return _G.GetTime() end

-- Add or refresh a board entry. Returns true if it was newly created.
function A.AddEntry(info)
    local name = info.name
    if not name or name == "" then return false end

    local e = A.board[name]
    local isNew = (e == nil)
    if isNew then
        e = { name = name, firstSeen = A.now() }
        A.board[name] = e
    end
    e.lastSeen  = A.now()
    e.source    = info.source or e.source or "chat"
    e.channel   = info.channel or e.channel
    if info.note    and info.note   ~= "" then e.note     = info.note end
    if info.level   then e.level = info.level end
    if info.class   then e.class = info.class end
    if info.roles   then e.roles = info.roles end          -- "THD" subset
    e.kind = info.kind or e.kind or "solo"                 -- "solo" (LFG) / "group" (LFM)
    if info.count ~= nil then e.count = info.count end
    -- dungeon keys as a set, plus a cached display string
    if info.dungeonKeys then
        local set = {}
        if info.dungeonKeys[1] ~= nil then
            for _, k in ipairs(info.dungeonKeys) do set[k] = true end
        else
            set = info.dungeonKeys
        end
        if next(set) then
            e.dungeonKeys = set
            e.dungeons = A.KeysToNames(set)
        end
    elseif info.dungeons and info.dungeons ~= "" then
        e.dungeons = info.dungeons
    end

    if A.UI_Refresh then A.UI_Refresh() end
    return isNew
end

function A.RemoveEntry(name)
    if A.board[name] then
        A.board[name] = nil
        if A.UI_Refresh then A.UI_Refresh() end
    end
end

-- Remove entries older than the configured lifetime.
function A.ExpireEntries()
    local cutoff = A.now() - (A.db.lifetime or 720)
    local changed = false
    for name, e in pairs(A.board) do
        if (e.lastSeen or 0) < cutoff then
            A.board[name] = nil
            changed = true
        end
    end
    if changed and A.UI_Refresh then A.UI_Refresh() end
end

local function overlapsMyDungeons(e)
    local mine = A.db.selfDungeons or {}
    if not next(mine) then return true end          -- nothing selected -> show all
    if not e.dungeonKeys then return false end
    for k in pairs(mine) do if e.dungeonKeys[k] then return true end end
    return false
end

-- Sorted array of active entries (most recent first) for the UI.
function A.GetSortedEntries(filter)
    local list = {}
    local f = filter and filter ~= "" and _G.string.lower(filter) or nil
    for _, e in pairs(A.board) do
        local ok = true
        if f then
            local hay = _G.string.lower((e.name or "") .. " " .. (e.dungeons or "") .. " " .. (e.note or ""))
            if not _G.string.find(hay, f, 1, true) then ok = false end
        end
        if ok and A.db.matchMyDungeons and not overlapsMyDungeons(e) then ok = false end
        if ok then _G.table.insert(list, e) end
    end
    _G.table.sort(list, function(a, b) return (a.lastSeen or 0) > (b.lastSeen or 0) end)
    return list
end

-- ---------------------------------------------------------------------------
-- Self announcement
-- ---------------------------------------------------------------------------
-- roleSet / dungeonSet are optional; default to the saved UI selection.
function A.AnnounceSelf(note, dungeonSet, roleSet)
    local name  = _G.UnitName("player")
    local level = _G.UnitLevel("player")
    local _, class = _G.UnitClass("player")
    note = A.SanitizeNote and A.SanitizeNote(note) or note

    local srcDung = dungeonSet or A.db.selfDungeons or {}
    roleSet       = roleSet    or A.db.selfRoles    or {}

    -- work on a copy so note-detection never mutates the saved selection
    local working = {}
    for k in pairs(srcDung) do working[k] = true end
    for _, k in ipairs(A.DetectDungeonKeys(note or "")) do working[k] = true end
    dungeonSet = working

    local roleStr = ""
    for _, r in ipairs(A.ROLE_ORDER) do if roleSet[r] then roleStr = roleStr .. r end end
    local noteRoles = A.DetectRoles(note or "")
    for i = 1, _G.string.len(noteRoles) do
        local r = _G.string.sub(noteRoles, i, i)
        if not _G.string.find(roleStr, r, 1, true) then roleStr = roleStr .. r end
    end

    -- solo (LFG) vs group (LFM): note wording, or actually being in a party/raid
    local kind, count = A.DetectKind(note or "")
    if A.InGroup() then kind = "group" end

    A.db.selfNote = note
    A.AddEntry({ name = name, level = level, class = class, note = note,
                 dungeonKeys = dungeonSet, roles = roleStr,
                 kind = kind, count = count, source = "self" })

    if A.db.sync and A.Comm_BroadcastSelf then A.Comm_BroadcastSelf() end
    if A.db.announceToWorld then
        A.SendToChannel(A.db.worldChannel, A.ComposeWorldMessage(note, dungeonSet, roleStr))
    end
    A.print("Listed as LFG for: |cffffffff" .. (A.KeysToNames(dungeonSet) ~= "" and A.KeysToNames(dungeonSet) or "(any)")
            .. "|r" .. (roleStr ~= "" and " [" .. roleStr .. "]" or ""))
end

-- Human-readable line for posting to the public World channel.
function A.ComposeWorldMessage(note, dungeonSet, roleStr)
    local parts = { "LFG" }
    local dn = A.KeysToNames(dungeonSet, true)   -- short codes for brevity
    if dn ~= "" then _G.table.insert(parts, dn) end
    if roleStr and roleStr ~= "" then
        local rlabels = {}
        for i = 1, _G.string.len(roleStr) do
            _G.table.insert(rlabels, A.ROLE_NAME[_G.string.sub(roleStr, i, i)])
        end
        _G.table.insert(parts, "(" .. _G.table.concat(rlabels, "/") .. ")")
    end
    local base = _G.table.concat(parts, " ")
    if note and note ~= "" then base = base .. " - " .. note end
    return base
end

function A.ClearSelf()
    local name = _G.UnitName("player")
    A.db.selfNote = nil
    A.RemoveEntry(name)
    if A.db.sync and A.Comm_BroadcastRemoveSelf then A.Comm_BroadcastRemoveSelf() end
    A.print("Removed you from the LFG board.")
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
local function handleSlash(msg)
    msg = A.trim(msg or "")
    local cmd, rest = A.match(msg, "^(%S+)%s*(.*)$")
    cmd = cmd and _G.string.lower(cmd) or ""

    if cmd == "" or cmd == "show" or cmd == "toggle" then
        if A.UI_Toggle then A.UI_Toggle() end
    elseif cmd == "me" or cmd == "lfg" then
        A.AnnounceSelf(rest)
    elseif cmd == "world" then
        local prev = A.db.announceToWorld
        A.db.announceToWorld = true
        A.AnnounceSelf(rest)
        A.db.announceToWorld = prev
    elseif cmd == "off" or cmd == "clear" or cmd == "done" then
        A.ClearSelf()
    elseif cmd == "sync" then
        A.db.sync = not A.db.sync
        A.print("Sync " .. (A.db.sync and "ENABLED" or "DISABLED") .. " (reload to apply channel join).")
    elseif cmd == "lifetime" then
        local n = tonumber(rest)
        if n and n >= 60 and n <= 3600 then
            A.db.lifetime = n
            A.print("Entry lifetime set to " .. n .. "s.")
        else
            A.print("Usage: /lfg lifetime <seconds 60-3600> (current " .. (A.db.lifetime or 720) .. ")")
        end
    elseif cmd == "wipe" then
        A.board = {}
        if A.UI_Refresh then A.UI_Refresh() end
        A.print("Board cleared (local only).")
    else
        A.print("Commands:")
        A.print("  /lfg               - open/close the window")
        A.print("  /lfg me <note>     - list yourself as LFG (synced to addon users)")
        A.print("  /lfg world <note>  - same, and post <note> to the World channel")
        A.print("  /lfg off           - remove yourself")
        A.print("  /lfg sync          - toggle addon-to-addon sync")
        A.print("  /lfg lifetime <s>  - how long entries stay (default 720)")
        A.print("  /lfg wipe          - clear your local board")
    end
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------
local function onEvent(event, a1)
    if event == "ADDON_LOADED" and a1 == "OpenLFG" then
        _G.OpenLFGDB = _G.OpenLFGDB or {}
        A.db = _G.OpenLFGDB
        applyDefaults(A.db, DEFAULTS)

    elseif event == "PLAYER_LOGIN" then
        A.print("v" .. A.version .. " loaded (" .. (A.isModern and "1.14" or "1.12") .. " client). Type /lfg.")
        -- expiry + UI refresh loop
        A.NewTicker(5, function()
            A.ExpireEntries()
            if A.UI_Refresh then A.UI_Refresh() end
        end)
        if A.Comm_Start then A.After(4, A.Comm_Start) end
        if A.db.autoShow and A.UI_Toggle then A.UI_Toggle() end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if A.db and A.db.sync and A.Comm_Rejoin then A.After(6, A.Comm_Rejoin) end
    end
end

A.coreFrame = A.CreateEventFrame(onEvent)
A.coreFrame:RegisterEvent("ADDON_LOADED")
A.coreFrame:RegisterEvent("PLAYER_LOGIN")
A.coreFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

_G.SLASH_OPENLFG1 = "/lfg"
_G.SLASH_OPENLFG2 = "/openlfg"
_G.SlashCmdList["OPENLFG"] = handleSlash
