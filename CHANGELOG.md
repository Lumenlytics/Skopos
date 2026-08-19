# Changelog

All notable changes to Skopos. Newest first.

Skopos has never been released; every version below shipped only to the local
AddOns folder via `deploy.ps1`. Releases are Publisher's lane — this file exists
so `publish.ps1` preflight has an entry to match `## Version` against.

## 1.12.0

- `/sko secret` records `zone` and `instanceType` (`IsInInstance`) per probe and prints
  them. Secret restrictions apply on restricted MAPS as well as in combat
  (`SecretOnRestrictedMaps`), so an out-of-combat SECRET inside an instance is expected;
  without the zone recorded that reads as an anomaly.

## 1.11.0

- `/sko secret` records `restrictions` — `C_Secrets.HasSecretRestrictions()` — next to
  `inCombat`, and prints it. Combat is not what gates secrecy: `UnitPower player` returns
  SECRET with `inCombat = false`. (The changelog entry here originally cited a plain→SECRET
  flip between two probes; that was a misreading of the log — they were different queries.
  The fix is right, the reason given for it was not.)

## 1.10.0

- `/sko secret` now reports the `C_Secrets` policy answer alongside the empirical
  probe and flags disagreement between them. The probe says what one call returned
  in one context; the policy says what the rule is. A disagreement is never
  reconciled silently. The policy call receives the same arguments as the probe.
- Fixed: colour codes passed to `chatLine` rendered literally as `||cff888888…`,
  because `chatLine` escapes pipes by design. Four call sites; the `/sko events`
  reload warning moved to `msg()`, which does not escape.

## 1.9.0

- `/sko addons` — installed addon inventory: version, memory, load state, sorted
  heaviest-first. Answers "who made this frame?", which the map raises and cannot
  settle.
- Memory figures are optional: Details replaces the global `UpdateAddOnMemoryUsage`,
  so it is pcall'd and every row reports `?` if it fails.
- Dropped the pre-`C_AddOns` fallbacks rather than whitelist five removed globals
  for luacheck, which would have blunted the check that catches Midnight renames.

## 1.8.0

- `/sko cvar` — CVar sweep, changed-from-default first. Console commands are told
  from variables by `GetCVarInfo` returning nothing, not by a `commandType` enum.

## 1.7.0

- `/sko attr @last` targets the frame from the most recent `/sko grab`. Aura leaf
  buttons in 12.1 are anonymous, so hovering is the only handle on them.
- `/sko events` warns not to `/reload` before the window closes; doing so discarded
  the whole run with no error.

## 1.6.0

- Walker secrecy guards for 12.1. A secret `IsShown()` was being folded into `H`
  ("definitely hidden"); visibility now reports `?` when it is genuinely unreadable.
  On the first 12.1 map that was 16,080 of 45,437 rows — 35% of the map had been a lie.
- New `U` flag for an unreadable forbidden state; `meta.unreadableVis` and
  `meta.unknownForbidden` count degraded rows so silent degradation is impossible.

## 1.5.0

- `/sko events` — register all events for a window and report what fired, sorted by
  count. Arg signatures captured on first sighting only.

## 1.4.0

- `/sko attr` — secure attributes and snippet bodies on a live frame. Probes a known
  133-key list, because no enumerate-attributes API exists; the output says so.

## 1.3.0

- `/sko api` descends one level into every `C_*` namespace. Before this, half the
  modern API reported `count = 0`, which reads as "this API is gone".

## 1.2.0

- `/sko secret` — call an API and report whether its returns are secret. Runs in
  combat deliberately, since many values are secret only there.

## 1.1.0

- `/sko api` — search `_G` for globals. Globals are not frames, so no amount of
  mapping will ever surface a function name.

## 1.0.1

- Scrub secret values at the `safe()` boundary. Secrets survive `pcall` and only
  detonate on later arithmetic.

## 1.0.0

- Initial: `/sko map`, `/sko grab`, `/sko find`, `/sko note`, `/sko clear`.
