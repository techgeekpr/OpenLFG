# OpenLFG

A server-wide **Looking For Group** board for Vanilla WoW (1.12) and Classic Era
(1.14) — Turtle/Kronos-style private servers included.

Stop squinting at World chat. OpenLFG turns LFG spam into a clean, Classic-style
window: pick your dungeons and role, hit **Set LFG**, and see everyone who's
looking — whether or not they have the addon.

## Features

- **Classic-LFG UI** — a two-pane window: pick dungeons/raids + your role
  (Tank / Heal / DPS, multi-select) on the left; the live player board on the right.
- **Works even for non-addon users** — it scans World chat and lists everyone
  who's LFG/LFM, so you see the *whole* server.
- **Syncs between addon users** — over a hidden custom chat channel, so the more
  people who run it, the better the board is for everyone.
- **LFG vs LFM tags** — instantly tells solo players apart from groups looking
  for more, with headcounts like `3/5`.
- **Roles** — auto-detected from chat ("LF tank", "need heals") or set explicitly.
- **Notes** — add details like *"LBRS first 3 bosses"* or *"need summon"*.
- **One-click** whisper and invite straight from the list.
- **Auto-expiry** — listings drop off after ~12 minutes (configurable).

## Works on both clients

The same folder runs on the **1.12.1 client (Lua 5.0)** and the **1.14.2 Classic
Era client (Lua 5.1)** — it ships two TOC files and detects the client at runtime.
No separate download needed.

## Install

1. Download / clone this repo into a folder named **`OpenLFG`**.
2. Copy that folder into your `Interface\AddOns\` directory.
3. Fully restart WoW, and tick **"Load out of date AddOns"** at the character screen.
4. Type **`/lfg`** in game.

## Commands

| Command | What it does |
|---|---|
| `/lfg` | Open / close the window |
| `/lfg me <note>` | List yourself as LFG (synced to addon users) |
| `/lfg world <note>` | Same, and also post `<note>` to the World channel |
| `/lfg off` | Remove yourself |
| `/lfg sync` | Toggle addon-to-addon sync |
| `/lfg lifetime <seconds>` | How long listings stay (default 720) |
| `/lfg wipe` | Clear your local board |

## How sync works

Vanilla has no server-wide addon-message channel, so OpenLFG uses a **hidden
custom chat channel** (`OpenLFGsync`) that it auto-joins and hides from your chat
windows. Each user broadcasts only their own listing (and answers new logins), so
there's no chat spam. Scanned World-chat entries stay local — everyone scans the
same channel, so boards converge.

## Compatibility notes for contributors

This addon **must run on both Lua 5.0 (1.12) and Lua 5.1 (1.14)**. That means:

- No `%` modulo operator (use `A.mod`), no `#` length operator (use `A.tlen`),
  no `select()`, no bare `string.match` / `string.gmatch` (use `A.match` / `A.gmatch`).
- `SetPoint` must use the full form `SetPoint(point, frame, relativePoint, x, y)`
  — the 1.12 client rejects the shorthand.
- Guard modern-only APIs (`C_Timer`, `IsInGroup`, `JoinTemporaryChannel`,
  `BackdropTemplateMixin`, `SetColorTexture`) behind `if X then` with 1.12 fallbacks.

`Compat.lua` is the abstraction layer for all of this.

## Files

| File | Purpose |
|---|---|
| `Compat.lua` | Runtime abstraction (events, timers, strings, channels) |
| `Dungeons.lua` | Dungeon/role catalogue + detection helpers |
| `Core.lua` | Saved data, the board, expiry, slash commands |
| `Scan.lua` | World-chat LFG detection |
| `Comm.lua` | Addon-to-addon sync protocol |
| `UI.lua` | The window |

## License

MIT — do whatever you like with it.
