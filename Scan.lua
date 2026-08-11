--[[ OpenLFG -- Scan.lua
     Detects LFG intent in public chat and tags the dungeon(s) mentioned.
     Also the single owner of CHAT_MSG_CHANNEL: routes sync-channel traffic to
     Comm and everything else to the scanner. ]]

local A = OpenLFG
local _G = A._G

-- (dungeon + role detection now live in Dungeons.lua)

-- Strong signals: message is LFG on its own.
local STRONG = {
    "lfg", "lf%d*m", "looking for", "want to join", "wtj",
    "%d%s*/%s*%d",      -- 3/5, 4 / 10
    "%d%s+more", "need%s+%d", "%d%s+spot",
}

-- Weak signals: only count as LFG when a dungeon is also present.
local WEAK = {
    ["anyone"]=1, ["any1"]=1, ["inv"]=1, ["invite"]=1, ["more"]=1, ["spot"]=1,
    ["spots"]=1, ["run"]=1, ["runs"]=1, ["grp"]=1, ["group"]=1, ["heal"]=1,
    ["healer"]=1, ["tank"]=1, ["dps"]=1, ["dd"]=1, ["need"]=1, ["boost"]=1,
    ["summon"]=1, ["sum"]=1, ["forming"]=1, ["lf"]=1,
}

-- Words we never want to treat as LFG (reduce false positives).
local NEGATIVE = { ["wts"]=1, ["wtb"]=1, ["selling"]=1, ["buying"]=1 }

function A.SanitizeNote(note)
    if not note then return nil end
    note = _G.string.gsub(note, "[%z\1-\31]", " ")   -- strip control chars incl. our separators
    note = A.trim(note)
    if _G.string.len(note) > 120 then note = _G.string.sub(note, 1, 120) .. "..." end
    return note
end

-- Decide whether a chat line is an LFG post.
-- Returns isLFG, dungeonKeys(array), roles(string).
function A.IsLFG(text)
    local lower = _G.string.lower(text or "")

    local words = {}
    for w in A.gmatch(lower, "[%w]+") do words[w] = true end
    for w in pairs(NEGATIVE) do
        if words[w] then return false end
    end

    local dungeonKeys = A.DetectDungeonKeys(text)
    local roles       = A.DetectRoles(text)

    for _, pat in ipairs(STRONG) do
        if _G.string.find(lower, pat) then
            return true, dungeonKeys, roles
        end
    end

    if A.tlen(dungeonKeys) > 0 then
        for w in pairs(words) do
            if WEAK[w] then return true, dungeonKeys, roles end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Chat routing
-- ---------------------------------------------------------------------------
local function scanLine(text, sender, channelName)
    if not text or text == "" then return end
    local me = _G.UnitName("player")
    local short = A.ShortName(sender)
    if short == me then return end            -- our own posts come via self-announce

    local isLFG, dungeonKeys, roles = A.IsLFG(text)
    if not isLFG then return end

    local kind, count = A.DetectKind(text)

    A.AddEntry({
        name = short, note = A.SanitizeNote(text),
        dungeonKeys = dungeonKeys, roles = roles,
        kind = kind, count = count,
        source = "chat", channel = channelName,
    })
end

local function onChat(event, a1, a2, a3, a4, a5, a6, a7, a8, a9)
    if not A.db or not A.db.enabled then return end

    if event == "CHAT_MSG_CHANNEL" then
        local text, sender, baseName = a1, a2, a9
        -- Route our hidden sync channel to Comm; never scan it.
        if A.db.sync and baseName and A.db.syncChannel
           and _G.string.lower(baseName) == _G.string.lower(A.db.syncChannel) then
            if A.Comm_OnMessage then A.Comm_OnMessage(text, sender) end
            return
        end
        scanLine(text, sender, baseName)

    elseif event == "CHAT_MSG_SAY" or event == "CHAT_MSG_YELL" then
        if A.db.scanSayYell then scanLine(a1, a2, event == "CHAT_MSG_YELL" and "Yell" or "Say") end
    end
end

A.scanFrame = A.CreateEventFrame(onChat)
A.scanFrame:RegisterEvent("CHAT_MSG_CHANNEL")
A.scanFrame:RegisterEvent("CHAT_MSG_SAY")
A.scanFrame:RegisterEvent("CHAT_MSG_YELL")
