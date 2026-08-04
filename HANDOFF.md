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
5. For "can I do maths on what it returns": `/sko secret <API> [args]`, then `/reload`.
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

- `vis`: `V` visible, `S` shown but an ancestor is hidden, `H` hidden
- `anchor`: `POINT->RelativeName:RELPOINT(x,y)`, `+N` = N more anchor points
- `flags`: `P` protected, `M` mouse-enabled, `F` forbidden (row is otherwise `?`s),
  `R` region row (col 6 is then drawLayer:sublevel, col 7 is atlas/tex/text)

`SkoposDB.map.meta` has timestamp, client build, resolution, UI scale, counts, and
this format string. `SkoposDB.picks` is an array of grabs: `{time, stack, ancestry, note?}`.

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
