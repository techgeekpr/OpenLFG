--[[ OpenLFG -- Dungeons.lua
     Dungeon/raid catalogue, role catalogue, and the detection + (de)serialize
     helpers built on top of them. Loaded after Compat, before Scan. ]]

local A = OpenLFG
local _G = A._G

-- key -> { name, min, max, raid }
A.DUNGEON_INFO = {
    RFC  = { name = "Ragefire Chasm",        min = 13, max = 18 },
    WC   = { name = "Wailing Caverns",       min = 17, max = 24 },
    VC   = { name = "The Deadmines",         min = 17, max = 26 },
    SFK  = { name = "Shadowfang Keep",       min = 22, max = 30 },
    BFD  = { name = "Blackfathom Deeps",     min = 24, max = 32 },
    STK  = { name = "The Stockade",          min = 24, max = 32 },
    GNO  = { name = "Gnomeregan",            min = 29, max = 38 },
    RFK  = { name = "Razorfen Kraul",        min = 30, max = 40 },
    SM   = { name = "Scarlet Monastery",     min = 28, max = 45 },
    RFD  = { name = "Razorfen Downs",        min = 36, max = 46 },
    ULD  = { name = "Uldaman",               min = 42, max = 52 },
    ZF   = { name = "Zul'Farrak",            min = 44, max = 54 },
    MARA = { name = "Maraudon",              min = 46, max = 55 },
    ST   = { name = "Sunken Temple",         min = 50, max = 60 },
    BRD  = { name = "Blackrock Depths",      min = 52, max = 60 },
    DM   = { name = "Dire Maul",             min = 55, max = 60 },
    LBRS = { name = "Lower Blackrock Spire", min = 55, max = 60 },
    UBRS = { name = "Upper Blackrock Spire", min = 58, max = 60 },
    STRT = { name = "Stratholme",            min = 58, max = 60 },
    SCHO = { name = "Scholomance",           min = 58, max = 60 },
    -- raids
    MC   = { name = "Molten Core",           min = 60, max = 60, raid = true },
    ONY  = { name = "Onyxia",                min = 60, max = 60, raid = true },
    BWL  = { name = "Blackwing Lair",        min = 60, max = 60, raid = true },
    ZG   = { name = "Zul'Gurub",             min = 60, max = 60, raid = true },
    AQ20 = { name = "Ruins of AQ (20)",      min = 60, max = 60, raid = true },
    AQ40 = { name = "Temple of AQ (40)",     min = 60, max = 60, raid = true },
    NAXX = { name = "Naxxramas",             min = 60, max = 60, raid = true },
}

-- Display order (level ascending, raids last).
A.DUNGEON_ORDER = {
    "RFC","WC","VC","SFK","BFD","STK","GNO","RFK","SM","RFD","ULD","ZF","MARA",
    "ST","BRD","DM","LBRS","UBRS","STRT","SCHO",
    "MC","ONY","BWL","ZG","AQ20","AQ40","NAXX",
}

-- chat token (lowercase) -> key
A.DUNGEON_TOKENS = {
    rfc="RFC", ragefire="RFC",
    wc="WC", wailing="WC",
    vc="VC", dm="VC", deadmines="VC", vancleef="VC",
    sfk="SFK", shadowfang="SFK",
    bfd="BFD", blackfathom="BFD",
    stk="STK", stocks="STK", stockade="STK", stockades="STK",
    gno="GNO", gnomer="GNO", gnomeregan="GNO",
    rfk="RFK",
    sm="SM", scarlet="SM", monastery="SM", smgy="SM", smlib="SM", smarm="SM", smcath="SM",
    rfd="RFD",
    uld="ULD", uldaman="ULD",
    zf="ZF", zulfarrak="ZF",
    mara="MARA", maraudon="MARA",
    st="ST", sunken="ST", temple="ST", atalhakkar="ST",
    brd="BRD", depths="BRD",
    dire="DM", diremaul="DM", dmt="DM", dme="DM", dmw="DM", dmn="DM",
    lbrs="LBRS", ubrs="UBRS", spire="LBRS",
    strat="STRT", stratholme="STRT",
    scholo="SCHO", scholomance="SCHO",
    mc="MC", molten="MC", moltencore="MC",
    ony="ONY", onyxia="ONY",
    bwl="BWL", blackwing="BWL",
    zg="ZG", zulgurub="ZG", gurub="ZG",
    aq20="AQ20", aq40="AQ40", ruins="AQ20", aq="AQ40",
    naxx="NAXX", naxxramas="NAXX",
}

-- Roles
A.ROLE_ORDER = { "T", "H", "D" }
A.ROLE_NAME  = { T = "Tank", H = "Heal", D = "DPS" }
A.ROLE_COLOR = { T = { 0.45, 0.6, 1.0 }, H = { 0.4, 1.0, 0.5 }, D = { 1.0, 0.5, 0.4 } }

A.ROLE_TOKENS = {
    tank="T", tanks="T", tanking="T", prot="T", mt="T", ot="T", bear="T",
    heal="H", heals="H", healer="H", healers="H", healing="H", resto="H",
    holy="H", disc="H", hpal="H", hpriest="H",
    dps="D", dd="D", deeps="D", damage="D", ranged="D", melee="D",
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
function A.KeyName(key)
    local info = A.DUNGEON_INFO[key]
    return info and info.name or key
end

-- keys can be an array or a set; returns short label CSV of canonical names.
function A.KeysToNames(keys, useShort)
    if not keys then return "" end
    local out = {}
    -- normalise to a presence check that follows DUNGEON_ORDER
    local set = {}
    if keys[1] ~= nil then                      -- array
        for _, k in ipairs(keys) do set[k] = true end
    else
        set = keys                              -- already a set
    end
    for _, k in ipairs(A.DUNGEON_ORDER) do
        if set[k] then
            _G.table.insert(out, useShort and k or A.KeyName(k))
        end
    end
    return _G.table.concat(out, ", ")
end

function A.DetectDungeonKeys(text)
    local lower = _G.string.lower(text or "")
    local set, order = {}, {}
    for w in A.gmatch(lower, "[%w]+") do
        local k = A.DUNGEON_TOKENS[w]
        if k and not set[k] then set[k] = true; _G.table.insert(order, k) end
    end
    return order   -- array of keys in first-seen order
end

-- Returns a role string subset of "THD" in canonical order.
function A.DetectRoles(text)
    local lower = _G.string.lower(text or "")
    local has = {}
    for w in A.gmatch(lower, "[%w]+") do
        local r = A.ROLE_TOKENS[w]
        if r then has[r] = true end
    end
    local out = ""
    for _, r in ipairs(A.ROLE_ORDER) do if has[r] then out = out .. r end end
    return out
end

-- Classify a chat line as solo (LFG) or group-forming (LFM), and pull out a
-- headcount if present ("3/5", "lf2m", "need 2", "2 more"). Returns kind, count.
function A.DetectKind(text)
    local lower = _G.string.lower(text or "")
    local count = ""

    local a, b = A.match(lower, "(%d+)%s*/%s*(%d+)")
    if a and b then count = a .. "/" .. b end
    if count == "" then local n = A.match(lower, "lf%s*(%d+)%s*m"); if n then count = n .. " more" end end
    if count == "" then local n = A.match(lower, "need%s+(%d+)");   if n then count = n .. " more" end end
    if count == "" then local n = A.match(lower, "(%d+)%s+more");   if n then count = n .. " more" end end

    local group = _G.string.find(lower, "lfm")
        or _G.string.find(lower, "lf%s*%d+%s*m")
        or _G.string.find(lower, "%d+%s*/%s*%d+")
        or _G.string.find(lower, "need%s+%d")
        or _G.string.find(lower, "%d+%s+more")
        or _G.string.find(lower, "forming")
        or _G.string.find(lower, "spots")
    return (group and "group" or "solo"), count
end

-- set <-> csv of keys
function A.KeysToCSV(keysSet)
    local out = {}
    for _, k in ipairs(A.DUNGEON_ORDER) do if keysSet[k] then _G.table.insert(out, k) end end
    return _G.table.concat(out, ",")
end

function A.CSVToSet(csv)
    local set = {}
    if not csv or csv == "" then return set end
    for _, k in ipairs(A.split(csv, ",")) do
        if k ~= "" and A.DUNGEON_INFO[k] then set[k] = true end
    end
    return set
end
