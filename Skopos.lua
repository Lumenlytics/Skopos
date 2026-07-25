-- Skopos: frame cartographer.
-- /sko map [full]   snapshot every frame (full = include textures/fontstrings) into SkoposDB
-- /sko grab [sec]   after a countdown, capture the frame stack under the mouse
-- /sko find <text>  search live frame names
-- /sko note <text>  attach a note to the latest grab
-- /sko clear        wipe saved grabs
-- SavedVariables only hit disk on /reload or logout.

local ADDON_NAME = ...
local VERSION = "1.0.0"

-- Map/grab line format, 8 pipe-delimited columns:
-- debugName|objectType|parentDebugName|vis|WxH|strata:level|anchor|flags
--   vis:    V visible, S shown-but-parent-hidden, H hidden
--   anchor: POINT->RelativeName:RELPOINT(x,y)  (+N = additional points)
--   flags:  P protected, M mouse-enabled, F forbidden, R region (layer:sublevel in col 6)
local LINE_FORMAT = "debugName|objectType|parent|vis|WxH|strata:level|anchor|flags"

local function msg(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Skopos|r " .. text)
end

-- Chat interprets "|" as an escape; double it for display only.
local function chatLine(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa  " .. text:gsub("|", "||") .. "|r")
end

-- Secret-marked frames may hand back secret values instead of erroring — and a
-- secret survives pcall, then detonates on any later arithmetic, comparison, or
-- concat. So every widget call goes through pcall AND every return is scrubbed:
-- secrets come out as nil, so downstream "or '?'" fallbacks kick in.
local function scrub(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function safe(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if not ok then return nil end
    return scrub(a), scrub(b), scrub(c), scrub(d), scrub(e)
end

local function round(n)
    if type(n) ~= "number" or (issecretvalue and issecretvalue(n)) then return "?" end
    return math.floor(n * 10 + 0.5) / 10
end

local function debugName(obj)
    local name = safe(obj.GetDebugName, obj)
    if type(name) == "string" and name ~= "" then return name end
    return "(anon)"
end

local function describeAnchor(f, parentName)
    local n = safe(f.GetNumPoints, f)
    if not n or n == 0 then return "" end
    local point, relTo, relPoint, x, y = safe(f.GetPoint, f, 1)
    if not point then return "?" end
    local relName
    if relTo then
        relName = debugName(relTo)
    else
        relName = (parentName ~= "" and parentName) or "parent"
    end
    local s = point .. "->" .. relName .. ":" .. (relPoint or "?")
        .. "(" .. round(x or 0) .. "," .. round(y or 0) .. ")"
    if n > 1 then s = s .. "+" .. (n - 1) end
    return s
end

local function describeFrame(f)
    if safe(f.IsForbidden, f) then
        return debugName(f) .. "|?|?|?|?|?|?|F"
    end
    local name = debugName(f)
    local otype = safe(f.GetObjectType, f) or "?"
    local parent = safe(f.GetParent, f)
    local parentName = parent and debugName(parent) or ""
    local vis
    if safe(f.IsVisible, f) then vis = "V"
    elseif safe(f.IsShown, f) then vis = "S"
    else vis = "H" end
    local w, h = safe(f.GetSize, f)
    local size = (w and h) and (round(w) .. "x" .. round(h)) or "?"
    local strata = safe(f.GetFrameStrata, f) or "?"
    local level = safe(f.GetFrameLevel, f) or "?"
    local flags = ""
    if safe(f.IsProtected, f) then flags = flags .. "P" end
    if safe(f.IsMouseEnabled, f) then flags = flags .. "M" end
    return table.concat({
        name, otype, parentName, vis, size,
        strata .. ":" .. level,
        describeAnchor(f, parentName),
        flags,
    }, "|")
end

local function describeRegion(r, parentName)
    local name = debugName(r)
    local otype = safe(r.GetObjectType, r) or "?"
    local vis
    if safe(r.IsVisible, r) then vis = "V"
    elseif safe(r.IsShown, r) then vis = "S"
    else vis = "H" end
    local w, h = safe(r.GetSize, r)
    local size = (w and h) and (round(w) .. "x" .. round(h)) or "?"
    local layer, sublevel = safe(r.GetDrawLayer, r)
    local content = ""
    if otype == "Texture" then
        local atlas = safe(r.GetAtlas, r)
        if atlas and atlas ~= "" then
            content = "atlas:" .. atlas
        else
            local tex = safe(r.GetTexture, r)
            if tex then content = "tex:" .. tostring(tex) end
        end
    elseif otype == "FontString" then
        local ok, text = pcall(r.GetText, r)
        if ok and type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
            if #text > 40 then text = text:sub(1, 40) .. "…" end
            content = "text:" .. text
        end
    end
    return table.concat({
        name, otype, parentName, vis, size,
        tostring(layer or "?") .. ":" .. tostring(sublevel or "?"),
        content, "R",
    }, "|")
end

local function collectRegions(f, parentName, lines)
    local results = { pcall(f.GetRegions, f) }
    if not results[1] then return end
    for i = 2, #results do
        local r = results[i]
        if r then lines[#lines + 1] = describeRegion(r, parentName) end
    end
end

local function eachFrame(callback)
    if EnumerateFrames then
        local f = EnumerateFrames()
        while f do
            callback(f)
            f = EnumerateFrames(f)
        end
        return true
    end
    -- Fallback if EnumerateFrames ever disappears: walk from the two roots.
    -- Misses detached frames but beats nothing.
    local seen = {}
    local function walk(f)
        if not f or seen[f] then return end
        seen[f] = true
        callback(f)
        local kids = { pcall(f.GetChildren, f) }
        if kids[1] then
            for i = 2, #kids do walk(kids[i]) end
        end
    end
    walk(UIParent)
    walk(WorldFrame)
    return false
end

local function BuildMap(includeRegions)
    if InCombatLockdown() then
        msg("In combat — geometry reads go secret and the map would be full of holes. Try again out of combat.")
        return
    end
    local lines = {}
    local frameCount = 0
    eachFrame(function(f)
        frameCount = frameCount + 1
        lines[#lines + 1] = describeFrame(f)
        if includeRegions and not safe(f.IsForbidden, f) then
            collectRegions(f, debugName(f), lines)
        end
    end)
    local sw, sh = GetPhysicalScreenSize()
    SkoposDB.map = {
        meta = {
            when = date("%Y-%m-%d %H:%M:%S"),
            version = VERSION,
            build = select(4, GetBuildInfo()),
            screen = sw .. "x" .. sh,
            uiScale = UIParent and UIParent:GetEffectiveScale() or 1,
            frameCount = frameCount,
            lineCount = #lines,
            includesRegions = includeRegions or false,
            format = LINE_FORMAT,
        },
        frames = lines,
    }
    msg(("Mapped %d frames (%d lines%s)."):format(
        frameCount, #lines, includeRegions and ", regions included" or ""))
    msg("|cffffcc00/reload|r to flush the map to SavedVariables\\Skopos.lua.")
end

local function Grab(delaySec)
    local delay = tonumber(delaySec) or 2
    msg(("Grabbing whatever is under the mouse in %d second(s) — hover it now."):format(delay))
    C_Timer.After(delay, function()
        local foci
        if GetMouseFoci then
            foci = GetMouseFoci()
        elseif GetMouseFocus then
            foci = { GetMouseFocus() }
        end
        if not foci or #foci == 0 then
            msg("Nothing under the mouse.")
            return
        end
        local stack = {}
        for i, f in ipairs(foci) do
            stack[i] = describeFrame(f)
        end
        local ancestry = {}
        local p = foci[1]
        while p do
            ancestry[#ancestry + 1] = debugName(p)
            p = safe(p.GetParent, p)
        end
        local pick = {
            time = date("%Y-%m-%d %H:%M:%S"),
            stack = stack,
            ancestry = table.concat(ancestry, " <- "),
        }
        table.insert(SkoposDB.picks, pick)
        msg(("Grabbed %d frame(s) under the mouse:"):format(#stack))
        for _, line in ipairs(stack) do chatLine(line) end
        msg("Ancestry: |cffffffff" .. pick.ancestry:gsub("|", "||") .. "|r")
        msg(("Saved as pick #%d. /sko note <text> to annotate, /reload to flush to disk."):format(#SkoposDB.picks))
    end)
end

local function Find(pattern)
    if not pattern or pattern == "" then
        msg("Usage: /sko find <text>")
        return
    end
    local needle = pattern:lower()
    local results = {}
    eachFrame(function(f)
        if not safe(f.IsForbidden, f) then
            local name = safe(f.GetDebugName, f)
            if type(name) == "string" and name:lower():find(needle, 1, true) then
                results[#results + 1] = describeFrame(f)
            end
        end
    end)
    msg(("%d match(es) for '%s':"):format(#results, pattern))
    for i = 1, math.min(#results, 30) do chatLine(results[i]) end
    if #results > 30 then
        msg(("...%d more not shown — narrow the search, or /sko map and read the file."):format(#results - 30))
    end
end

local function Note(text)
    if not text or text == "" then
        msg("Usage: /sko note <text>")
        return
    end
    local pick = SkoposDB.picks[#SkoposDB.picks]
    if not pick then
        msg("No grabs yet — /sko grab first.")
        return
    end
    pick.note = text
    msg(("Noted on pick #%d: %s"):format(#SkoposDB.picks, text))
end

local function Help()
    msg("v" .. VERSION .. " — frame cartographer")
    chatLine("/sko map        snapshot every frame into SavedVariables")
    chatLine("/sko map full   same, plus textures and fontstrings (bigger file)")
    chatLine("/sko grab [sec] capture the frame stack under the mouse (default 2s)")
    chatLine("/sko find <txt> search live frame names")
    chatLine("/sko note <txt> annotate the latest grab")
    chatLine("/sko clear      wipe saved grabs")
    chatLine("Maps/grabs hit disk on /reload, at WTF\\...\\SavedVariables\\Skopos.lua")
end

SLASH_SKOPOS1 = "/skopos"
SLASH_SKOPOS2 = "/sko"
SlashCmdList.SKOPOS = function(input)
    input = (input or ""):gsub("^%s+", "")
    local cmd, rest = input:match("^(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "map" then
        BuildMap(rest:lower() == "full")
    elseif cmd == "grab" then
        Grab(rest)
    elseif cmd == "find" then
        Find(rest)
    elseif cmd == "note" then
        Note(rest)
    elseif cmd == "clear" then
        SkoposDB.picks = {}
        msg("Grabs cleared.")
    else
        Help()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    SkoposDB = SkoposDB or {}
    SkoposDB.picks = SkoposDB.picks or {}
    msg("v" .. VERSION .. " loaded. /sko for commands.")
end)
