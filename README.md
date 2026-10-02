# Ultimate Spire feature walkthrough

Public demo site for the editors, inventory tool, item icons, 2D/3D zone tools, zone controller, talents / runewords, server file editing, and streamer privacy mode added to local Ultimate Spire.

**Site:** https://eniner.github.io/ultimate-spire-demo/

**Interactive app:** https://eniner.github.io/ultimate-spire-demo/app/

The clickable demo is the same Vue Spire frontend as the local tool, with a read-only adapter over a snapshot of the **default EQEmu installer PEQ** plus seeded Ultimate catalogs (27 zone-controller zones, talents, ranks, unlocks, traits, and runewords) and fake admin/server rows so every left-nav page and tab shows what it does. Character / account / guild names are fake demo rows (`DemoWarrior`, `demo_admin`, Demo Guild). No live accounts, passwords, or server files are included.

**Windows exe:** https://github.com/eniner/ultimate-spire/releases/latest

## New add-ons (screenshots)

1. **Zone Controller** — configured Ultimate zone JSON (custom / ignore / depop / loot / items)
2. **ZC create / clone** — bulk zone folders from a template or existing kit
3. **ZC apply tier** — stamp trash / boss / raid numbers onto many zones
4. **ZC custom mobs** — batch named mobs across target zones
5. **Talent catalog** — class trees, ranks, cost, pools
6. **Talent rank registry** — bucket keys for spent ranks
7. **Unlock states** — spell-turned-in player flags
8. **Specializations** — per-class specialization rows
9. **Trait vendor catalog** — non-god trait loot notes
10. **Runeword recipes** — four runes + ethereal base catalog
11. **Evolving targeted tables** — details first, then item columns; type 4 zone pills
12. **Task list redo** — searchable table instead of a giant native select
13. **Zone expansion labels** — PEQ 1-based Classic / Kunark / Velious
14. **Calculator windows** — bitmask tools in the same chrome

## Clips

1. **PEQ Editors hub** — every peqphpeditor tab mapped onto local full-page or table editors
2. **Item search with EQ icons** — class, race, and deity chips plus item icons on results and cards
3. **Evolving item chains** — chain list with each level’s icon and problem flags
4. **Inventory editor** — paperdoll, bags, bank, shared bank, parcels; place and remove items
5. **2D zone editor (Blackburrow)** — walls, spawn models, and the zone card tabs
6. **3D Atlas (Blackburrow)** — Lantern mesh orbit, NPCs, scenery, lighting, wireframe
7. **Server file / quest editor** — browse a quests tree and edit perl/lua
8. **Server config + hide private details** — world/zone/UCS/database tabs with privacy blur

Videos and screenshots were recorded against a local instance with **Hide private details** on. Server names, hosts, keys, passwords, and file paths stay blurred.

This repository is overview media only. It does not include the emulator, peq database, or server files.
