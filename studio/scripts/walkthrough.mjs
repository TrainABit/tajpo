import { chromium } from "@playwright/test";
import fs from "node:fs";
import path from "node:path";

const out = process.argv[2] || "/tmp/tajpo-walkthrough";
fs.mkdirSync(out, { recursive: true });

const browser = await chromium.launch({
  channel: "chrome",
  headless: false,
  args: ["--window-size=1440,900", "--window-position=80,40"],
});
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
await page.addInitScript(() => localStorage.clear());
await page.goto("http://127.0.0.1:4173/");
await page.waitForTimeout(800);
await page.screenshot({ path: path.join(out, "onboarding.png") });

await page.getByRole("button", { name: "Continue" }).click();
await page.waitForTimeout(400);
await page.getByRole("button", { name: "Skip" }).click();
await page.waitForTimeout(500);
await page.screenshot({ path: path.join(out, "desktop_notes.png") });

const editor = page.locator("#tajpo-editor");
await editor.click();
await editor.press("Control+A");
await page.getByRole("button", { name: "Tajpo" }).click();
await page.waitForTimeout(400);
await page.screenshot({ path: path.join(out, "menu_open.png") });
await page.getByRole("button", { name: "Open rewrite panel" }).click({ force: true });
await page.getByRole("button", { name: "Replace" }).waitFor({ state: "visible" });
await page.getByRole("button", { name: "Replace" }).waitFor({ state: "attached" });
await page.waitForFunction(() => {
  const button = [...document.querySelectorAll("button")].find((el) => el.textContent?.trim() === "Replace");
  return button && !button.disabled;
});
await page.waitForTimeout(400);
await page.screenshot({ path: path.join(out, "rewrite_panel.png") });

await page.getByRole("button", { name: "Replace" }).click();
await page.waitForTimeout(500);
await page.screenshot({ path: path.join(out, "replaced_notes.png") });

await page.getByRole("button", { name: "Tajpo" }).click();
await page.getByRole("button", { name: "History" }).click();
await page.waitForTimeout(400);
await page.screenshot({ path: path.join(out, "history_drawer.png") });
await page.getByRole("button", { name: "Close" }).first().click();

await page.getByRole("button", { name: "Tajpo" }).click();
await page.getByRole("button", { name: "Settings" }).click();
await page.waitForTimeout(400);
await page.screenshot({ path: path.join(out, "settings_model.png") });
await page.getByRole("tab", { name: "writing" }).click();
await page.waitForTimeout(300);
await page.screenshot({ path: path.join(out, "settings_writing.png") });
await page.getByRole("tab", { name: "appearance" }).click();
await page.waitForTimeout(200);
await page.screenshot({ path: path.join(out, "settings_appearance.png") });
await page.getByRole("tab", { name: "privacy" }).click();
await page.waitForTimeout(300);
await page.screenshot({ path: path.join(out, "settings_privacy.png") });
await page.getByRole("button", { name: "Close" }).click();

await page.getByRole("button", { name: "Switch to light theme" }).click();
await page.waitForTimeout(300);
await page.screenshot({ path: path.join(out, "desktop_light.png") });
await page.getByRole("button", { name: "Switch to dark theme" }).click();
await page.getByRole("tab", { name: "Pages" }).click();
await page.waitForTimeout(300);
await page.screenshot({ path: path.join(out, "desktop_pages.png") });
await page.getByRole("tab", { name: "Notes" }).click();

await editor.click();
await page.keyboard.press("End");
await page.getByRole("button", { name: "Tajpo" }).click();
await page.getByRole("button", { name: "Open rewrite panel" }).click({ force: true });
await page.waitForTimeout(400);
await page.screenshot({ path: path.join(out, "empty_selection_error.png") });

await browser.close();
console.log(`wrote screenshots to ${out}`);
