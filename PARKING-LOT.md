# Skopos — parking lot

Deferred items. Nothing here is in flight. Each entry should be actionable without
the conversation that produced it.

---

## 1. The map on disk is from 2026-07-24, not fresh

**Found:** 2026-07-28, while catching up after a chat was deleted.

`WTF\Account\RYRIN\SavedVariables\Skopos.lua` has a file mtime of 2026-07-27 22:21,
but the map *inside* it is stamped `meta.when = "2026-07-24 23:15:24"`, and all five
`/sko grab` picks are from 23:18–23:26 that same night. The 07-27 write was a logout
flush re-serializing unchanged data — **no new `/sko map` has landed since the 24th.**

Consequence: the map predates the 07-26 repo move and anything that changed in the
addon setup since. 28,854 frames is still a lot of real data, so this may not matter —
but don't assume it reflects today's UI.

**To resolve:** `/sko map` (or `/sko map full`), then `/reload`. Confirm `meta.when`
shows the new date before trusting it.

Side note: `meta.version` reads `1.0.0` while the `.toc` says `1.0.1`. Not a bug —
the map was taken at 23:15 and the version bump committed at 23:16, so the stamp is
honest about the build that produced it. A re-map will stamp 1.0.1.

---

## 2. HANDOFF.md overstates the secret-scrub result

**Found:** 2026-07-28, verified by counting rows in the live SavedVariables.

HANDOFF.md's Status section claims "zero forbidden stubs, zero secret-degraded rows."
Forbidden is genuinely **0**. Secret-degraded is **23**, not zero — rows carrying `?`
in the size field and sometimes the anchor field:

```
Panoply_player.Health.HealAbsorb|StatusBar|Panoply_player.Health|V|?|LOW:4|?|
Panoply_player.Health.HealingAll|StatusBar|Panoply_player.Health|V|?|LOW:4|?|
oUF_PartyUnitButton1.Health.HealAbsorb|StatusBar|oUF_PartyUnitButton1.Health|V|?|LOW:5|?|
```

Mostly heal-absorb / healing-prediction StatusBars, which are secret-marked in Midnight,
plus a couple of paged-content containers.

**This is not a defect.** It's `safe()` working exactly as designed — degrading to `?`
instead of detonating on a secret read. 23 of 28,854 rows is 0.08%. The only thing wrong
is the doc line.

**To resolve:** reword that bullet in HANDOFF.md to "23 secret-degraded rows (0.08%),
all healing-prediction bars — the scrubber working as intended."

---

## 3. RESOLVED — Skopos exists to serve Panoply

**Raised:** 2026-07-28. **Answered by Marshall the same day.** The guess from frame
names (`Panoply_player.*`, `oUF_PartyUnitButton1.*`) was right: Panoply's unit frames
are the thread, and the recurring cost Skopos removes is "a lot of time spent figuring
out which frame we should be editing."

First real payoff, 2026-07-28 — two Panoply questions answered straight from the map,
no in-game testing needed:

- **Confirmed `Blizzard.lua`'s targets exist**: `CompactRaidFrameManager` and
  `CompactRaidFrameContainer` are both present at build `120007`. (The map covers
  frames, not globals, so `CompactRaidFrameManager_SetSetting` /
  `_UpdateShown` are still unverified.)
- **Supplied the anchor targets for Panoply's P4.9** cooldown-viewer integration:
  `WarminatorPrimaryGroupAnchor` (top-level Frame, 283.1x46.9), plus Blizzard's
  `EssentialCooldownViewer`, `UtilityCooldownViewer`, `BuffBarCooldownViewer` and
  `BuffIconCooldownViewer`. Recorded in `Projects\WoW\Panoply\PARKING-LOT.md`.

**Standing workflow:** before hunting for a Blizzard frame name for any addon, grep
the map first. Item 1 above still applies — re-map before trusting it for anything
that changed recently.

---

## Already recorded elsewhere — don't duplicate here

HANDOFF.md's "Ideas / not built" section already holds the feature backlog
(`/sko diff`, hover-highlight overlay during grab countdown, per-addon attribution
by name prefix). Those live there; this file is for findings and loose ends.
