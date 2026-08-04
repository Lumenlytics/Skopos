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

## 2. RESOLVED — HANDOFF.md overstated the secret-scrub result

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

**Resolved 2026-07-28.** HANDOFF.md's Status bullet now reads the real numbers. Counts
re-verified independently against the live SavedVariables before editing: 23 rows with
`?` in the size field, 0 rows carrying the `F` flag.

One correction to this note's own suggested wording — "all healing-prediction bars" was
not accurate. It is *mostly* `Health.HealAbsorb` / `Health.HealingAll` StatusBars, plus a
few paged-content containers (`WarbandSceneJournal.IconsFrame.Icons`,
`TransmogFrame…ItemsFrame.PagedContent`). HANDOFF says "mostly … plus a few".

---

## 3. RESOLVED — Skopos exists to serve Panoply

**Raised:** 2026-07-28. **Answered by Marshall the same day.** The guess from frame
names (`Panoply_player.*`, `oUF_PartyUnitButton1.*`) was right: Panoply's unit frames
are the thread, and the recurring cost Skopos removes is "a lot of time spent figuring
out which frame we should be editing."

First real payoff, 2026-07-28 — two Panoply questions answered straight from the map,
no in-game testing needed:

- **Confirmed `Blizzard.lua`'s targets exist**: `CompactRaidFrameManager` and
  `CompactRaidFrameContainer` are both present at build `120007`.
  **The function half is now confirmed too (2026-07-28, via `/sko api`, v1.2.0):**
  `CompactRaidFrameManager_SetSetting|function` and
  `CompactRaidFrameManager_UpdateShown|function` both exist — 51 matching globals in
  total. `Blizzard.lua` is **not** silently no-opping. Also available if useful:
  `_GetSetting`, `_GetSettingBeforeLoad`, `_Toggle`, `_UpdateContainerVisibility`.
- **Supplied the anchor targets for Panoply's P4.9** cooldown-viewer integration:
  `WarminatorPrimaryGroupAnchor` (top-level Frame, 283.1x46.9), plus Blizzard's
  `EssentialCooldownViewer`, `UtilityCooldownViewer`, `BuffBarCooldownViewer` and
  `BuffIconCooldownViewer`. Recorded in `Projects\WoW\Panoply\PARKING-LOT.md`.

**Standing workflow:** before hunting for a Blizzard frame name for any addon, grep
the map first. Item 1 above still applies — re-map before trusting it for anything
that changed recently.

---

## 4. Five researched-but-unbuilt commands

**Researched 2026-07-28.** Ranked by value. API existence was verified by counting
real usage across the 131 addons installed at `Interface\AddOns` — if oUF or Dominos
calls it, it exists at build `120007`. Counts are that evidence, not guesses.

Follows the pattern `/sko api` and `/sko secret` established: capture to an
append-only `SkoposDB.<name>` log, render values as pipe-delimited strings, flush on
`/reload`, never store a raw value.

| Command | Answers | API evidence |
|---|---|---|
| `/sko attr <frame>` | Secure attributes on a live frame. Serves P4.3 `destroytotem` and P4.8 header attrs, and lets you *study* a shipping in-combat `cancelaura` button instead of guessing | `GetAttribute` — **172 uses** |
| `/sko scripts <frame>` | Which handlers are set. `OnUpdate` = perf smell, `OnClick` = interactive | `GetScript` 120, `HasScript` 6 |
| `/sko events <sec>` | Sniff every event firing in a window — "what should I hook?" | `RegisterAllEvents` — **151 uses** |
| `/sko addons` | Name/version/enabled/LoD/memory. Explains frame provenance: who made `DetailsBarra_1_5` | `C_AddOns.GetAddOnMetadata` 61 |
| `/sko cvar <pattern>` | CVar sweep. Compact raid frame settings live here — directly relevant to Panoply's `Blizzard.lua` | `C_CVar.GetCVar` 35, `GetCVarInfo` 18 |

⚠ **`/sko attr` has a keyspace problem worth knowing before starting it.** There is no
"enumerate all attributes" call, so it must probe a known key list (`unit`, `type`,
`type1`/`type2`, `action`, `spell`, `macrotext`, oUF and secure-header conventions).
That makes it a best-effort dump, not a complete one — say so in its output rather
than letting a caller read absence as proof.

### Deliberately NOT worth building — don't rediscover these

- **Per-frame registered-event lists.** The obvious "show every event this frame
  listens to" has no public API: `GetRegisteredEvents` appears **zero times across all
  131 installed addons**. Only `IsEventRegistered(event)` exists (5 uses), which means
  probing a guessed list, not enumerating. Not worth an evening.
- **Reverse anchor lookup** ("what anchors *to* this frame?"). Already derivable — the
  map records every frame's anchor target, so it is a grep over data you already have.
  Don't add a command for a question the existing file answers.

Unverified either way: `GetRaidProfileOption` / `GetNumRaidProfiles` (0 local uses,
which is not proof of absence). `/sko api GetRaidProfile` now answers that itself.

---

## 5. RESOLVED — `/sko api` now descends into `C_*` namespaces

**Found 2026-07-28, the hard way.** `/sko api GetSpellCooldown` returned `count = 0`
at build `120007`, which reads as "this API is gone" and is *not* what it means —
`/sko api` sweeps `_G`'s own keys and never looks inside namespace tables, so
`C_Spell.GetSpellCooldown` could never have appeared. The limitation is now documented
in HANDOFF.md, but documentation is a workaround, not a fix.

This bites hardest on exactly the APIs most worth asking about, since Blizzard has
spent years migrating globals into `C_*` tables. A sweep that silently cannot see the
modern half of the API surface is a sharp edge on the tool's primary use.

**Resolved 2026-07-28 in v1.3.0.** Default-on, as suspected — no `deep` flag, because
the old default was quietly wrong and an opt-in fix leaves the trap armed. Matches
against the full dotted name, so `GetSpellCooldown` finds `C_Spell.GetSpellCooldown`
and `C_Spell` lists the namespace. Only C_* tables and name-matching keys get indexed,
so it does not pay to index all ~30k globals. Secret namespaces are skipped rather
than iterated.

Building it surfaced a second bug worth remembering: the first version appended an
`unreadable-namespace` marker into `results`, which meant every single sweep returned
at least one "match" — including genuinely-absent APIs. That destroyed the very
property the fix existed to create. Unreadable namespaces are now a separate
`unreadable` field, reported as a caveat rather than counted as a hit.

⚠ **Still one level deep only** (`C_Foo.Bar`, never `C_Foo.Bar.Baz`). No known case
needs deeper today; revisit if one appears.

---

## Already recorded elsewhere — don't duplicate here

HANDOFF.md's "Ideas / not built" section already holds the feature backlog
(`/sko diff`, hover-highlight overlay during grab countdown, per-addon attribution
by name prefix). Those live there; this file is for findings and loose ends.
