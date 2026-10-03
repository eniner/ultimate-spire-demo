# Zone Controller requirements

The zone process runs Perl. Copying files is not enough.

## Runtime

- EQEmu `zone.exe` / `world.exe` that already loads Perl quests
- Perl on PATH for that process (Windows: Strawberry Perl)
- Zone cwd = folder that contains `eqemu_config.json`

## Perl modules

| Module | Why |
|---|---|
| `JSON` | `instance_tools.pl` decode / encode of zone JSON |
| `JSON::PP` | Spire `_spire_commands` poll (core) |
| `DBI` + `DBD::mysql` | NPC name list, item names, respawn timer writes |
| `File::Copy` + `File::Path` | First-init template copy (core) |

```
perl -MJSON -MJSON::PP -MDBI -MDBD::mysql -e "print qq{ok\n}"
```

Missing modules (Strawberry):

```
cpan JSON
cpan DBI
cpan DBD::mysql
```

## Database / NPC

- `eqemu_config.json` → `server.database` works
- `npc_types` row id **2000986**, name `zone_controller`
- Auto-spawn by name; `spawn2` not required

## Paths

- `quests/` beside `zone.exe`, or `EQEMU_QUEST_ROOT` / `quest_root`
- Spire beside the server, or `SPIRE_QUESTS_ROOT`

## Sage, Lantern, and 2D maps (not in this pack)

These are separate from Zone Controller. Do not zip EQ client files or Lantern exports.

- **2D maps** — Spire downloads `eq-asset-preview` on first launch (internet once).
- **Sage** — Spire proxies EQ Sage from the web. The user Connects their own EQ client folder in Chrome. Sage writes `eqsage/` next to that client.
- **Lantern / Atlas 3D** — needs a LanternExtractor `Exports` folder with `<zone>/Zone/<zone>.glb`. Set `SPIRE_LANTERN_ROOT`, or keep Exports in the default Downloads / Desktop / Documents LanternExtractor path. Each person extracts their own client.
