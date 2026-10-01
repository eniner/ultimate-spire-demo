import {chromium} from "playwright"
import fs from "fs"
import path from "path"
import {fileURLToPath} from "url"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const TOKEN = JSON.parse(fs.readFileSync(path.join(__dirname, ".auth.json"), "utf8")).token
const OUT = path.join(__dirname, "..", "videos")

const pages = [
  ["/editors", "editors"],
  ["/items", "items"],
  ["/items/evolving", "evolving"],
  ["/editors/inventory?c=681696", "inventory"],
  ["/zone/blackburrow", "zone2d"],
  ["/zone/blackburrow/atlas", "zone3d"],
  ["/admin/server-files", "files"],
  ["/admin/configuration/server", "config"],
]

const browser = await chromium.launch({headless: true, args: ["--use-angle=d3d11", "--enable-webgl"]})
const context = await browser.newContext({viewport: {width: 1440, height: 900}})
await context.addInitScript((token) => {
  localStorage.setItem("spire-privacy-mode", "1")
  localStorage.setItem("spire-theme-mode", "dark")
  localStorage.setItem("spire-web-access-token-localhost:8080", token)
}, TOKEN)
const page = await context.newPage()
for (const [url, name] of pages) {
  await page.goto("http://localhost:8080" + url, {waitUntil: "domcontentloaded", timeout: 60000})
  await page.waitForTimeout(3500)
  console.log(name, page.url(), await page.title())
  await page.screenshot({path: path.join(OUT, "debug-" + name + ".png")})
}
await browser.close()
