import {chromium} from "playwright"
import fs from "fs"
import path from "path"
import {fileURLToPath} from "url"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.resolve(__dirname, "..")
const VIDEO_DIR = path.join(ROOT, "videos")
const RAW_DIR = path.join(ROOT, "record", "raw")
const BASE = process.env.SPIRE_URL || "http://localhost:8080"
const ONLY = (process.env.ONLY || "").split(",").map((s) => s.trim()).filter(Boolean)
function loadToken() {
  if (process.env.SPIRE_TOKEN) {
    return process.env.SPIRE_TOKEN
  }
  const authFile = path.join(__dirname, ".auth.json")
  if (fs.existsSync(authFile)) {
    const data = JSON.parse(fs.readFileSync(authFile, "utf8"))
    return data.token || ""
  }
  return ""
}
const TOKEN = loadToken()
if (!TOKEN) {
  console.error("Need SPIRE_TOKEN or record/.auth.json so clips stay logged in")
  process.exit(1)
}

fs.mkdirSync(VIDEO_DIR, {recursive: true})
fs.mkdirSync(RAW_DIR, {recursive: true})

async function sleep(page, ms) {
  await page.waitForTimeout(ms)
}

async function hideLoader(page) {
  await page.waitForFunction(() => {
    const loaders = [...document.querySelectorAll(".loader")]
    return loaders.every((el) => {
      const box = el.getBoundingClientRect()
      const parent = el.parentElement
      const hidden = parent && getComputedStyle(parent).display === "none"
      return hidden || box.height < 4 || box.width < 4
    })
  }, {timeout: 25000}).catch(() => {})
  await sleep(page, 400)
}

async function goto(page, route) {
  await page.goto(BASE + route, {waitUntil: "domcontentloaded", timeout: 60000})
  await hideLoader(page)
  await sleep(page, 600)
}

async function clickText(page, text, exact = false) {
  const loc = page.getByText(text, {exact})
  if (await loc.count()) {
    await loc.first().click({timeout: 8000})
    await sleep(page, 500)
    return true
  }
  return false
}

async function clickTab(page, name) {
  const tab = page.locator(".eq-tab, [role='tab'], .nav-link, a, button").filter({hasText: name}).first()
  if (await tab.count()) {
    await tab.click({timeout: 8000}).catch(() => {})
    await sleep(page, 700)
    return
  }
  await clickText(page, name, true)
}

async function scrollPage(page, steps = 4, dy = 280) {
  for (let i = 0; i < steps; i++) {
    await page.mouse.wheel(0, dy)
    await sleep(page, 450)
  }
}

async function recordClip(name, run) {
  if (ONLY.length && !ONLY.includes(name)) {
    console.log("skip", name)
    return
  }
  console.log("recording", name)
  const raw = path.join(RAW_DIR, name)
  fs.rmSync(raw, {recursive: true, force: true})
  fs.mkdirSync(raw, {recursive: true})

  const browser = await chromium.launch({
    headless: true,
    args: ["--use-angle=d3d11", "--enable-webgl", "--ignore-gpu-blocklist"],
  })
  const context = await browser.newContext({
    viewport: {width: 1440, height: 900},
    deviceScaleFactor: 1,
    recordVideo: {dir: raw, size: {width: 1440, height: 900}},
  })
  await context.addInitScript((token) => {
    localStorage.setItem("spire-privacy-mode", "1")
    localStorage.setItem("spire-theme-mode", "dark")
    localStorage.setItem("spire-web-access-token-localhost:8080", token)
  }, TOKEN)
  const page = await context.newPage()
  await page.addStyleTag({
    content: `
      .char-inv-meta { filter: blur(9px) !important; user-select: none !important; }
      .leaflet-container { background: #2a3340 !important; }
      path.leaflet-interactive { stroke: #d5dbe6 !important; }
    `,
  }).catch(() => {})
  try {
    await run(page)
    await page.screenshot({path: path.join(VIDEO_DIR, "poster-" + name + ".png")}).catch(() => {})
    await sleep(page, 900)
  } catch (err) {
    console.error("clip failed", name, err && err.message)
    await page.screenshot({path: path.join(VIDEO_DIR, name + "-error.png"), fullPage: false}).catch(() => {})
  }
  const video = page.video()
  await context.close()
  await browser.close()
  if (video) {
    const src = await video.path()
    const dest = path.join(VIDEO_DIR, name + ".webm")
    if (fs.existsSync(src)) {
      fs.copyFileSync(src, dest)
      console.log("saved", dest, Math.round(fs.statSync(dest).size / 1024) + "kb")
    }
  }
}

const clips = [
  {
    name: "01-peq-editors",
    run: async (page) => {
      await goto(page, "/editors")
      await sleep(page, 800)
      await scrollPage(page, 8, 320)
      await page.mouse.wheel(0, -2000)
      await sleep(page, 400)
      await sleep(page, 1200)
    },
  },
  {
    name: "02-items-icons",
    run: async (page) => {
      await goto(page, "/items")
      await sleep(page, 700)
      await page.mouse.wheel(0, 180)
      await sleep(page, 500)
      await page.waitForSelector("#item_name", {timeout: 20000})
      const name = page.locator("#item_name")
      await name.click()
      await name.fill("cloak")
      await name.press("Enter")
      await hideLoader(page)
      await page.waitForSelector("table tbody tr, .eq-item-card, .item-preview", {timeout: 20000}).catch(() => {})
      await sleep(page, 1800)
      await page.mouse.wheel(0, 500)
      await sleep(page, 900)
      const cards = page.getByTitle("Show as cards")
      if (await cards.count()) {
        await cards.click()
        await sleep(page, 1600)
      }
      await page.mouse.wheel(0, 350)
      await sleep(page, 800)
    },
  },
  {
    name: "03-evolving-items",
    run: async (page) => {
      await goto(page, "/items/evolving")
      await hideLoader(page)
      await sleep(page, 1000)
      await scrollPage(page, 6, 300)
      await sleep(page, 700)
    },
  },
  {
    name: "04-inventory",
    run: async (page) => {
      await goto(page, "/editors/inventory?c=681696")
      await hideLoader(page)
      await sleep(page, 1400)
      await page.addStyleTag({
        content: `
          .char-inv-meta, .char-inv-hit-text span { filter: blur(8px) !important; }
          .char-inv-hit-text b { filter: none !important; }
        `,
      })
      for (const label of ["Worn", "Bags", "Bank", "Shared", "Parcels"]) {
        const btn = page.locator("button, .char-inv-tab").filter({hasText: label}).first()
        if (await btn.count()) {
          await btn.click().catch(() => {})
          await sleep(page, 900)
        }
      }
      const worn = page.locator("button, .char-inv-tab").filter({hasText: "Worn"}).first()
      if (await worn.count()) {
        await worn.click().catch(() => {})
        await sleep(page, 800)
      }
      await sleep(page, 700)
    },
  },
  {
    name: "05-zone-2d-blackburrow",
    run: async (page) => {
      await goto(page, "/zone/blackburrow?v=0")
      await page.waitForSelector(".zone-editor-map-hud, .leaflet-container", {timeout: 35000}).catch(() => {})
      await page.evaluate(() => {
        window.dispatchEvent(new Event("resize"))
        document.querySelectorAll(".leaflet-container").forEach((el) => {
          const vm = el.__vue__
          const map = vm && (vm.mapObject || (vm.$children && vm.$children[0] && vm.$children[0].mapObject))
          if (map && map.invalidateSize) map.invalidateSize()
        })
      })
      await sleep(page, 2800)
      const canvas = page.locator(".leaflet-container").first()
      if (await canvas.count()) {
        const box = await canvas.boundingBox()
        if (box && box.height > 80) {
          await page.mouse.move(box.x + box.width * 0.5, box.y + box.height * 0.48)
          await page.mouse.down()
          await page.mouse.move(box.x + box.width * 0.68, box.y + box.height * 0.36, {steps: 16})
          await page.mouse.up()
          await sleep(page, 700)
          await page.mouse.wheel(0, -420)
          await sleep(page, 900)
          await page.mouse.wheel(0, 220)
          await sleep(page, 600)
        }
      }
      for (const name of ["NPCs", "Items", "Tasks", "Sold", "Spells", "Zone Connections", "Zone"]) {
        const tab = page.locator(".eq-tab-box-fancy a, .eq-tab-box-fancy li").filter({hasText: name}).first()
        if (await tab.count()) {
          await tab.click().catch(() => {})
          await sleep(page, 900)
          await page.mouse.wheel(0, 280)
          await sleep(page, 450)
        }
      }
      await sleep(page, 800)
    },
  },
  {
    name: "06-zone-3d-blackburrow",
    run: async (page) => {
      await goto(page, "/zone/blackburrow/atlas")
      await page.waitForSelector(".atlas-viewport, canvas", {timeout: 20000})
      await page.waitForFunction(() => {
        const s = document.querySelector(".atlas-status")
        const t = s ? s.textContent || "" : ""
        return t.includes("terrain") || t.includes("NPCs") || t.includes("objects") || t.includes("error") || t.includes("not found")
      }, {timeout: 45000}).catch(() => {})
      await sleep(page, 1500)
      await page.evaluate(() => {
        const el = document.querySelector(".atlas-page")
        const vm = el && el.__vue__
        if (vm && vm.controls) {
          vm.controls.autoRotate = true
          vm.controls.autoRotateSpeed = 8
          if (vm.brightLighting === false) {
            vm.brightLighting = true
            if (vm.applyLighting) vm.applyLighting()
          }
        }
      })
      const vp = page.locator(".atlas-viewport, canvas").first()
      const box = await vp.boundingBox()
      if (box) {
        await page.mouse.move(box.x + box.width * 0.55, box.y + box.height * 0.45)
        await sleep(page, 8000)
        await page.mouse.down()
        await page.mouse.move(box.x + box.width * 0.25, box.y + box.height * 0.4, {steps: 18})
        await page.mouse.up()
        await sleep(page, 1500)
        await page.mouse.wheel(0, -500)
        await sleep(page, 1200)
        await page.mouse.wheel(0, 350)
        await sleep(page, 1000)
      } else {
        await sleep(page, 8000)
      }
      for (const label of ["Client scenery", "NPCs", "Wireframe", "Bright lighting"]) {
        const boxLabel = page.locator("label").filter({hasText: label}).first()
        if (await boxLabel.count()) {
          await boxLabel.click().catch(() => {})
          await sleep(page, 700)
          await boxLabel.click().catch(() => {})
          await sleep(page, 500)
        }
      }
      await sleep(page, 2000)
    },
  },
  {
    name: "07-server-files",
    run: async (page) => {
      await goto(page, "/admin/server-files")
      await hideLoader(page)
      await sleep(page, 1000)
      await sleep(page, 800)
      const openFolder = page.locator("table tbody tr").filter({hasText: /abysmal|akanon|crushbone|qeynos|freportn/i}).first()
      if (await openFolder.count()) {
        await openFolder.locator("button").click()
        await sleep(page, 1500)
      } else {
        const anyOpen = page.locator("button").filter({hasText: "Open"}).first()
        if (await anyOpen.count()) {
          await anyOpen.click()
          await sleep(page, 1500)
        }
      }
      const editBtn = page.locator("button").filter({hasText: "Edit"}).first()
      if (await editBtn.count()) {
        await editBtn.click()
        await sleep(page, 2200)
        await page.mouse.wheel(0, 240)
        await sleep(page, 900)
      }
    },
  },
  {
    name: "08-server-config",
    run: async (page) => {
      await goto(page, "/admin/configuration/server?s=World+Server")
      await hideLoader(page)
      await sleep(page, 900)
      for (const name of ["Networking", "Key", "Telnet / Websockets", "TCP Connections", "Loginserver #1"]) {
        await clickTab(page, name)
        await sleep(page, 650)
      }
      for (const name of ["Zone Server", "UCS", "Database", "Server Files"]) {
        await clickTab(page, name)
        await hideLoader(page)
        await sleep(page, 900)
        await page.mouse.wheel(0, 220)
        await sleep(page, 400)
      }
      await clickTab(page, "World Server")
      await clickTab(page, "Server Naming")
      await sleep(page, 800)
    },
  },
]

for (const clip of clips) {
  await recordClip(clip.name, clip.run)
}

console.log("done")
