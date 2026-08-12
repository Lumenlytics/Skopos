-- Skopos: frame cartographer.
-- /sko map [full]   snapshot every frame (full = include textures/fontstrings) into SkoposDB
-- /sko grab [sec]   after a countdown, capture the frame stack under the mouse
-- /sko find <text>  search live frame names
-- /sko api <text>   search _G AND C_* namespaces (does this API exist in this build?)
-- /sko secret <api> [args]  call an API, report whether its returns are SECRET
-- /sko attr <frame> [key]   dump secure attributes + snippets on a live frame
-- /sko events [sec]  register ALL events for a window, report what actually fired
-- /sko note <text>  attach a note to the latest grab
-- /sko clear        wipe saved grabs
-- SavedVariables only hit disk on /reload or logout.

local ADDON_NAME = ...
local VERSION = "1.6.0"

-- Map/grab line format, 8 pipe-delimited columns:
-- debugName|objectType|parentDebugName|vis|WxH|strata:level|anchor|flags
--   vis:    V visible, S shown-but-parent-hidden, H hidden,
--           ? visibility UNREADABLE (secret or errored) — not the same as hidden
--   anchor: POINT->RelativeName:RELPOINT(x,y)  (+N = additional points)
--   flags:  P protected, M mouse-enabled, F forbidden, R region (layer:sublevel in col 6),
--           U forbidden-state unreadable (row gathered anyway, trust it less)
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

-- Degradation counters for the current map, reset by BuildMap and written into meta.
-- Silent degradation is the enemy: a map that quietly guesses is worse than one that
-- admits what it could not read.
local mapStats = { unreadableVis = 0, unknownForbidden = 0 }

-- safe() returns nil for BOTH "the read errored" and "the value was secret", but a
-- real `false` for a definite negative. That distinction carries the whole fix here:
-- 12.1's Forbidden Partition objects hand back a SECRET IsShown(), and the old code
-- folded that into "H" — recording a frame as definitely hidden when its visibility
-- is simply unknowable. Never launder an unreadable value into a definite answer.
local function visibility(obj)
    local visible = safe(obj.IsVisible, obj)
    if visible == true then return "V" end
    if visible == nil then
        mapStats.unreadableVis = mapStats.unreadableVis + 1
        return "?"
    end
    local shown = safe(obj.IsShown, obj)
    if shown == true then return "S" end
    if shown == nil then
        mapStats.unreadableVis = mapStats.unreadableVis + 1
        return "?"
    end
    return "H"
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
    local forbidden = safe(f.IsForbidden, f)
    if forbidden then
        return debugName(f) .. "|?|?|?|?|?|?|F"
    end
    local name = debugName(f)
    local otype = safe(f.GetObjectType, f) or "?"
    local parent = safe(f.GetParent, f)
    local parentName = parent and debugName(parent) or ""
    local vis = visibility(f)
    local w, h = safe(f.GetSize, f)
    local size = (w and h) and (round(w) .. "x" .. round(h)) or "?"
    local strata = safe(f.GetFrameStrata, f) or "?"
    local level = safe(f.GetFrameLevel, f) or "?"
    local flags = ""
    if safe(f.IsProtected, f) then flags = flags .. "P" end
    if safe(f.IsMouseEnabled, f) then flags = flags .. "M" end
    -- IsForbidden itself came back unreadable. Everything below is pcall-guarded so
    -- the row is still worth having, but the caller must know it is not trustworthy
    -- the way an ordinary row is.
    if forbidden == nil then
        mapStats.unknownForbidden = mapStats.unknownForbidden + 1
        flags = flags .. "U"
    end
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
    local vis = visibility(r)
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
    mapStats.unreadableVis, mapStats.unknownForbidden = 0, 0
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
            -- Degradation is reported, never hidden. A high unreadableVis on a build
            -- that used to report zero is the signal that a patch changed what the
            -- walker is allowed to see.
            unreadableVis = mapStats.unreadableVis,
            unknownForbidden = mapStats.unknownForbidden,
        },
        frames = lines,
    }
    msg(("Mapped %d frames (%d lines%s)."):format(
        frameCount, #lines, includeRegions and ", regions included" or ""))
    if mapStats.unreadableVis > 0 or mapStats.unknownForbidden > 0 then
        msg(("|cffff8800%d row(s) with unreadable visibility, %d with unknown forbidden state.|r"):format(
            mapStats.unreadableVis, mapStats.unknownForbidden))
    end
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
-- A forbidden global errors on access; a secret one must be reported AS secret
-- rather than scrubbed to nil, which would read as "does not exist".
local function apiTypeOf(ok, v)
    if not ok then return "forbidden" end
    if issecretvalue and issecretvalue(v) then return "secret" end
    return type(v)
end

-- Matches against the full dotted name, so "GetSpellCooldown" finds
-- C_Spell.GetSpellCooldown and "C_Spell" lists everything in that namespace.
-- One level deep only: C_Foo.Bar, never C_Foo.Bar.Baz.
local function sweepNamespace(results, nsName, ns, needle)
    for mk in pairs(ns) do
        if type(mk) == "string" then
            local full = nsName .. "." .. mk
            if full:lower():find(needle, 1, true) then
                local ok, v = pcall(indexGlobal, ns, mk)
                results[#results + 1] = full .. "|" .. apiTypeOf(ok, v)
            end
        end
    end
end

local function ApiProbe(pattern)
    if not pattern or pattern == "" then
        msg("Usage: /sko api <text>   (substring of an API name, case-insensitive)")
        chatLine("searches _G and one level into every C_* namespace table")
        return
    end
    local needle = pattern:lower()
    local results = {}
    local namespaces, unreadable = 0, {}

    for k in pairs(_G) do
        if type(k) == "string" then
            local nameMatches = k:lower():find(needle, 1, true)
            local isNamespace = k:find("^C_") ~= nil
            -- Only index what we actually need: matching names, plus every C_* table.
            -- Indexing all ~30k globals to find a few hundred namespaces is waste.
            if nameMatches or isNamespace then
                local ok, v = pcall(indexGlobal, _G, k)
                if nameMatches then
                    results[#results + 1] = k .. "|" .. apiTypeOf(ok, v)
                end
                -- Blizzard has spent years moving the API surface out of _G and into
                -- C_* tables. A sweep seeing only _G's own keys reports count = 0 for
                -- half the modern API, which reads as "this API is gone" — the exact
                -- wrong conclusion. GetSpellCooldown vs C_Spell.GetSpellCooldown is
                -- the case that caught this on 2026-07-28.
                if isNamespace and ok and type(v) == "table"
                    and not (issecretvalue and issecretvalue(v)) then
                    namespaces = namespaces + 1
                    -- Kept OUT of results deliberately: an unreadable namespace is a
                    -- gap in coverage, not a match. Counting it as one would break the
                    -- "count = 0 means genuinely absent" property this sweep exists for.
                    if not pcall(sweepNamespace, results, k, v, needle) then
                        unreadable[#unreadable + 1] = k
                    end
                end
            end
        end
    end
    table.sort(results)
    table.insert(SkoposDB.api, {
        time = date("%Y-%m-%d %H:%M:%S"),
        build = select(4, GetBuildInfo()),
        query = pattern,
        count = #results,
        -- Recorded so a future reader can tell a zero-result sweep actually looked
        -- inside the namespaces, rather than being the old _G-only blind spot.
        deep = true,
        namespaces = namespaces,
        unreadable = unreadable,
        results = results,
    })
    msg(("%d match(es) for '%s' — searched _G + %d C_* namespace(s):"):format(
        #results, pattern, namespaces))
    for i = 1, math.min(#results, 30) do chatLine(results[i]) end
    if #unreadable > 0 then
        msg(("|cffff8800%d namespace(s) could not be read|r: %s — a match could be hiding in there."):format(
            #unreadable, table.concat(unreadable, ", ")))
    end
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

-- There is NO "enumerate all attributes" call in the WoW API. GetAttribute answers
-- one key at a time, so this probes a known list and is therefore a best-effort dump,
-- never a complete one. An attribute missing from the output may simply be a key
-- nobody thought to list — which is why the output says so, and why explicit keys can
-- be passed to test anything outside the list.
local ATTR_KEYS = {}
do
    local function add(t) for _, k in ipairs(t) do ATTR_KEYS[#ATTR_KEYS + 1] = k end end
    -- SecureActionButtonTemplate: what a click actually does.
    add({ "type", "unit", "action", "spell", "item", "macro", "macrotext", "target",
          "toy", "flyout", "pet", "extra", "cancelaura", "index", "totem-slot",
          "target-slot", "useparent-unit", "unitsuffix", "toggleForVehicle",
          "allowVehicleTarget", "checkfocuscast", "checkselfcast", "harmbutton",
          "helpbutton", "pressAndHoldAction", "ping-receiver", "typerelease" })
    -- Numbered and modifier variants — a right-click cancelaura lives in type2.
    for _, k in ipairs({ "type", "unit", "spell", "macrotext", "action" }) do
        for i = 1, 5 do ATTR_KEYS[#ATTR_KEYS + 1] = k .. i end
        for _, m in ipairs({ "shift-", "ctrl-", "alt-", "*" }) do
            ATTR_KEYS[#ATTR_KEYS + 1] = m .. k .. "1"
            ATTR_KEYS[#ATTR_KEYS + 1] = m .. k .. "2"
        end
    end
    -- SecureGroupHeaderTemplate: how a raid/party header lays itself out.
    add({ "showRaid", "showParty", "showPlayer", "showSolo", "groupFilter",
          "roleFilter", "strictFiltering", "point", "xOffset", "yOffset",
          "columnSpacing", "columnAnchorPoint", "maxColumns", "unitsPerColumn",
          "startingIndex", "sortMethod", "sortDir", "template", "templateType",
          "groupBy", "groupingOrder", "nameList", "useOwnerUnit", "filterOnPet",
          "initialConfigFunction" })
    -- Secure snippets: the restricted-environment code itself. These are the whole
    -- reason this command is worth having — combat lockdown does not apply inside
    -- them, so this is where an in-combat cancelaura implementation actually lives.
    add({ "_onshow", "_onhide", "_onclick", "_onmousedown", "_onmouseup", "_onenter",
          "_onleave", "_onattributechanged", "_onstate-unit", "_childupdate",
          "_childupdate-unit", "_onreceivedrag", "_ondragstart" })
    add({ "oUF-guessUnit", "oUF-headerType", "oUF-onlyProcessChildren" })
end

local function AttrProbe(input)
    if not input or input == "" then
        msg("Usage: /sko attr <frame> [key ...]")
        chatLine("no keys = probe the built-in list; keys given = probe only those")
        chatLine(("built-in list is %d keys — see the caveat in HANDOFF.md"):format(#ATTR_KEYS))
        return
    end
    local name, rest = input:match("^(%S+)%s*(.-)%s*$")
    local frame, err = resolvePath(name)
    if not frame then
        msg(("Cannot resolve '%s': %s"):format(name, err))
        return
    end
    if type(frame) ~= "table" then
        msg(("'%s' is a %s, not a frame."):format(name, type(frame)))
        return
    end
    local okG, getAttr = pcall(indexGlobal, frame, "GetAttribute")
    if not okG or type(getAttr) ~= "function" then
        msg(("'%s' has no GetAttribute — not a Frame."):format(name))
        return
    end

    local keys, explicit = ATTR_KEYS, false
    if rest ~= "" then
        keys, explicit = {}, true
        for w in rest:gmatch("%S+") do keys[#keys + 1] = w end
    end

    local lines = {}
    for _, key in ipairs(keys) do
        local ok, v = pcall(getAttr, frame, key)
        -- type(v) rather than v ~= nil: never compare a value that might be secret.
        if ok and type(v) ~= "nil" then
            local isSecret = (issecretvalue and issecretvalue(v)) and true or false
            -- Snippet bodies ARE the payload worth reading; give them real room.
            local cap = key:sub(1, 1) == "_" and 1000 or 120
            lines[#lines + 1] = table.concat({ key, type(v),
                isSecret and "SECRET" or "plain",
                isSecret and "<secret>" or renderValue(v, cap) }, "|")
        elseif not ok then
            lines[#lines + 1] = key .. "|?|errored|<read failed>"
        end
    end

    local fname = debugName(frame)
    table.insert(SkoposDB.attrs, {
        time = date("%Y-%m-%d %H:%M:%S"),
        build = select(4, GetBuildInfo()),
        query = input,
        frame = fname,
        objectType = safe(frame.GetObjectType, frame) or "?",
        protected = safe(frame.IsProtected, frame) and true or false,
        -- Recorded so a reader can weigh an empty result: 0 found out of 3 explicit
        -- keys means something very different from 0 out of the whole built-in list.
        probed = #keys,
        explicitKeys = explicit,
        found = #lines,
        attrs = lines,
    })

    msg(("%s (%s) — %d attribute(s) set, %d key(s) probed:"):format(
        fname, safe(frame.GetObjectType, frame) or "?", #lines, #keys))
    for i = 1, math.min(#lines, 30) do
        local line = lines[i]
        chatLine(#line > 140 and (line:sub(1, 140) .. "…") or line)
    end
    if #lines > 30 then
        msg(("...%d more not shown — |cffffcc00/reload|r and read SkoposDB.attrs."):format(#lines - 30))
    end
    if not explicit then
        chatLine("|cff888888absence is NOT proof: no enumerate-attributes API exists, so")
        chatLine("|cff888888this checks a known list only. /sko attr <frame> <key> to test one.|r")
    end
    msg(("Saved as attr probe #%d. |cffffcc00/reload|r to flush to disk."):format(#SkoposDB.attrs))
end

-- Records the shape of an event's payload on its FIRST sighting only. Doing this on
-- every firing would be the expensive part of a sniff — COMBAT_LOG_EVENT_UNFILTERED
-- alone can fire hundreds of times a second — while counting is just an increment.
local function describeArgs(...)
    local n = select("#", ...)
    if n == 0 then return "" end
    local parts = {}
    for i = 1, math.min(n, 6) do
        local v = select(i, ...)
        if issecretvalue and issecretvalue(v) then
            parts[#parts + 1] = "secret"
        else
            local t = type(v)
            if t == "string" or t == "number" or t == "boolean" then
                parts[#parts + 1] = t .. ":" .. renderValue(v, 24)
            else
                parts[#parts + 1] = t
            end
        end
    end
    if n > 6 then parts[#parts + 1] = ("+%d more"):format(n - 6) end
    return table.concat(parts, ",")
end

local sniffFrame, sniffActive

-- The map answers "which frame", /sko api "does it exist", /sko secret "can I do
-- maths on it". This answers the fourth question no static inspection can: "what
-- should I hook?" RegisterAllEvents for a window, then report what actually fired.
local function EventSniff(seconds)
    if sniffActive then
        msg("A sniff is already running — let it finish first.")
        return
    end
    local dur = tonumber(seconds) or 5
    -- Clamped deliberately: this registers EVERY event, so a mistyped 600 would leave
    -- the firehose open for ten minutes.
    if dur < 1 then dur = 1 elseif dur > 30 then dur = 30 end

    sniffFrame = sniffFrame or CreateFrame("Frame")
    local counts, order, args, total = {}, {}, {}, 0

    sniffFrame:SetScript("OnEvent", function(_, event, ...)
        total = total + 1
        if not counts[event] then
            counts[event] = 0
            order[#order + 1] = event
            args[event] = describeArgs(...)
        end
        counts[event] = counts[event] + 1
    end)
    sniffFrame:RegisterAllEvents()
    sniffActive = true
    msg(("Sniffing ALL events for %d second(s) — go do the thing you want to trace."):format(dur))

    C_Timer.After(dur, function()
        sniffFrame:UnregisterAllEvents()
        sniffFrame:SetScript("OnEvent", nil)
        sniffActive = false

        -- Frequency order, not alphabetical: "what fired most" is the question being
        -- asked, and the one-shot event you are hunting is usually at the bottom.
        table.sort(order, function(a, b)
            if counts[a] ~= counts[b] then return counts[a] > counts[b] end
            return a < b
        end)

        local lines = {}
        for i, event in ipairs(order) do
            lines[i] = table.concat({ event, counts[event], args[event] or "" }, "|")
        end

        table.insert(SkoposDB.events, {
            time = date("%Y-%m-%d %H:%M:%S"),
            build = select(4, GetBuildInfo()),
            seconds = dur,
            inCombat = InCombatLockdown() and true or false,
            distinct = #order,
            total = total,
            events = lines,
        })

        msg(("%d distinct event(s), %d firing(s) in %ds:"):format(#order, total, dur))
        for i = 1, math.min(#lines, 30) do chatLine(lines[i]) end
        if #lines > 30 then
            msg(("...%d more not shown — |cffffcc00/reload|r and read SkoposDB.events."):format(#lines - 30))
        end
        msg(("Saved as event sniff #%d. |cffffcc00/reload|r to flush to disk."):format(#SkoposDB.events))
    end)
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
    chatLine("/sko api <txt>  search _G + C_* namespaces — does this API exist?")
    chatLine("/sko secret <api> [args]  does it return a SECRET? (works in combat)")
    chatLine("/sko attr <frame> [key]   secure attributes + snippets on a frame")
    chatLine("/sko events [sec]  what events fire in a window? (default 5s, max 30)")
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
    elseif cmd == "attr" then
        AttrProbe(rest)
    elseif cmd == "events" then
        EventSniff(rest)
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
    SkoposDB.attrs = SkoposDB.attrs or {}
    SkoposDB.events = SkoposDB.events or {}
    msg("v" .. VERSION .. " loaded. /sko for commands.")
end)
