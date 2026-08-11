--[[ OpenLFG -- Comm.lua
     Addon-to-addon sync over a hidden custom chat channel (works on both 1.12
     and 1.14 where SendAddonMessage has no server-wide option).

     Wire protocol -- one line per message, sent to the hidden channel:
       OLFG1|ADD|name|level|class|dungeonKeysCSV|roles|kind|count|note|ageSeconds
       OLFG1|REM|name
       OLFG1|REQ                (new login asking peers for their self-entry)
       OLFG1|VER|versionString  (addon version, for the out-of-date check)

     Only your OWN entry is broadcast (self-announce + reply to REQ), so there
     are no rebroadcast storms. Scanned world-chat entries stay local -- every
     addon user scans the same channel, so boards converge anyway. ]]

local A = OpenLFG
local _G = A._G

local PREFIX = "OLFG1"
local SEP    = "|"
local started = false

-- ---- outgoing send queue (rate-limited; vanilla disconnects on chat spam) --
local queue, sending = {}, false
local function pump()
    if A.tlen(queue) == 0 then sending = false; return end
    sending = true
    local text = _G.table.remove(queue, 1)
    A.SendToChannel(A.db.syncChannel, text)
    A.After(1.5, pump)
end
local function enqueue(text)
    if not (A.db and A.db.sync) then return end
    _G.table.insert(queue, text)
    if not sending then pump() end
end

-- ---- encode helpers --------------------------------------------------------
local function esc(s)
    s = tostring(s or "")
    s = _G.string.gsub(s, "[%z\1-\31]", " ")   -- kill control chars
    s = _G.string.gsub(s, "%" .. SEP, "/")     -- our field separator can't appear in data
    return s
end

-- ---- broadcasts ------------------------------------------------------------
function A.Comm_BroadcastSelf()
    if not (A.db and A.db.sync) then return end
    local name  = _G.UnitName("player")
    local e = A.board[name]
    if not e then return end
    local age = math.floor(A.now() - (e.firstSeen or A.now()))
    local dcsv = e.dungeonKeys and A.KeysToCSV(e.dungeonKeys) or ""
    enqueue(_G.table.concat({
        PREFIX, "ADD", esc(name), esc(e.level or 0), esc(e.class or ""),
        esc(dcsv), esc(e.roles or ""), esc(e.kind or "solo"), esc(e.count or ""),
        esc(e.note or ""), esc(age),
    }, SEP))
end

function A.Comm_BroadcastRemoveSelf()
    if not (A.db and A.db.sync) then return end
    enqueue(_G.table.concat({ PREFIX, "REM", esc(_G.UnitName("player")) }, SEP))
end

local function requestBoard()
    enqueue(PREFIX .. SEP .. "REQ")
end

function A.Comm_BroadcastVersion()
    enqueue(PREFIX .. SEP .. "VER" .. SEP .. esc(A.version))
end

-- ---- incoming --------------------------------------------------------------
local lastReqReply = 0
function A.Comm_OnMessage(text, sender)
    if not text then return end
    local parts = A.split(text, SEP)   -- preserves empty fields (dungeons/note)
    if parts[1] ~= PREFIX then return end
    local kind = parts[2]

    if kind == "ADD" then
        local name = A.ShortName(parts[3])
        if not name or name == "" then return end
        if name == _G.UnitName("player") then return end
        local level = tonumber(parts[4]) or nil
        A.AddEntry({
            name = name, level = level, class = (parts[5] ~= "" and parts[5] or nil),
            dungeonKeys = A.CSVToSet(parts[6] or ""),
            roles = (parts[7] ~= "" and parts[7] or nil),
            kind = (parts[8] ~= "" and parts[8] or "solo"),
            count = parts[9] or "",
            note = parts[10], source = "sync",
        })

    elseif kind == "VER" then
        if A.OnPeerVersion then A.OnPeerVersion(parts[3]) end

    elseif kind == "REM" then
        local name = A.ShortName(parts[3])
        if name and name ~= _G.UnitName("player") then A.RemoveEntry(name) end

    elseif kind == "REQ" then
        -- Reply with our own self-entry, if any, after a small random-ish delay
        -- (spread by name length so peers don't all answer on the same tick).
        local myName = _G.UnitName("player")
        local now = A.now()
        if now - lastReqReply > 5 then
            lastReqReply = now
            local jitter = 1 + A.mod(_G.string.len(myName), 4)
            A.After(jitter, A.Comm_BroadcastVersion)   -- help new logins detect updates
            if A.board[myName] and A.board[myName].source == "self" then
                A.After(jitter, A.Comm_BroadcastSelf)
            end
        end
    end
end

-- ---- lifecycle -------------------------------------------------------------
local function ensureJoined()
    if not (A.db and A.db.sync) then return false end
    if A.ChannelId(A.db.syncChannel) then return true end
    A.JoinHiddenChannel(A.db.syncChannel)
    return A.ChannelId(A.db.syncChannel) ~= nil
end

function A.Comm_Start()
    if started then return end
    if not (A.db and A.db.sync) then return end
    started = true
    if ensureJoined() then
        requestBoard()
        A.After(3, A.Comm_BroadcastVersion)   -- announce our version on login
        -- refresh our own entry + version to peers every 4 min
        A.NewTicker(240, function()
            A.Comm_BroadcastVersion()
            local myName = _G.UnitName("player")
            if A.board[myName] and A.board[myName].source == "self" then
                A.Comm_BroadcastSelf()
            end
        end)
    else
        A.After(8, function() started = false; A.Comm_Start() end)  -- retry
    end
end

-- Re-join after zoning / reconnect if we dropped the channel.
function A.Comm_Rejoin()
    if not (A.db and A.db.sync) then return end
    if not A.ChannelId(A.db.syncChannel) then
        ensureJoined()
    end
end
