# Skopos — handoff

Frame cartographer. Exists to solve one problem: "which frame do I edit?" It dumps
the entire live UI frame tree to SavedVariables so Claude can grep it from disk,
and grabs the frame stack under the mouse so Marshall can point at a thing on
screen and get its exact name and ancestry.

## Status

- v1.0.1 **FULLY VERIFIED in-game** 2026-07-24: map = 28,854 frames, 4.9 MB, zero
  forbidden stubs, zero secret-degraded rows. `/sko grab` verified on a real UI
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
