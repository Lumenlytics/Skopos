-- Skopos: frame cartographer.
-- /sko map [full]   snapshot every frame (full = include textures/fontstrings) into SkoposDB
-- /sko grab [sec]   after a countdown, capture the frame stack under the mouse
-- /sko find <text>  search live frame names
-- /sko api <text>   search _G for globals (does this API exist in this build?)
-- /sko secret <api> [args]  call an API, report whether its returns are SECRET
-- /sko note <text>  attach a note to the latest grab
-- /sko clear        wipe saved grabs
-- SavedVariables only hit disk on /reload or logout.

local ADDON_NAME = ...
local VERSION = "1.2.0"

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

-- The frame map answers "does this WIDGET exist". This answers the other half:
-- "does this API exist in this build" — globals are not frames, so EnumerateFrames
-- will never surface a function name no matter how complete the map is. Results are
-- recorded to SkoposDB.api so the answer survives to disk and can be read out of game.
--
-- Hoisted so the sweep doesn't build a closure per global.
local function indexGlobal(t, k) return t[k] end

-- Deliberately NOT routed through safe(): scrub() turns secrets into nil, which is
-- correct for geometry but here would report a secret global as "does not exist" —
-- the exact opposite of the truth. So secret is reported as its own type.
local function ApiProbe(pattern)
    if not pattern or pattern == "" then
        msg("Usage: /sko api <text>   (substring of a global name, case-insensitive)")
        return
    end
    local needle = pattern:lower()
    local results = {}
    for k in pairs(_G) do
        if type(k) == "string" and k:lower():find(needle, 1, true) then
            local ok, v = pcall(indexGlobal, _G, k)
            local vtype
            if not ok then
                vtype = "forbidden"
            elseif issecretvalue and issecretvalue(v) then
                vtype = "secret"
            else
                vtype = type(v)
            end
            results[#results + 1] = k .. "|" .. vtype
        end
    end
    table.sort(results)
    table.insert(SkoposDB.api, {
        time = date("%Y-%m-%d %H:%M:%S"),
        build = select(4, GetBuildInfo()),
        query = pattern,
        count = #results,
        results = results,
    })
    msg(("%d global(s) matching '%s':"):format(#results, pattern))
    for i = 1, math.min(#results, 30) do chatLine(results[i]) end
    if #results > 30 then
        msg(("...%d more not shown — |cffffcc00/reload|r and read SkoposDB.api."):format(#results - 30))
    end
    msg(("Saved as api query #%d. |cffffcc00/reload|r to flush to disk."):format(#SkoposDB.api))
end

-- /sko api answers "does this exist". This answers the follow-up that actually decides
-- whether a feature is cheap or hard on Midnight: "is what it hands back a SECRET?"
-- A secret survives pcall and only detonates on later arithmetic, comparison or
-- concat — so a value can look perfectly fine and blow up three functions later.
--
-- Deliberately permitted IN COMBAT, unlike /sko map: many values are secret only in
-- combat, so combat state is part of the answer and is recorded alongside it.

local unpack = unpack or table.unpack

-- pcall returns a variable number of values and some may be nil, so select("#") is
-- the only honest count — #results would stop at the first nil.
local function capture(ok, ...)
    return ok, { n = select("#", ...), ... }
end

-- Never call this on a value until it is known non-secret: tostring on a secret is
-- exactly the kind of coercion that detonates.
local function renderValue(v, maxLen)
    maxLen = maxLen or 60
    if type(v) == "string" then
        if #v > maxLen then return v:sub(1, maxLen) .. "…" end
        return v
    end
    local ok, s = pcall(tostring, v)
    if ok and type(s) == "string" then return s end
    return "<tostring failed>"
end

-- Walks a dotted path (C_Spell.GetSpellCooldown) a segment at a time, so a missing
-- namespace reports which segment broke instead of erroring.
local function resolvePath(path)
    local cur = _G
    for part in path:gmatch("[^%.]+") do
        if type(cur) ~= "table" then
            return nil, "'" .. part .. "' — the thing before it is not a table"
        end
        local ok, nxt = pcall(indexGlobal, cur, part)
        if not ok then
            return nil, "indexing '" .. part .. "' errored (forbidden?)"
        end
        if nxt == nil then
            return nil, "'" .. part .. "' does not exist"
        end
        cur = nxt
    end
    return cur
end

local function classify(v)
    local isSecret = (issecretvalue and issecretvalue(v)) and true or false
    return isSecret, type(v), isSecret and "<secret>" or renderValue(v)
end

local function SecretProbe(input)
    if not input or input == "" then
        msg("Usage: /sko secret <API> [args]   e.g. /sko secret UnitPower player")
        chatLine("args coerce: numbers, true, false, nil — anything else stays a string")
        chatLine("dotted paths work: /sko secret C_Spell.GetSpellCooldown 6552")
        return
    end
    local path, rest = input:match("^(%S+)%s*(.-)%s*$")
    local target, err = resolvePath(path)
    if not target then
        msg(("Cannot resolve '%s': %s"):format(path, err))
        return
    end

    local argv, argn = {}, 0
    for word in rest:gmatch("%S+") do
        argn = argn + 1
        if word == "nil" then argv[argn] = nil
        elseif word == "true" then argv[argn] = true
        elseif word == "false" then argv[argn] = false
        else argv[argn] = tonumber(word) or word end
    end

    local inCombat = InCombatLockdown() and true or false
    local lines, anySecret, errText, headline = {}, false, nil, nil

    if type(target) ~= "function" then
        -- Not callable, but "this global is a secret table" is still a real answer.
        local isSecret, vtype, shown = classify(target)
        anySecret = isSecret
        headline = "is not a function — the value itself:"
        lines[1] = table.concat({ "0", vtype, isSecret and "SECRET" or "plain", shown }, "|")
    else
        local ok, res = capture(pcall(target, unpack(argv, 1, argn)))
        if not ok then
            errText = renderValue(res[1], 200)
        elseif res.n == 0 then
            headline = "returned no values"
        else
            headline = ("-> %d value(s)"):format(res.n)
            for i = 1, res.n do
                local isSecret, vtype, shown = classify(res[i])
                if isSecret then anySecret = true end
                lines[#lines + 1] = table.concat({ i, vtype,
                    isSecret and "SECRET" or "plain", shown }, "|")
            end
        end
    end

    -- Store the rendered strings only, never the raw values: a secret written into
    -- SavedVariables would either fail to serialise or poison whatever reads it.
    table.insert(SkoposDB.secret, {
        time = date("%Y-%m-%d %H:%M:%S"),
        build = select(4, GetBuildInfo()),
        query = input,
        inCombat = inCombat,
        errored = errText,
        anySecret = anySecret,
        returns = lines,
    })

    if errText then
        msg(("%s errored: %s"):format(path, errText))
    else
        msg(("%s %s%s"):format(path, headline,
            anySecret and " |cffff4444SECRET present|r" or ""))
        for _, line in ipairs(lines) do chatLine(line) end
    end
    msg(("%s. Saved as secret probe #%d. |cffffcc00/reload|r to flush to disk."):format(
        inCombat and "|cffff8800IN COMBAT|r" or "Out of combat", #SkoposDB.secret))
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
    chatLine("/sko api <txt>  search _G — does this API exist in this build?")
    chatLine("/sko secret <api> [args]  does it return a SECRET? (works in combat)")
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
    elseif cmd == "api" then
        ApiProbe(rest)
    elseif cmd == "secret" then
        SecretProbe(rest)
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
    SkoposDB.api = SkoposDB.api or {}
    SkoposDB.secret = SkoposDB.secret or {}
    msg("v" .. VERSION .. " loaded. /sko for commands.")
end)
