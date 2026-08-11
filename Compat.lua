--[[ OpenLFG -- Compat.lua
     Runtime abstraction so the rest of the addon is written once and runs on
     both the 1.12.1 client (Lua 5.0-era, global-arg events, string.gfind) and
     the 1.14.2 Classic Era client (Lua 5.1, param events, C_Timer, etc).
     Loaded FIRST. ]]

OpenLFG = OpenLFG or {}
local A = OpenLFG

local _G = _G or getfenv(0)
A._G = _G

-- Client detection: C_Timer only exists on the modern (1.14) client.
A.isModern  = (_G.C_Timer ~= nil)
A.isVanilla = not A.isModern
A.version   = "1.2"

-- "1.10.2" -> a single comparable integer.
function A.VersionNum(v)
    local nums = { 0, 0, 0 }
    local i = 1
    for n in (A.gmatch or _G.string.gmatch or _G.string.gfind)(v or "", "%d+") do
        nums[i] = tonumber(n) or 0
        i = i + 1
        if i > 3 then break end
    end
    return nums[1] * 10000 + nums[2] * 100 + nums[3]
end

-- ---------------------------------------------------------------------------
-- String helpers
-- ---------------------------------------------------------------------------
A.gmatch = _G.string.gmatch or _G.string.gfind   -- gmatch renamed from gfind in 2.0

-- Portable string.match (5.0 has no string.match; emulate with string.find).
function A.match(s, pat)
    if not s then return nil end
    if _G.string.match then return _G.string.match(s, pat) end
    local res = { _G.string.find(s, pat) }
    if res[1] == nil then return nil end
    if res[3] ~= nil then return unpack(res, 3) end        -- has captures
    return _G.string.sub(s, res[1], res[2])
end

function A.trim(s)
    if not s then return "" end
    return (_G.string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- Split on a literal separator, PRESERVING empty fields (gmatch drops them).
function A.split(str, sep)
    local out, start = {}, 1
    while true do
        local s, e = _G.string.find(str, sep, start, true)
        if not s then _G.table.insert(out, _G.string.sub(str, start)); break end
        _G.table.insert(out, _G.string.sub(str, start, s - 1))
        start = e + 1
    end
    return out
end

-- Table length that works whether or not table.getn exists.
if _G.table.getn then
    A.tlen = function(t) return _G.table.getn(t) end
else
    A.tlen = function(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end
end

-- Modulo without the '%' operator (Lua 5.0 has no '%'; using it is a parse error).
function A.mod(a, b)
    return a - _G.math.floor(a / b) * b
end

function A.print(msg)
    local f = _G.DEFAULT_CHAT_FRAME
    if f then f:AddMessage("|cff44ccffOpenLFG|r: " .. tostring(msg)) end
end

-- ---------------------------------------------------------------------------
-- Timers  (C_Timer on modern; OnUpdate scheduler on vanilla)
-- ---------------------------------------------------------------------------
if A.isModern and _G.C_Timer and _G.C_Timer.After then
    A.After = function(delay, fn) _G.C_Timer.After(delay, fn) end
else
    local sched  = {}
    local driver = _G.CreateFrame("Frame")
    driver:SetScript("OnUpdate", function()
        local now = _G.GetTime()
        for i = A.tlen(sched), 1, -1 do
            local e = sched[i]
            if e and now >= e.at then
                _G.table.remove(sched, i)
                pcall(e.fn)
            end
        end
    end)
    A.After = function(delay, fn)
        _G.table.insert(sched, { at = _G.GetTime() + delay, fn = fn })
    end
end

-- Repeating ticker built on A.After.
function A.NewTicker(interval, fn)
    local t = { stopped = false }
    local function loop()
        if t.stopped then return end
        pcall(fn)
        A.After(interval, loop)
    end
    A.After(interval, loop)
    t.Cancel = function() t.stopped = true end
    return t
end

-- ---------------------------------------------------------------------------
-- Events  (params on modern; globals event/arg1.. on vanilla)
-- ---------------------------------------------------------------------------
function A.CreateEventFrame(handler)
    local f = _G.CreateFrame("Frame")
    f:SetScript("OnEvent", function(self, event,
            a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12)
        if event == nil then                       -- vanilla: read globals
            event = _G.event
            a1, a2, a3, a4, a5, a6 = _G.arg1, _G.arg2, _G.arg3, _G.arg4, _G.arg5, _G.arg6
            a7, a8, a9, a10, a11, a12 = _G.arg7, _G.arg8, _G.arg9, _G.arg10, _G.arg11, _G.arg12
        end
        handler(event, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12)
    end)
    return f
end

-- ---------------------------------------------------------------------------
-- Frames / backdrops
-- ---------------------------------------------------------------------------
function A.NewFrame(name, parent)
    local tmpl
    if A.isModern and _G.BackdropTemplateMixin then tmpl = "BackdropTemplate" end
    local f = _G.CreateFrame("Frame", name, parent or _G.UIParent, tmpl)
    if not f.SetBackdrop and _G.BackdropTemplateMixin and _G.Mixin then
        _G.Mixin(f, _G.BackdropTemplateMixin)
    end
    return f
end

-- ---------------------------------------------------------------------------
-- Chat channels
-- ---------------------------------------------------------------------------
function A.JoinHiddenChannel(name)
    if A.isModern then
        if _G.JoinTemporaryChannel then _G.JoinTemporaryChannel(name)
        elseif _G.JoinChannelByName then _G.JoinChannelByName(name) end
    else
        if _G.JoinChannelByName then _G.JoinChannelByName(name)
        elseif _G.JoinPermanentChannel then _G.JoinPermanentChannel(name) end
    end
    local id = _G.GetChannelName(name)
    if id and id > 0 then
        for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
            local cf = _G["ChatFrame" .. i]
            if cf and _G.ChatFrame_RemoveChannel then
                _G.ChatFrame_RemoveChannel(cf, name)
            end
        end
    end
    return id
end

function A.ChannelId(name)
    local id = _G.GetChannelName(name)
    if id and id > 0 then return id end
    return nil
end

function A.SendToChannel(name, text)
    local id = A.ChannelId(name)
    if id and _G.SendChatMessage then
        _G.SendChatMessage(text, "CHANNEL", nil, id)
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Player actions
-- ---------------------------------------------------------------------------
function A.Whisper(name)
    if _G.ChatFrame_SendTell then _G.ChatFrame_SendTell(name)
    elseif _G.ChatFrame_OpenChat then _G.ChatFrame_OpenChat("/w " .. name .. " ") end
end

function A.Invite(name)
    if _G.C_PartyInfo and _G.C_PartyInfo.InviteUnit then _G.C_PartyInfo.InviteUnit(name)
    elseif _G.InviteUnit then _G.InviteUnit(name)
    elseif _G.InviteByName then _G.InviteByName(name) end
end

-- Strip a "-Realm" suffix if the channel handed us one.
function A.ShortName(name)
    if not name then return name end
    local base = A.match(name, "^([^-]+)")
    return base or name
end

-- Are we currently in a party or raid? (cross-version)
function A.InGroup()
    if _G.IsInRaid and _G.IsInRaid() then return true end
    if _G.IsInGroup and _G.IsInGroup() then return true end
    local p = (_G.GetNumPartyMembers and _G.GetNumPartyMembers()) or 0
    local r = (_G.GetNumRaidMembers and _G.GetNumRaidMembers()) or 0
    return (p > 0) or (r > 0)
end

function A.ClassColorHex(classToken)
    local c = classToken and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
    if c then
        return _G.string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
    end
    return "ffd100"
end
