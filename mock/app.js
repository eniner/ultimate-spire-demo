const TASK_TYPES = {0: "Task", 1: "Shared", 2: "Quest", 3: "Expedition"}
const CLASS_NAMES = {1:"Warrior",2:"Cleric",3:"Paladin",4:"Ranger",5:"Shadow Knight",6:"Druid",7:"Monk",8:"Bard",9:"Rogue",10:"Shaman",11:"Necromancer",12:"Wizard",13:"Magician",14:"Enchanter",15:"Beastlord",16:"Berserker"}
const EVO_TYPES = {1:"XP",2:"Kills",3:"Race kills",4:"Zone kills",99:"Stock / unused"}

const PEQ_EDITORS = [
  {group:"Game data", title:"Items", to:"#/items", status:"Full page", php:"items", blurb:"Item search against stock peq.items."},
  {group:"Game data", title:"Evolving Items", to:"#/evolving", status:"Full page", php:"items", blurb:"items_evolving_details first, then item evo columns."},
  {group:"Game data", title:"NPCs", to:"#/zone/blackburrow", status:"Full page", php:"npc", blurb:"Open a zone, then edit spawn/NPC rows."},
  {group:"Game data", title:"Spawns", to:"#/zone/blackburrow", status:"Table editor", php:"spawn", blurb:"spawn2 rows: zone, XYZ, heading, pathgrid."},
  {group:"Game data", title:"Spells", to:"#/items", status:"Full page", php:"spells", blurb:"Spell editor stays a dedicated page in live Spire."},
  {group:"Game data", title:"Tasks", to:"#/tasks", status:"Full page", php:"tasks", blurb:"Searchable task table from peq.tasks."},
  {group:"Game data", title:"Loot", to:"#/editors", status:"Full page", php:"loot", blurb:"Loottables and drop preview."},
  {group:"Game data", title:"Merchants", to:"#/editors", status:"Full page", php:"merchant", blurb:"Merchant lists."},
  {group:"Game data", title:"Factions", to:"#/editors", status:"Table editor", php:"faction", blurb:"faction_list."},
  {group:"Game data", title:"Tradeskills", to:"#/editors", status:"Table editor", php:"tradeskill", blurb:"Recipe headers."},
  {group:"Zone / misc", title:"Zones", to:"#/zones", status:"Full page", php:"zone", blurb:"Zone list with PEQ 1-based expansions."},
  {group:"Zone / misc", title:"Doors", to:"#/zone/blackburrow", status:"Table editor", php:"misc", blurb:"Doors and teleports on the zone map."},
  {group:"Zone / misc", title:"Grids", to:"#/atlas", status:"Table editor", php:"util", blurb:"Path grids drawn on Atlas."},
  {group:"Zone / misc", title:"Objects", to:"#/atlas", status:"Table editor", php:"misc", blurb:"World objects / placeables."},
  {group:"Zone / misc", title:"Ground Spawns", to:"#/editors", status:"Table editor", php:"misc", blurb:"Ground items by zoneid."},
  {group:"Zone / misc", title:"Forage", to:"#/editors", status:"Table editor", php:"misc", blurb:"Forage table by zoneid."},
  {group:"Live server", title:"Inventory", to:"#/inventory", status:"Full page", php:"inv", blurb:"Paperdoll using stock starter items."},
  {group:"Live server", title:"Players", to:"#/editors", status:"Table editor", php:"player", blurb:"character_data. This mock does not ship player rows."},
  {group:"Live server", title:"Accounts", to:"#/editors", status:"Table editor", php:"account", blurb:"Passwords stay hidden in live Spire."},
  {group:"Live server", title:"Server", to:"#/admin", status:"Full page", php:"server", blurb:"Admin tools. Server Files is its own page."},
]

const state = {
  peq: null,
  privacy: false,
  itemQ: "",
  taskQ: "",
  taskType: "",
  zoneQ: "",
  zoneXpac: "",
  evoId: null,
  invSlot: null,
  sysTab: "talents",
  zcTab: "zones",
  filePath: "quests/global/zone_controller.pl",
  adminTab: "world",
  calc: 0,
  atlas: {yaw: 0.4, showNpcs: true, showPaths: true, move: true},
}

function $(id) { return document.getElementById(id) }
function esc(v) {
  return String(v == null ? "" : v)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}
function iconColor(id) {
  const n = Number(id) || 0
  const h = (n * 47) % 360
  return `hsl(${h} 42% 42%)`
}
function ico(id) {
  return `<span class="ico" style="background:${iconColor(id)}"></span>`
}
function toast(msg) {
  const el = $("toast")
  el.hidden = false
  el.textContent = msg
  clearTimeout(toast._t)
  toast._t = setTimeout(() => { el.hidden = true }, 2600)
}
function route() {
  const hash = (location.hash || "#/home").replace(/^#/, "")
  const [path, qs] = hash.split("?")
  const q = {}
  if (qs) {
    qs.split("&").forEach((p) => {
      const [k, v] = p.split("=")
      q[decodeURIComponent(k)] = decodeURIComponent(v || "")
    })
  }
  return {path: path || "/home", q}
}
function go(hash) {
  location.hash = hash
}

function wornSlots() {
  const byName = {}
  state.peq.items.forEach((i) => { byName[i.name] = i })
  const pick = (name, fallback) => byName[name] || state.peq.items[fallback] || state.peq.items[0]
  return [
    {id:"head", label:"Head", item: pick("Cloth Cap", 0)},
    {id:"chest", label:"Chest", item: pick("Patchwork Tunic", 1)},
    {id:"arms", label:"Arms", item: null},
    {id:"hands", label:"Hands", item: pick("Brown Leather Gloves", 2)},
    {id:"primary", label:"Primary", item: pick("Rusty Short Sword", 3)},
    {id:"secondary", label:"Secondary", item: pick("Small Bag", 4)},
    {id:"legs", label:"Legs", item: pick("Cloth Pants", 5)},
    {id:"feet", label:"Feet", item: pick("Leather Boots", 6)},
    {id:"range", label:"Range", item: null},
  ]
}

function evoChains() {
  const map = {}
  state.peq.evolving_details.forEach((row) => {
    const key = row.item_evo_id
    if (!map[key]) map[key] = {id: key, rows: [], type: row.type}
    map[key].rows.push(row)
  })
  const items = {}
  state.peq.evolving_items.forEach((it) => { items[it.id] = it })
  return Object.values(map).map((chain) => {
    chain.rows.sort((a, b) => a.item_evolve_level - b.item_evolve_level)
    chain.items = chain.rows.map((r) => items[r.item_id]).filter(Boolean)
    chain.name = (chain.items[0] && chain.items[0].name) || ("Chain " + chain.id)
    chain.max = chain.rows.length
    return chain
  })
}

function uniqueXpacs() {
  const seen = []
  const have = new Set()
  state.peq.zones.forEach((z) => {
    if (!have.has(z.expansion)) {
      have.add(z.expansion)
      seen.push({id: z.expansion, name: z.expansion_name})
    }
  })
  return seen.sort((a, b) => a.id - b.id)
}

function renderHome() {
  const xp = uniqueXpacs()
  const kunark = state.peq.zones.filter((z) => z.expansion === 2).length
  return `
    <div class="win"><div class="win-h">Stock installer PEQ</div><div class="win-b">
      <p class="lede">This mock reads a snapshot of the <b>default EQEmu installer database</b> (<span class="privacy-hide">peq @ localhost</span>).
      ${state.peq.zone_count} version-0 zones, ${state.peq.items.length} starter/search items, ${state.peq.evolving_details.length} evolving-detail rows, ${state.peq.tasks.length} tasks, and Blackburrow spawn/grid rows.
      Click the left nav. Nothing is saved.</p>
      <div class="grid grid-3">
        <div class="card"><strong>${state.peq.zone_count} zones</strong><p>${kunark} Kunark zones labeled ${esc(xp.find((x)=>x.id===2)?.name || "Kunark")} (PEQ expansion 2).</p></div>
        <div class="card"><strong>${state.peq.blackburrow.npcs.length} Blackburrow NPCs</strong><p>Gnolls and pups from spawn2 + npc_types, plus ${state.peq.blackburrow.grids.length} grid waypoints.</p></div>
        <div class="card"><strong>${evoChains().length} evolving chains</strong><p>Stock PEQ uses type 99 (server ignores these). Live type 4 is zone-kill.</p></div>
      </div>
    </div></div>
    <div class="cards">
      <a class="card" href="#/editors"><strong>PEQ Editors</strong><p>Hub of full-page and table editors.</p></a>
      <a class="card" href="#/zones"><strong>Zones</strong><p>Filter Classic / Kunark / Velious with the 1-based fix.</p></a>
      <a class="card" href="#/evolving"><strong>Evolving</strong><p>Two tables: details, then item evo columns.</p></a>
      <a class="card" href="#/tasks"><strong>Tasks</strong><p>Search the stock task list.</p></a>
      <a class="card" href="#/atlas"><strong>3D Atlas</strong><p>Blackburrow markers and path grids from peq.</p></a>
      <a class="card" href="#/inventory"><strong>Inventory</strong><p>Paperdoll using Cloth Cap, Rusty Short Sword, and other stock items.</p></a>
    </div>`
}

function renderEditors() {
  const groups = [...new Set(PEQ_EDITORS.map((e) => e.group))]
  return groups.map((g) => `
    <div class="win"><div class="win-h">${esc(g)}</div><div class="win-b">
      <div class="cards">${PEQ_EDITORS.filter((e)=>e.group===g).map((e)=>`
        <a class="card" href="${e.to}">
          <strong>${esc(e.title)} <span class="badge ${e.status==="Full page"?"gold":""}">${esc(e.status)}</span></strong>
          <p class="mono subtle">php: ${esc(e.php)}</p>
          <p>${esc(e.blurb)}</p>
        </a>`).join("")}</div>
    </div></div>`).join("")
}

function renderItems() {
  const q = state.itemQ.toLowerCase()
  const rows = state.peq.items.filter((i) => !q || String(i.name).toLowerCase().includes(q) || String(i.id).includes(q))
  return `
    <div class="win"><div class="win-h">Item search</div><div class="win-b">
      <p class="lede">Rows from stock <code>items</code>. Icons here are color chips (the live app uses EQ item sprites).</p>
      <div class="toolbar">
        <input id="item-q" value="${esc(state.itemQ)}" placeholder="Name or id — try bread, gnoll, rusty">
        <span class="stat ml"><b>${rows.length}</b> / ${state.peq.items.length}</span>
      </div>
      <div class="table-wrap"><table>
        <thead><tr><th>Item</th><th>ID</th><th>Icon</th><th>Slots</th><th>Type</th></tr></thead>
        <tbody>${rows.map((i)=>`<tr>
          <td>${ico(i.icon)}${esc(i.name)}</td>
          <td class="mono">${i.id}</td>
          <td class="mono">${i.icon}</td>
          <td class="mono">${i.slots}</td>
          <td class="mono">${i.itemtype}</td>
        </tr>`).join("")}</tbody>
      </table></div>
    </div></div>`
}

function renderEvolving() {
  const chains = evoChains()
  const selected = chains.find((c) => c.id === state.evoId) || chains[0]
  if (selected && state.evoId == null) state.evoId = selected.id
  return `
    <div class="win"><div class="win-h">Evolving chains</div><div class="win-b">
      <p class="lede">Order of operations: define the chain in <code>items_evolving_details</code>, then match <code>items.evoitem / evoid / evolvinglevel / evomax</code>.
      This installer DB is stock <b>type 99</b> (ignored in-game). Type 4 would put zone IDs in subtype and kill count in required amount.</p>
      <div class="grid grid-2">
        <div class="table-wrap"><table>
          <thead><tr><th>Chain</th><th>Type</th><th>Max</th></tr></thead>
          <tbody>${chains.map((c)=>`<tr class="clickable ${c.id===selected.id?"selected":""}" data-evo="${c.id}">
            <td>${c.items[0] ? ico(c.items[0].icon) : ""}${esc(c.name)}<div class="subtle mono">evoid ${c.id}</div></td>
            <td>${c.type} · ${esc(EVO_TYPES[c.type]||"")}</td>
            <td>${c.max}</td>
          </tr>`).join("")}</tbody>
        </table></div>
        <div>
          <div class="win-h" style="margin:-14px -14px 12px;border:0;border-bottom:1px solid var(--border)">Chain ${selected.id}</div>
          <p class="lede">1. Details table</p>
          <table><thead><tr><th>Lvl</th><th>Item</th><th>Type</th><th>Subtype</th><th>Amt</th></tr></thead>
          <tbody>${selected.rows.map((r,i)=>`<tr>
            <td>${r.item_evolve_level}</td>
            <td>${selected.items[i] ? ico(selected.items[i].icon)+esc(selected.items[i].name) : r.item_id}</td>
            <td>${r.type}</td>
            <td>${r.type===4 ? `<div class="pills">${String(r.sub_type||"").split(",").filter(Boolean).map((z)=>`<span class="zone-pill">${esc(z)}</span>`).join("")}</div>` : esc(r.sub_type)}</td>
            <td>${r.required_amount}</td>
          </tr>`).join("")}</tbody></table>
          <p class="lede" style="margin-top:14px">2. Item evo columns</p>
          <table><thead><tr><th>Item</th><th>evoitem</th><th>evoid</th><th>lvl</th><th>evomax</th></tr></thead>
          <tbody>${selected.items.map((it)=>`<tr>
            <td>${ico(it.icon)}${esc(it.name)}</td><td>${it.evoitem}</td><td>${it.evoid}</td><td>${it.evolvinglevel}</td><td>${it.evomax}</td>
          </tr>`).join("")}</tbody></table>
        </div>
      </div>
    </div></div>`
}

function renderTasks() {
  const q = state.taskQ.toLowerCase()
  const rows = state.peq.tasks.filter((t) => {
    if (state.taskType !== "" && String(t.type) !== state.taskType) return false
    return !q || String(t.title).toLowerCase().includes(q) || String(t.id).includes(q)
  })
  return `
    <div class="win"><div class="win-h">Tasks</div><div class="win-b">
      <p class="lede">Stock <code>tasks</code> — searchable table, not a 900-row native select.</p>
      <div class="toolbar">
        <input id="task-q" value="${esc(state.taskQ)}" placeholder="Title or id">
        <select id="task-type">
          <option value="">All types</option>
          ${Object.entries(TASK_TYPES).map(([k,v])=>`<option value="${k}" ${state.taskType===k?"selected":""}>${v}</option>`).join("")}
        </select>
        <span class="stat ml"><b>${rows.length}</b> shown</span>
      </div>
      <div class="table-wrap"><table>
        <thead><tr><th>ID</th><th>Title</th><th>Type</th><th>Duration</th><th>Level</th></tr></thead>
        <tbody>${rows.map((t)=>`<tr class="clickable" data-task="${t.id}">
          <td class="mono">${t.id}</td>
          <td>${esc(t.title)}</td>
          <td>${TASK_TYPES[t.type]||t.type}</td>
          <td>${t.duration}</td>
          <td>${t.min_level}–${t.max_level}</td>
        </tr>`).join("")}</tbody>
      </table></div>
    </div></div>`
}

function renderZones() {
  const q = state.zoneQ.toLowerCase()
  const rows = state.peq.zones.filter((z) => {
    if (state.zoneXpac !== "" && String(z.expansion) !== state.zoneXpac) return false
    return !q || z.long.toLowerCase().includes(q) || z.short.toLowerCase().includes(q) || String(z.id).includes(q)
  })
  return `
    <div class="win"><div class="win-h">Zones</div><div class="win-b">
      <p class="lede">PEQ <code>zone.expansion</code> is 1-based: 1 Classic, 2 Kunark, 3 Velious. Stock Spire used to read that as 0-based, so Kunark showed as Velious.</p>
      <div class="toolbar">
        <input id="zone-q" value="${esc(state.zoneQ)}" placeholder="Name or shortname — try blackburrow">
        <select id="zone-xpac">
          <option value="">All expansions</option>
          ${uniqueXpacs().map((x)=>`<option value="${x.id}" ${String(x.id)===state.zoneXpac?"selected":""}>${x.id} · ${esc(x.name)}</option>`).join("")}
        </select>
        <span class="stat ml"><b>${rows.length}</b> zones</span>
      </div>
      <div class="table-wrap"><table>
        <thead><tr><th>ID</th><th>Zone</th><th>Short</th><th>Expansion</th><th></th></tr></thead>
        <tbody>${rows.slice(0,80).map((z)=>`<tr>
          <td class="mono">${z.id}</td>
          <td>${esc(z.long)}</td>
          <td class="mono">${esc(z.short)}</td>
          <td>${z.expansion} · ${esc(z.expansion_name)}</td>
          <td>${z.short==="blackburrow"?`<a class="btn" href="#/zone/blackburrow">Open</a>`:""}</td>
        </tr>`).join("")}</tbody>
      </table></div>
      ${rows.length>80?`<p class="subtle">Showing first 80 of ${rows.length}.</p>`:""}
    </div></div>`
}

function renderZone() {
  const z = state.peq.zones.find((x) => x.short === "blackburrow")
  const npcs = state.peq.blackburrow.npcs
  return `
    <div class="win"><div class="win-h">${esc(z.long)} <span class="badge gold">${esc(z.expansion_name)}</span></div><div class="win-b">
      <div class="toolbar">
        <a class="btn" href="#/zones">Back to list</a>
        <a class="btn primary" href="#/atlas">3D Atlas</a>
        <span class="stat ml"><b>${npcs.length}</b> spawn rows · <b>${state.peq.blackburrow.grids.length}</b> grid points · <b>${state.peq.blackburrow.objects.length}</b> objects</span>
      </div>
      <p class="lede">2D mock plots real spawn2 X/Y from stock Blackburrow. Drag empty space to pan. Click a row to highlight.</p>
      <div class="atlas" id="map2d"><canvas id="map2d-c"></canvas><div class="atlas-note">Blackburrow · stock spawn2</div></div>
    </div></div>
    <div class="win"><div class="win-h">NPCs</div><div class="win-b table-wrap">
      <table>
        <thead><tr><th>NPC</th><th>Lvl</th><th>HP</th><th>X</th><th>Y</th><th>Grid</th></tr></thead>
        <tbody>${npcs.map((n,i)=>`<tr class="clickable" data-npc="${i}">
          <td>${esc(n.name.replace(/_/g," "))}${n.lastname?` <span class="subtle">${esc(n.lastname)}</span>`:""}</td>
          <td>${n.level}</td><td>${n.hp}</td>
          <td class="mono">${Number(n.x).toFixed(1)}</td>
          <td class="mono">${Number(n.y).toFixed(1)}</td>
          <td class="mono">${n.pathgrid||"—"}</td>
        </tr>`).join("")}</tbody>
      </table>
    </div></div>`
}

function renderAtlas() {
  const a = state.atlas
  return `
    <div class="win"><div class="win-h">3D Atlas · Blackburrow</div><div class="win-b">
      <div class="toolbar">
        <button class="btn ${a.showNpcs?"active":""}" data-atlas="npcs">NPCs</button>
        <button class="btn ${a.showPaths?"active":""}" data-atlas="paths">Path grids</button>
        <button class="btn ${a.move?"active":""}" data-atlas="move">Move on path</button>
        <a class="btn" href="#/zone/blackburrow">2D map</a>
        <a class="btn" href="#/sage">Sage</a>
        <span class="stat ml">Lantern mesh is not on GitHub Pages — this plots stock peq coordinates.</span>
      </div>
      <div class="atlas" id="atlas3d"><canvas id="atlas-c"></canvas><div class="atlas-note">Drag to orbit · ${state.peq.blackburrow.npcs.length} NPCs · ${state.peq.blackburrow.grids.length} waypoints</div></div>
    </div></div>`
}

function renderInventory() {
  const slots = wornSlots()
  const bag = state.peq.items.filter((i) => /bread|water|flask|fang|stout|bag/i.test(i.name)).slice(0, 8)
  const selected = slots.find((s) => s.id === state.invSlot)
  return `
    <div class="win"><div class="win-h">Inventory</div><div class="win-b">
      <p class="lede">No player characters are published. This paperdoll is stock installer items a new character would actually own or find early.</p>
      <div class="grid grid-2">
        <div>
          <div class="doll">${slots.map((s)=>`
            <button type="button" class="slot ${s.item?"has":""} ${s.id===state.invSlot?"active":""}" data-slot="${s.id}">
              ${s.item?ico(s.item.icon)+`<b>${esc(s.item.name)}</b>`:`<span>${esc(s.label)}</span>`}
            </button>`).join("")}</div>
        </div>
        <div>
          <p class="lede">${selected ? "Selected "+esc(selected.label)+". Click a bag item to preview a swap (not saved)." : "Click a worn slot."}</p>
          <table><thead><tr><th>General / bag</th><th>ID</th></tr></thead>
          <tbody>${bag.map((i)=>`<tr class="clickable" data-bag="${i.id}">
            <td>${ico(i.icon)}${esc(i.name)}</td><td class="mono">${i.id}</td>
          </tr>`).join("")}</tbody></table>
        </div>
      </div>
    </div></div>`
}

function renderController() {
  return `
    <div class="win"><div class="win-h">Zone Controller</div><div class="win-b">
      <div class="toolbar">
        <button class="btn ${state.zcTab==="zones"?"active":""}" data-zc="zones">Configured zones</button>
        <button class="btn ${state.zcTab==="create"?"active":""}" data-zc="create">Create / clone</button>
        <button class="btn ${state.zcTab==="tier"?"active":""}" data-zc="tier">Apply tier</button>
        <button class="btn ${state.zcTab==="mobs"?"active":""}" data-zc="mobs">Add mobs</button>
      </div>
      <p class="lede">Stock installer PEQ has <b>no zone-controller tables</b>. On a real Ultimate box this page reads <code>quests/global/ultimatedata</code> JSON. The tabs still work so you can see the builder chrome.</p>
      ${state.zcTab==="zones"?`<p class="subtle">0 configured Ultimate zones in this snapshot. Use live Spire against your quests folder.</p>`:""}
      ${state.zcTab==="create"?`<div class="field-row"><div class="field"><label>Zone ids</label><input value="17, 30, 34" disabled></div><div class="field"><label>Clone from</label><input value="(blank template)" disabled></div></div><button class="btn" data-mock-write>Preview JSON</button>`:""}
      ${state.zcTab==="tier"?`<div class="field-row"><div class="field"><label>Tier</label><select disabled><option>Trash</option><option>Boss</option><option>Raid</option></select></div><div class="field"><label>Level</label><input value="20" disabled></div></div><button class="btn" data-mock-write>Preview JSON</button>`:""}
      ${state.zcTab==="mobs"?`<div class="field"><label>Mob name</label><input value="a_gnoll_captain" disabled></div><button class="btn" data-mock-write>Preview JSON</button>`:""}
    </div></div>`
}

function renderSystems() {
  const tabs = ["talents","ranks","unlocks","specs","traits","runewords"]
  return `
    <div class="win"><div class="win-h">Talents / Runewords</div><div class="win-b">
      <div class="toolbar">
        ${tabs.map((t)=>`<button class="btn ${state.sysTab===t?"active":""}" data-sys="${t}">${t}</button>`).join("")}
      </div>
      <p class="lede">These catalogs are quest JSON / custom tables, not stock PEQ. The installer database has no <code>custom_runeword_*</code> tables and no talent_catalog. Live Spire edits the files next to zone controller JSON.</p>
      <p class="subtle">Open this tab on your local Spire to see the 283-talent catalog from your quests tree.</p>
    </div></div>`
}

function renderFiles() {
  const files = {
    "quests/global/zone_controller.pl": "# stock tree would show perl here\\nsub EVENT_SAY {\\n  # GM saylinks for Ultimate zone controller\\n}",
    "quests/blackburrow/a_gnoll_pup.pl": "sub EVENT_SAY {\\n  if ($text=~/hail/i) { quest::say('Grrrr...'); }\\n}",
    "quests/global/global_player.pl": "sub EVENT_ENTERZONE {\\n  # global player hooks\\n}",
  }
  if (!files[state.filePath]) state.filePath = Object.keys(files)[0]
  return `
    <div class="win"><div class="win-h">Server Files</div><div class="win-b">
      <p class="lede">Live Spire points at your quests folder. This mock shows typical installer paths only — no disk contents from your machine.</p>
      <div class="grid grid-2">
        <div class="tree">${Object.keys(files).map((p)=>`<button type="button" class="${p===state.filePath?"active":""}" data-file="${esc(p)}">${esc(p)}</button>`).join("")}</div>
        <pre class="code">${esc(files[state.filePath])}</pre>
      </div>
    </div></div>`
}

function renderAdmin() {
  const tabs = ["world","zone","database","privacy"]
  return `
    <div class="win"><div class="win-h">Server Admin</div><div class="win-b">
      <div class="toolbar">${tabs.map((t)=>`<button class="btn ${state.adminTab===t?"active":""}" data-admin="${t}">${t}</button>`).join("")}</div>
      ${state.adminTab==="privacy"?`<p class="lede">Hide private details blurs hosts, keys, and paths. Toggle it in the left footer.</p><p class="privacy-hide">Example host: localhost:3306 / peq</p>`:""}
      ${state.adminTab==="database"?`<div class="field"><label>Database</label><input class="privacy-hide" value="peq" disabled></div><div class="field"><label>Host</label><input class="privacy-hide" value="localhost" disabled></div><p class="subtle">Password is never shown.</p>`:""}
      ${state.adminTab==="world"?`<div class="field"><label>Long name</label><input class="privacy-hide" value="EQEmu" disabled></div><div class="field"><label>Short name</label><input class="privacy-hide" value="EQEmu" disabled></div>`:""}
      ${state.adminTab==="zone"?`<p class="lede">Zone server ports and boot options live here in the real app. Server Files is a separate left-nav page, not this dashboard.</p>`:""}
    </div></div>`
}

function renderCalculators() {
  const classes = Object.entries(CLASS_NAMES)
  return `
    <div class="win"><div class="win-h">Class bitmask</div><div class="win-b">
      <p class="lede">Click classes. The number is the EQ bitmask used on items.</p>
      <div class="toolbar">
        ${classes.map(([id,name])=>{
          const bit = 1 << (Number(id)-1)
          const on = (state.calc & bit) !== 0
          return `<button class="btn ${on?"active":""}" data-bit="${bit}">${esc(name)}</button>`
        }).join("")}
        <span class="stat ml">mask <b class="mono">${state.calc}</b></span>
      </div>
    </div></div>`
}

function renderSage() {
  return `
    <div class="win"><div class="win-h">EQ Sage</div><div class="win-b">
      <p class="lede">Sage is a live iframe of the zone converter. GitHub Pages cannot proxy eqsage.vercel.app the way local Spire does.
      On your machine: open Sage, use <b>Connect EQ folder</b>, then <b>Request Permissions</b>, then pick Blackburrow so it can convert.</p>
      <a class="btn" href="#/atlas">Use the Atlas mock instead</a>
    </div></div>`
}

const PAGES = {
  "/home": {title:"Home", crumb:"Mock · stock PEQ", render: renderHome},
  "/editors": {title:"PEQ Editors", crumb:"Game Data", render: renderEditors},
  "/items": {title:"Items", crumb:"Game Data", render: renderItems},
  "/evolving": {title:"Evolving Items", crumb:"Game Data", render: renderEvolving},
  "/inventory": {title:"Inventory", crumb:"Characters", render: renderInventory},
  "/tasks": {title:"Tasks", crumb:"Game Data", render: renderTasks},
  "/zones": {title:"Zones", crumb:"Game Data", render: renderZones},
  "/zone/blackburrow": {title:"Blackburrow", crumb:"Zones", render: renderZone},
  "/atlas": {title:"3D Atlas", crumb:"Zones · Blackburrow", render: renderAtlas},
  "/controller": {title:"Zone Controller", crumb:"Game Data", render: renderController},
  "/systems": {title:"Talents / Runewords", crumb:"Game Data", render: renderSystems},
  "/files": {title:"Server Files", crumb:"Client", render: renderFiles},
  "/admin": {title:"Server Admin", crumb:"Client", render: renderAdmin},
  "/calculators": {title:"Calculators", crumb:"Tools", render: renderCalculators},
  "/sage": {title:"Sage", crumb:"Tools", render: renderSage},
}

function paint() {
  const {path} = route()
  const page = PAGES[path] || PAGES["/home"]
  $("page-title").textContent = page.title
  $("crumb").textContent = page.crumb
  $("page").innerHTML = page.render()
  document.querySelectorAll(".nav-link").forEach((a) => {
    const href = a.getAttribute("href").replace("#", "")
    a.classList.toggle("active", href === path || (path.startsWith("/zone") && href === "/zones") || (path === "/atlas" && href === "/atlas"))
  })
  bind()
  if (path === "/atlas") startAtlas("atlas-c", true)
  if (path === "/zone/blackburrow") startAtlas("map2d-c", false)
}

function bind() {
  const itemQ = $("item-q")
  if (itemQ) itemQ.oninput = () => { state.itemQ = itemQ.value; paint() }
  const taskQ = $("task-q")
  if (taskQ) taskQ.oninput = () => { state.taskQ = taskQ.value; paint() }
  const taskType = $("task-type")
  if (taskType) taskType.onchange = () => { state.taskType = taskType.value; paint() }
  const zoneQ = $("zone-q")
  if (zoneQ) zoneQ.oninput = () => { state.zoneQ = zoneQ.value; paint() }
  const zoneXpac = $("zone-xpac")
  if (zoneXpac) zoneXpac.onchange = () => { state.zoneXpac = zoneXpac.value; paint() }
  document.querySelectorAll("[data-evo]").forEach((el) => {
    el.onclick = () => { state.evoId = Number(el.getAttribute("data-evo")); paint() }
  })
  document.querySelectorAll("[data-task]").forEach((el) => {
    el.onclick = () => toast("Task " + el.getAttribute("data-task") + " — editor body is in live Spire.")
  })
  document.querySelectorAll("[data-slot]").forEach((el) => {
    el.onclick = () => { state.invSlot = el.getAttribute("data-slot"); paint() }
  })
  document.querySelectorAll("[data-bag]").forEach((el) => {
    el.onclick = () => toast("Would place item " + el.getAttribute("data-bag") + " into " + (state.invSlot || "the selected slot") + ".")
  })
  document.querySelectorAll("[data-sys]").forEach((el) => {
    el.onclick = () => { state.sysTab = el.getAttribute("data-sys"); paint() }
  })
  document.querySelectorAll("[data-zc]").forEach((el) => {
    el.onclick = () => { state.zcTab = el.getAttribute("data-zc"); paint() }
  })
  document.querySelectorAll("[data-file]").forEach((el) => {
    el.onclick = () => { state.filePath = el.getAttribute("data-file"); paint() }
  })
  document.querySelectorAll("[data-admin]").forEach((el) => {
    el.onclick = () => { state.adminTab = el.getAttribute("data-admin"); paint() }
  })
  document.querySelectorAll("[data-bit]").forEach((el) => {
    el.onclick = () => { state.calc ^= Number(el.getAttribute("data-bit")); paint() }
  })
  document.querySelectorAll("[data-mock-write]").forEach((el) => {
    el.onclick = () => toast("Preview only. Stock PEQ has no zone-controller JSON to write.")
  })
  document.querySelectorAll("[data-atlas]").forEach((el) => {
    el.onclick = () => {
      const k = el.getAttribute("data-atlas")
      if (k === "npcs") state.atlas.showNpcs = !state.atlas.showNpcs
      if (k === "paths") state.atlas.showPaths = !state.atlas.showPaths
      if (k === "move") state.atlas.move = !state.atlas.move
      paint()
    }
  })
}

let atlasTimer = null
function startAtlas(canvasId, orbit) {
  const canvas = $(canvasId)
  if (!canvas) return
  const wrap = canvas.parentElement
  const npcs = state.peq.blackburrow.npcs
  const grids = state.peq.blackburrow.grids
  const byGrid = {}
  grids.forEach((g) => {
    if (!byGrid[g.gridid]) byGrid[g.gridid] = []
    byGrid[g.gridid].push(g)
  })
  Object.values(byGrid).forEach((pts) => pts.sort((a, b) => a.number - b.number))
  let xs = npcs.map((n) => n.x).concat(grids.map((g) => g.x))
  let ys = npcs.map((n) => n.y).concat(grids.map((g) => g.y))
  if (!xs.length) { xs = [0]; ys = [0] }
  const minX = Math.min(...xs), maxX = Math.max(...xs)
  const minY = Math.min(...ys), maxY = Math.max(...ys)
  const movers = npcs.filter((n) => n.pathgrid && byGrid[n.pathgrid] && byGrid[n.pathgrid].length > 1).slice(0, 12).map((n) => ({
    grid: n.pathgrid, t: Math.random(),
  }))
  let drag = false, lastX = 0
  canvas.onmousedown = (e) => { drag = true; lastX = e.clientX }
  window.addEventListener("mouseup", () => { drag = false })
  canvas.onmousemove = (e) => {
    if (!drag || !orbit) return
    state.atlas.yaw += (e.clientX - lastX) * 0.01
    lastX = e.clientX
  }
  function project(x, y) {
    const w = canvas.width, h = canvas.height
    const nx = (x - minX) / Math.max(1, maxX - minX)
    const ny = (y - minY) / Math.max(1, maxY - minY)
    if (!orbit) return [30 + nx * (w - 60), 30 + (1 - ny) * (h - 60)]
    const cx = (nx - 0.5) * 2, cy = (ny - 0.5) * 2
    const ca = Math.cos(state.atlas.yaw), sa = Math.sin(state.atlas.yaw)
    const rx = cx * ca - cy * sa
    const ry = cx * sa + cy * ca
    return [w / 2 + rx * w * 0.38, h * 0.62 + ry * h * 0.22]
  }
  function frame(t) {
    const dpr = window.devicePixelRatio || 1
    canvas.width = wrap.clientWidth * dpr
    canvas.height = wrap.clientHeight * dpr
    const ctx = canvas.getContext("2d")
    ctx.scale(dpr, dpr)
    const w = wrap.clientWidth, h = wrap.clientHeight
    ctx.fillStyle = "#12161c"
    ctx.fillRect(0, 0, w, h)
    ctx.fillStyle = "#2a2118"
    ctx.beginPath()
    ctx.ellipse(w/2, h*0.58, w*0.42, h*0.28, 0, 0, Math.PI*2)
    ctx.fill()
    if (state.atlas.showPaths) {
      ctx.strokeStyle = "rgba(201,162,74,.45)"
      ctx.lineWidth = 1
      Object.values(byGrid).forEach((pts) => {
        if (pts.length < 2) return
        ctx.beginPath()
        pts.forEach((p, i) => {
          const [px, py] = project(p.x, p.y)
          if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
        })
        ctx.stroke()
      })
    }
    if (state.atlas.showNpcs) {
      npcs.forEach((n) => {
        let x = n.x, y = n.y
        if (state.atlas.move && n.pathgrid && byGrid[n.pathgrid] && byGrid[n.pathgrid].length > 1) {
          const pts = byGrid[n.pathgrid]
          const mover = movers.find((m) => m.grid === n.pathgrid)
          if (mover) {
            const f = ((t / 4000) + mover.t) % 1
            const idx = f * (pts.length - 1)
            const i0 = Math.floor(idx), i1 = Math.min(pts.length - 1, i0 + 1), u = idx - i0
            x = pts[i0].x + (pts[i1].x - pts[i0].x) * u
            y = pts[i0].y + (pts[i1].y - pts[i0].y) * u
          }
        }
        const [px, py] = project(x, y)
        ctx.fillStyle = n.level >= 10 ? "#c9a24a" : "#7ad0a0"
        ctx.beginPath()
        ctx.arc(px, py, n.level >= 10 ? 4 : 3, 0, Math.PI * 2)
        ctx.fill()
      })
    }
    atlasTimer = requestAnimationFrame(frame)
  }
  if (atlasTimer) cancelAnimationFrame(atlasTimer)
  atlasTimer = requestAnimationFrame(frame)
}

function setPrivacy(on) {
  state.privacy = on
  document.body.classList.toggle("privacy-on", on)
  $("privacy-pill").textContent = on ? "Privacy on" : "Privacy off"
  $("privacy-pill").classList.toggle("on", on)
  $("privacy-btn").textContent = on ? "Show private details" : "Hide private details"
}

async function boot() {
  $("privacy-btn").onclick = () => setPrivacy(!state.privacy)
  window.addEventListener("hashchange", paint)
  try {
    const res = await fetch("peq.json")
    state.peq = await res.json()
  } catch (err) {
    $("page").innerHTML = `<div class="win"><div class="win-b">Could not load peq.json. Serve this folder over HTTP.</div></div>`
    return
  }
  $("privacy-pill").nextElementSibling.textContent = "Installer peq · " + state.peq.zone_count + " zones"
  paint()
}

boot()
