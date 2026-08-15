# Skopos — parking lot

Deferred items. Nothing here is in flight. Each entry should be actionable without
the conversation that produced it.

---

## 1. RESOLVED 2026-08-11 (2nd time) — 12.1 map taken, and it validated v1.6.0

Re-mapped on the live 12.1 client and verified from the file, not from report:
`meta.build = 120100`, `meta.version = 1.6.0`, `when = 2026-08-11 22:05:40`,
45,437 frames (up from 26,893 — Blizzard's new aura trees account for most of it).

**`unreadableVis = 16080`** — non-zero for the first time ever, and 35% of the map.
Every one of those rows would have been silently recorded `H` by the pre-1.6.0 walker.
`unknownForbidden = 0`, so `IsForbidden` itself still reads cleanly.

Vis distribution: `S` 17,151 · `?` 16,080 · `H` 11,257 · `V` 949.

See HANDOFF's "12.1 walker secrecy guards" section for what 12.1 actually changed —
notably that the predicted object types do **not** exist, and that secrecy is per-API
(only 36 of the 16,080 also had secret geometry).

The original 2026-08-07 entry is kept below as 1a.

<details><summary>Original reopening note, superseded the same day</summary>

## 1b. REOPENED 2026-08-11 — the map is a PATCH behind, not just days

12.1 went live 2026-08-11 (client build 69189; see `Projects\WoW\12.1-LAUNCH-DATA.md`).
The map on disk is stamped `2026-08-07 21:21:28`, `build = 120007` — that is 12.0.7,
i.e. the previous patch. Object-type census confirms it: no `ManagedAuraContainer` and
no `VectorGraphics` anywhere in its 26,893 rows.

This is worse than ordinary staleness. Frame names survive a content patch; **object
types and secrecy behaviour do not**, and v1.6.0's whole point is recording secrecy
the walker previously laundered. Until a 12.1 map exists, every `H` in the current map
is unverifiable — under 12.0.7 rules a secret `IsShown()` was silently written as `H`.

**To resolve:** `/sko map` + `/reload` on the live 12.1 client. Three things confirm it:
`meta.build` should read `120100`, `meta.unreadableVis` should be **non-zero for the
first time ever**, and `ManagedAuraContainer` should appear in the object-type census
off Blizzard's own Target Frame.

⚠ Those two object-type names come from the Sniffer relay only — `12.1-LAUNCH-DATA.md`
does **not** corroborate them. v1.6.0's guards are type-agnostic so nothing depends on
the names being right, but do not treat them as verified until a live map shows them.

The resolution below stands as the record of the 2026-08-07 re-map; it was correct then.

</details>

---

## 1a. RESOLVED (2026-08-07) — the map on disk was from 2026-07-24, not fresh

**Found:** 2026-07-28, while catching up after a chat was deleted.

`WTF\Account\RYRIN\SavedVariables\Skopos.lua` has a file mtime of 2026-07-27 22:21,
but the map *inside* it is stamped `meta.when = "2026-07-24 23:15:24"`, and all five
`/sko grab` picks are from 23:18–23:26 that same night. The 07-27 write was a logout
flush re-serializing unchanged data — **no new `/sko map` has landed since the 24th.**

Consequence: the map predates the 07-26 repo move and anything that changed in the
addon setup since. 28,854 frames is still a lot of real data, so this may not matter —
but don't assume it reflects today's UI.

Side note: `meta.version` read `1.0.0` while the `.toc` said `1.0.1`. Not a bug — the
map was taken at 23:15 and the version bump committed at 23:16, so the stamp was
honest about the build that produced it.

**Resolved 2026-08-07.** Marshall re-mapped and reloaded; verified against the live
SavedVariables rather than taken on report:

| | old map | current map |
|---|---|---|
| `meta.when` | 2026-07-24 23:15:24 | **2026-08-07 21:21:28** |
| `meta.version` | 1.0.0 | **1.4.0** |
| frames | 28,854 | 26,893 |
| visible (`V`) | 992 | 1,019 |
| forbidden (`F`) | 0 | 0 |
| secret-degraded (`?` size) | 23 | 27 |

⚠ The new map has **~1,900 fewer frames** than the old one. That is expected, not a
truncated map: frames are created lazily, so a session where fewer panels have been
opened enumerates fewer of them. It does mean a map is a snapshot of *what has been
opened*, not of everything that could exist — if a Blizzard frame you expect is
missing, open its panel once and re-map before concluding it is gone.

The append-only `api`, `secret` and `attrs` logs all survived the re-map intact;
`/sko map` replaces `SkoposDB.map` only.

**Lesson worth keeping:** this item sat open through three sessions, and twice a
re-map was reported as done when the file showed otherwise — the giveaway both times
was `meta.when` being unchanged while the file mtime moved, which is a logout flush
re-serializing old data. Always check `meta.when`, never the file timestamp.

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

**Researched 2026-08-04.** Ranked by value. API existence was verified by counting
real usage across the 131 addons installed at `Interface\AddOns` — if oUF or Dominos
calls it, it exists at build `120007`. Counts are that evidence, not guesses.

Follows the pattern `/sko api` and `/sko secret` established: capture to an
append-only `SkoposDB.<name>` log, render values as pipe-delimited strings, flush on
`/reload`, never store a raw value.

| Command | Answers | API evidence |
|---|---|---|
| ~~`/sko attr <frame>`~~ | ✅ **BUILT v1.4.0 · `@last` v1.7.0 · LIVE-VERIFIED 2026-08-11** | — |
| `/sko scripts <frame>` | Which handlers are set. `OnUpdate` = perf smell, `OnClick` = interactive | `GetScript` 120, `HasScript` 6 |
| ~~`/sko events <sec>`~~ | ✅ **BUILT v1.5.0 · LIVE-VERIFIED 2026-08-11** | — |
| `/sko addons` | Name/version/enabled/LoD/memory. Explains frame provenance: who made `DetailsBarra_1_5` | `C_AddOns.GetAddOnMetadata` 61 |
| ~~`/sko cvar <pattern>`~~ | ✅ **BUILT 2026-08-15, v1.8.0** | — |

✅ **`/sko attr` shipped in v1.4.0.** The keyspace problem was real and is handled the
way this note anticipated: 133 known keys probed, the output states plainly that
absence is not proof, and explicit keys can be passed to test anything off the list.
`probed` / `explicitKeys` are recorded so an empty result can be read correctly.
Snippet bodies get a 1000-char cap against 120 for ordinary values, since the snippet
is the actual payload worth reading.

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

**Found 2026-08-04, the hard way**, reading back the 2026-07-28 probe data.
`/sko api GetSpellCooldown` had returned `count = 0`
at build `120007`, which reads as "this API is gone" and is *not* what it means —
`/sko api` sweeps `_G`'s own keys and never looks inside namespace tables, so
`C_Spell.GetSpellCooldown` could never have appeared. The limitation is now documented
in HANDOFF.md, but documentation is a workaround, not a fix.

This bites hardest on exactly the APIs most worth asking about, since Blizzard has
spent years migrating globals into `C_*` tables. A sweep that silently cannot see the
modern half of the API surface is a sharp edge on the tool's primary use.

**Resolved 2026-08-04 in v1.3.0.** Default-on, as suspected — no `deep` flag, because
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

## 6. Investigate the `C_Secrets` namespace

**Found 2026-08-11**, incidentally, in the first live `/sko api` sweep on 12.1:

```
C_Secrets.GetSpellCooldownSecrecy|function
C_Spell.GetSpellCooldownDuration|function
C_Spell.GetSpellCooldown|function
```

12.1 ships a `C_Secrets` namespace, and at least one of its functions reports **whether
a value is secret** rather than requiring you to call an API and inspect what comes back
— which is exactly how `/sko secret` works today.

This matters because the empirical approach has a real blind spot: it can only report
secrecy for the specific call and context it just made. The 12.1 map showed secrecy is
marked **per API** (only 36 of 16,080 unreadable-visibility rows also had secret
geometry), so one probe genuinely tells you nothing about the next. A direct query would
replace inference with fact.

**The namespace is already documented — and by Marshall.**
`Projects\WoW\WoW-Midnight-Addon-Dev-KnowledgeBase.md` §2.3 lists the family:

```
C_Secrets.HasSecretRestrictions, ShouldUnitHealthMaxBeSecret,
ShouldUnitPowerBeSecret, ShouldCooldownsBeSecret, ShouldAurasBeSecret,
ShouldUnitComparisonBeSecret, ShouldUnitIdentityBeSecret, GetPowerTypeSecrecy
```

So the caveat an earlier draft of this item carried — "the one function observed is
spell-cooldown-specific, it may be a narrow helper" — was wrong. It is a **general
policy family**, and it is in normal use: Platynator and Coolinator gate on it,
MythicDungeonTools uses `ShouldAurasBeSecret`, oUF uses `CanCompareUnitTokens`, and
Krito's own `Probe.lua` already probes three of these.

**To resolve:** `/sko api C_Secrets` still confirms what this build actually exposes
(the KB is research, the sweep is ground truth). Then decide whether `/sko secret`
consults it — most likely reporting both the policy answer and the empirical one, and
flagging any disagreement, since the two answer subtly different questions.

⚠ **Cite the right knowledge base — there are two and they have diverged.**
`Projects\WoW\WoW-Midnight-Addon-Dev-KnowledgeBase.md` (59 KB, current through
2026-08-11) is the live one. `AbilityMap\_project\knowledge\` holds a 44 KB snapshot
frozen 2026-07-19 that is missing the 12.1 aura directionality policy, the widened
identity-secret list and the Lua-error behaviour of secret aura reads — a chat reading
it will draw 12.1 conclusions from pre-12.1 material. An earlier version of this item
cited the stale one.

⚠ **Wider lesson, worth more than the feature:** several sessions went into measuring
secrecy empirically when `ShouldUnitPowerBeSecret` and `GetPowerTypeSecrecy` were sitting
in Marshall's own knowledge base the whole time. Read that doc before designing a probe.
Recorded as the `midnight-secrets-knowledge-base` memory so every chat picks it up.

---

## Already recorded elsewhere — don't duplicate here

HANDOFF.md's "Ideas / not built" section already holds the feature backlog
(`/sko diff`, hover-highlight overlay during grab countdown, per-addon attribution
by name prefix). Those live there; this file is for findings and loose ends.
