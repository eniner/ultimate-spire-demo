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
