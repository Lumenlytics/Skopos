# Skopos — handoff

Frame cartographer. Exists to solve one problem: "which frame do I edit?" It dumps
the entire live UI frame tree to SavedVariables so Claude can grep it from disk,
and grabs the frame stack under the mouse so Marshall can point at a thing on
screen and get its exact name and ancestry.

## Status

- v1.0.1 **FULLY VERIFIED in-game** 2026-07-24: map = 28,854 frames, 4.9 MB, zero
  forbidden stubs, and 23 secret-degraded rows (0.08%) — mostly healing-prediction
  StatusBars (`Health.HealAbsorb`, `Health.HealingAll`) plus a few paged-content
  containers. Those are `safe()` doing its job, degrading to `?` rather than
  detonating on a secret read, not a defect. `/sko grab` verified on a real UI
  element (PaperDollSidebarTab2 with full ancestry to UIParent). Note: hovering
  open world grabs an anonymous protected WorldFrame overlay — that's expected.
- v1.0.0 lesson: secret numbers survive pcall and only detonate on later
  arithmetic — `GetSize` returns secrets on secret-marked widgets even out of
  combat. Everything is scrubbed with `issecretvalue` at the `safe()` boundary now.

## The workflow this enables

1. Marshall runs `/sko map` (or `/sko map full` for textures/fontstrings too), then `/reload`.
2. Claude reads/greps `C:\Games\World of Warcraft\_retail_\WTF\Account\RYRIN\SavedVariables\Skopos.lua`.
3. For "what IS this thing on my screen": `/sko grab 3`, hover the element during the
   countdown, read the printed stack + ancestry. `/sko note <text>` annotates it,
   `/reload` persists it for Claude.
4. For "does this API exist in this build": `/sko api <text>`, then `/reload`. The map
   covers widgets only — a function name will never appear in it, because
   `EnumerateFrames` walks frames and globals are not frames. This is the other half.
5. For "what should I hook": `/sko events [sec]`, then do the thing you want to trace
   during the window, then `/reload`. No static inspection can answer this — it is the
   only command here that observes behaviour over time rather than state at an instant.
6. For "how is this secure frame wired": `/sko attr <frame> [key ...]`, then `/reload`.
   Dumps click types, unit bindings, header layout keys and — most usefully — the
   secure snippet bodies, which is how to *study* a working in-combat implementation
   instead of guessing at one.
7. For "can I do maths on what it returns": `/sko secret <API> [args]`, then `/reload`.
   Existence is rarely the real question on Midnight — secrecy is, because it decides
   whether a feature is cheap or needs an engine-side workaround. Run each probe
   **twice, in and out of combat**, since that is frequently where the answer changes.

Remember: SavedVariables only flush on `/reload` or logout. A map taken without a
reload afterward is invisible to Claude.

## Data format

`SkoposDB.map.frames` is a flat array of pipe-delimited strings, one per widget:

```
debugName|objectType|parentDebugName|vis|WxH|strata:level|anchor|flags
```

- `vis`: `V` visible, `S` shown but an ancestor is hidden, `H` hidden,
  **`?` visibility unreadable — secret or errored. NOT the same as hidden.**
- `anchor`: `POINT->RelativeName:RELPOINT(x,y)`, `+N` = N more anchor points
- `flags`: `P` protected, `M` mouse-enabled, `F` forbidden (row is otherwise `?`s),
  `R` region row (col 6 is then drawLayer:sublevel, col 7 is atlas/tex/text),
  `U` forbidden state unreadable — the row was gathered anyway (everything is
  pcall-guarded) but trust it less than an ordinary row

## 12.1 walker secrecy guards (v1.6.0)

12.1 ships Forbidden Partition objects: `AuraButton`s whose `IsShown()` returns a
**secret**, plus new object types (`ManagedAuraContainer`, `VectorGraphics`). Blizzard's
own Target Frame runs a `ManagedAuraContainer`, so even mapping the default UI
exercises these paths.

Skopos never risked *crashing* on them — every widget read has gone through `safe()`
since v1.0.1. The actual defect was quieter and worse:

```lua
-- before v1.6.0
if safe(f.IsVisible, f) then vis = "V"
elseif safe(f.IsShown, f) then vis = "S"
else vis = "H" end
```

`safe()` scrubs a secret to `nil`, so a secret `IsShown()` fell through to **`H`** —
recording the frame as *definitely hidden*, indistinguishable from a genuine hide. The
map didn't fail; it lied, and nothing in the output said so.

The fix rests on a distinction `safe()` already preserved but the old code discarded:
it returns `nil` for "errored or secret" but a real `false` for a definite negative.
`visibility()` now checks for `nil` explicitly and emits `?`, and **only ever reports a
definite answer when it actually got one**.

`meta.unreadableVis` and `meta.unknownForbidden` count the degraded rows, and `/sko map`
prints them when non-zero. A build that used to report zero and suddenly doesn't is the
signal that a patch changed what the walker is allowed to see — which is precisely how
this class of problem should announce itself, rather than by silently mislabelling rows.

`SkoposDB.map.meta` has timestamp, client build, resolution, UI scale, counts, and
this format string. `SkoposDB.picks` is an array of grabs: `{time, stack, ancestry, note?}`.

`SkoposDB.events` (v1.5.0+) is an append-only log of `/sko events` sniffs:
`{time, build, seconds, inCombat, distinct, total, events}`, where `events` is an
array of `EVENT_NAME|count|argSignature` strings **sorted by count descending**.
Frequency order is deliberate — the one-shot event you are hunting is usually at the
bottom, under the noise.

The arg signature is captured on an event's **first sighting only** (`string:player,
number:6552`, or `secret` for a secret-marked arg, capped at 6 args). Capturing every
firing would be the expensive part; counting is just an increment, and
`COMBAT_LOG_EVENT_UNFILTERED` alone can fire hundreds of times a second.

Duration defaults to 5s and is **clamped to 1–30**, because this calls
`RegisterAllEvents` — a mistyped `600` would otherwise hold the firehose open for ten
minutes. Only one sniff runs at a time; a second call while one is live is refused.
An empty result is still recorded: "nothing fired in that window" is a real answer.

`SkoposDB.attrs` (v1.4.0+) is an append-only log of `/sko attr` dumps:
`{time, build, query, frame, objectType, protected, probed, explicitKeys, found, attrs}`,
where `attrs` is an array of `key|luaType|SECRET-or-plain|value` strings. A key whose
read errored is recorded as `key|?|errored|<read failed>` rather than dropped.

⚠ **This is a best-effort dump, NOT a complete one.** There is no enumerate-attributes
call in the WoW API — `GetAttribute` answers one key at a time — so the command probes
a built-in list of 133 known keys (SecureActionButton types and their modifier/numeric
variants, SecureGroupHeader layout keys, secure snippets, oUF conventions). **An
attribute absent from the output may simply be a key nobody thought to list.** Pass
explicit keys to test anything outside it: `/sko attr <frame> <key> [key...]`.

`probed` and `explicitKeys` exist to make an empty result readable: 0 found from 3
explicit keys means something very different from 0 found across the whole list.

⚠ **Virtual XML templates are invisible to every live-frame command here** — `attr`,
`find`, `grab` and `map` alike. A `<Button virtual="true">` is a template, not an
object: it never exists at runtime, and instances spawned from it are usually
anonymous. Worked example, 2026-08-05: `/sko find QuickMenu` returned 0 while hunting
ConsolePort's in-combat cancel-aura button, because the button is
`<Button name="CPQMenuAura" ... virtual="true">` in
`ConsolePort_World\View\QuickMenu\QuickMenu.xml`. **When a frame you can see in an
addon's source does not appear here, check whether it is virtual before assuming the
addon is unloaded** — and read the XML directly, which carries the attribute values
anyway. (The parent addon being unloaded is the other cause; check both.)

Secure snippet values (`_onclick`, `_onshow`, …) are stored up to 1000 chars rather
than the 120 ordinary values get, because the snippet body *is* the payload worth
reading — combat lockdown does not apply inside the restricted environment, so that
is where an in-combat implementation actually lives. Chat truncates at 140; read the
full text from disk.

`SkoposDB.secret` (v1.2.0+) is an append-only log of `/sko secret` probes:
`{time, build, query, inCombat, anySecret, errored, returns}`, where `returns` is an
array of `index|luaType|SECRET-or-plain|renderedValue` strings. Secret values are
recorded as the literal `<secret>` and **never** stored raw — a secret written into
SavedVariables would either fail to serialise or poison whatever reads it back.

`inCombat` is load-bearing, not trivia: many values are secret **only** in combat, so
a probe result is meaningless without knowing which state produced it. Unlike
`/sko map`, this command deliberately runs in combat for exactly that reason — to
answer "is this secret?" you usually need both readings of the same API.

`SkoposDB.api` (v1.1.0+) is an append-only log of `/sko api` sweeps:
`{time, build, query, count, results}`, where `results` is a sorted array of
`globalName|type` strings. `type` is the Lua type, or `forbidden` (access errored)
or `secret` (secret-marked). Append-only means several probes can be run in one
session and read after a single `/reload`. Note `/sko clear` wipes `picks` only —
it deliberately leaves the api log alone.

**As of v1.3.0 the sweep also descends one level into every `C_*` namespace table**,
matching against the full dotted name. So `/sko api GetSpellCooldown` finds
`C_Spell.GetSpellCooldown|function`, and `/sko api C_Spell` lists that whole
namespace. One level only — `C_Foo.Bar`, never `C_Foo.Bar.Baz`.

This mattered because Blizzard has spent years moving the API surface out of `_G`
into `C_*` tables. Before 1.3.0 the sweep saw only `_G`'s own keys, so half the modern
API reported `count = 0`, which reads as "this API is gone" — the exact wrong
conclusion. `GetSpellCooldown` is the case that caught it on 2026-07-28: the global
really is absent at `120007`, but the namespaced form exists.

Two fields make a zero-result sweep trustworthy: `deep = true` confirms namespaces
were searched at all, and `namespaces` records how many. **`unreadable` is the one to
check** — namespaces whose iteration errored, listed separately and deliberately kept
OUT of `results`, because counting a coverage gap as a match would destroy the
"`count = 0` means genuinely absent" property the descent exists to provide. If
`unreadable` is non-empty, a match could be hiding in there.

`/sko secret <dotted.path>` remains the way to confirm a specific call, since it
resolves a path segment at a time and reports which segment is missing.

## Design constraints (Midnight KB)

- Every widget read is pcall-guarded (`safe()`): secret-marked frames error on
  geometry reads, forbidden frames error on nearly everything.
- Forbidden frames are recorded name-only with flag `F`.
- `/sko map` refuses in combat (geometry goes secret; the map would be swiss cheese).
- Uses `GetMouseFoci()` (12.x) with a `GetMouseFocus` fallback; `EnumerateFrames()`
  with a UIParent/WorldFrame recursive-walk fallback if it ever disappears.

## Ideas / not built

- `/sko diff` — map twice, show frames created between (find what an addon just made).
- Highlight-on-hover overlay during grab countdown (fstack-style outline).
- Per-addon attribution by name-prefix heuristics.
