# Zone Controller starter pack

This is the in-game Perl controller Ultimate Spire writes JSON for.
The `zone_controller.pl` here is the real script (including the 2-second Spire command poll).
Mob, loot, and item JSON are **blank templates** — no live server kits.

## Where these files go

Unzip next to `eqemu_config.json` / `zone.exe` so the tree looks like this:

```
<your eqemu server>/
  eqemu_config.json
  zone.exe
  world.exe
  quests/
    global/
      zone_controller.pl                 <-- this script (required)
      global_player.pl                   <-- merge the snippet if you want !initdata from any zone
      ultimatedata/
        templates/
          _mob.json                      <-- blank new-zone defaults
          _loot.json
          _item.json
        _spire_commands/                 <-- Spire Apply drops <zoneid>.json here
        _spire_drafts/
        _spire_recipes/
        _spire_runs/
        _spire_export/
        _spire_backups/
        talent_rank_registry.json        <-- empty
        unlock_state_registry.json       <-- empty
    plugins/
      instance_tools.pl                  <-- JSON paths + !initdata router
      MySQL.pl                           <-- DB lookups
      zc_support.pl                      <-- skip if you already have Ultimate Whisper/Debug/TSS plugins
```

Spire must see the same `quests` folder. Put `spire-windows-amd64.exe` in that server folder, or set `SPIRE_QUESTS_ROOT`.

## Requirements

The zone process runs Perl. Files alone are not enough.

### Runtime

- A working EQEmu `zone.exe` / `world.exe` that already loads Perl quests
- **Perl on PATH** for that zone process (Windows servers usually use [Strawberry Perl](https://strawberryperl.com/))
- Zone working directory = the folder that contains `eqemu_config.json` (so `MySQL.pl` can open it)

### Perl modules

`instance_tools.pl` uses the CPAN `JSON` package (not only core `JSON::PP`). Name lookups and respawn writes need `DBI` + `DBD::mysql`.

| Module | Used for | Notes |
|---|---|---|
| `JSON` | Read / write mob, loot, item JSON | Install if `perl -MJSON -e 1` fails |
| `JSON::PP` | Spire Apply command files | Core Perl; should already be there |
| `DBI` | `GetAllNPCNamesForZone`, item name lookup | EQEmu Perl usually has this |
| `DBD::mysql` | Same DB calls | Must match your MySQL / MariaDB |
| `File::Copy` / `File::Path` | Copy blank templates on first init | Core Perl |

Check from the **server folder**:

```
perl -MJSON -MJSON::PP -MDBI -MDBD::mysql -e "print qq{ok\n}"
```

If that dies, with Strawberry Perl:

```
cpan JSON
cpan DBI
cpan DBD::mysql
```

### Database and NPC

- `eqemu_config.json` → `server.database` reachable from the zone host
- NPC type **2000986** named exactly `zone_controller` (run `npc_types_zone_controller.sql` if missing)
- EQEmu auto-spawns that name; no `spawn2` row is required in most zones
- If your controller NPC uses a different id, change `GetControllerNPCID()` in `instance_tools.pl`

### Paths

- `quests/` next to `zone.exe`, or set `EQEMU_QUEST_ROOT` / `quest_root` in `eqemu_config.json`
- Spire in that same folder, or `SPIRE_QUESTS_ROOT` pointing at that `quests` directory
- World telnet is optional: Apply still drops `_spire_commands/<zoneid>.json` for a **popped** controller

## Already running Ultimate?

Do **not** overwrite your existing `ultimatedata/17`, `ultimatedata/31`, … folders.
You only need:

1. Replace `quests/global/zone_controller.pl` with this one (adds Spire Apply).
2. Keep your current `instance_tools.pl` unless Apply cannot find `_spire_commands`.
3. Skip `zc_support.pl` if `Whisper`, `Debug`, and `TSSGetRaw` already exist.
4. Leave your live mob/loot/item JSON alone.

## New server / no Ultimate data

1. Copy the `quests/` folder from this pack onto your server.
2. Run `npc_types_zone_controller.sql` against your peq database.
3. Confirm the Perl modules in Requirements (`perl -MJSON -MDBI -MDBD::mysql -e "print qq{ok\n}"`).
4. Pop a zone. EQEmu auto-spawns an NPC named `zone_controller`.
5. First hail / `!zc refreshzonedata` copies the blank templates into `ultimatedata/<zoneid>/`.
6. Edit those files in Spire, then Apply (`refreshzonedata` + `rebuffzone`) or hail again.

`-1` in basedata means “leave the vanilla NPC stat alone.” Fill numbers and loot tables as you go. Do not copy someone else’s item or NPC kits unless you mean to.

## Paths Spire uses

| Role | Path |
|---|---|
| Controller script | `quests/global/zone_controller.pl` |
| Zone JSON | `quests/global/ultimatedata/<zoneid>/<zoneid>_{mob,loot,item}.json` |
| New-zone templates | `quests/global/ultimatedata/templates/_{mob,loot,item}.json` |
| Live Apply queue | `quests/global/ultimatedata/_spire_commands/<zoneid>.json` |
| Apply result | `quests/global/ultimatedata/_spire_commands/<zoneid>.result.json` |
| Recipes / drafts / backups | `quests/global/ultimatedata/_spire_*` |

NPC type id **2000986** must be named `zone_controller`. Change `GetControllerNPCID()` in `instance_tools.pl` if yours is different.

## Optional

`snippets/global_player.zc-snippet.pl` — merge into `global_player.pl` for cross-zone `!initdata <zoneid>`.
