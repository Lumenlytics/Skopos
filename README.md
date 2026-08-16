# Skopos

**Frame cartographer for World of Warcraft addon developers.** Skopos answers the
question every UI addon author hits first: *"which frame do I actually edit?"*

It dumps the entire live UI frame tree to SavedVariables so you can grep it from
disk, captures the frame stack under your mouse so you can point at a thing on
screen and get its exact name and ancestry, and — new for Midnight (12.x) — tells
you whether an API's return values are **secret** in the current context, so you
can find out what your addon is allowed to read before you write code that
assumes it can.

Requires no libraries. One file. GPL-3.0-or-later.

## Commands

`/skopos` or `/sko`:

| command | what it does |
|---|---|
| `/sko map [full]` | Snapshot every frame into `SkoposDB` (`full` = include textures and fontstrings). Reload or log out to flush to disk. |
| `/sko grab [sec]` | After a countdown, capture the frame stack under the mouse — names, parents, strata, anchors, secure/forbidden flags. |
| `/sko find <text>` | Search live frame names. |
| `/sko api <text>` | Search `_G` **and** every `C_*` namespace — "does this API exist in this build?" |
| `/sko secret <api> [args]` | Call an API and report whether its returns are secret values (12.x), plus the `C_Secrets` policy answer for comparison. |
| `/sko attr <frame\|@last> [key]` | Secure attributes and snippets on a frame (`@last` = the last grab). |
| `/sko events [sec]` | Register **all** events for a window and report which actually fired. |
| `/sko cvar <text>` | Search CVars; changed-from-default listed first. |
| `/sko addons [text]` | Installed addon inventory: version, memory, load state. |
| `/sko note <text>` | Attach a note to the latest grab. |
| `/sko clear` | Wipe saved grabs. |

## Reading the output

Map and grab lines are 8 pipe-delimited columns:

```
debugName|objectType|parent|vis|WxH|strata:level|anchor|flags
```

- **vis** — `V` visible · `S` shown but a parent is hidden · `H` hidden ·
  `?` visibility *unreadable* (secret or errored — not the same as hidden)
- **anchor** — `POINT->RelativeName:RELPOINT(x,y)`, `+N` = additional points
- **flags** — `P` protected · `M` mouse-enabled · `F` forbidden · `R` region
  (layer:sublevel in column 6) · `U` forbidden-state unreadable (row gathered
  anyway; trust it less)

The dump lands in `WTF/Account/<account>/SavedVariables/Skopos.lua` and is meant
to be searched with your editor or `grep`, not read in-game.

## Why this exists

Blizzard's `/fstack` shows one frame at a time and only while you hover. Skopos
gives you the whole tree as a file, so you can ask "every frame anchored to
`PlayerFrame`" or "everything in strata `DIALOG` that is visible right now" and
get an answer in one grep. The secrecy probes exist because in Midnight the
answer to "can I read this?" depends on context (combat, instance type, unit),
and the only reliable way to know is to ask the client itself.

## Install

Copy the `Skopos` folder into `World of Warcraft/_retail_/Interface/AddOns/`
or grab a release from the GitHub Releases page.

## License

GPL-3.0-or-later — see [LICENSE](LICENSE).
