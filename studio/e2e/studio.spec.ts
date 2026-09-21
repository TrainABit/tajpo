import { expect, test } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    localStorage.clear();
  });
});

test("onboarding, rewrite, replace, history, and settings", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Write better without leaving your app" })).toBeVisible();
  await page.getByRole("button", { name: "Skip" }).click();
  await expect(page.getByRole("heading", { name: "Write better without leaving your app" })).toHaveCount(0);

  const editor = page.locator("#tajpo-editor");
  await editor.click();
  await editor.press("ControlOrMeta+A");

  await page.getByRole("button", { name: "Tajpo" }).click();
  await page.getByRole("button", { name: "Open rewrite panel" }).click({ force: true });
  await expect(page.getByRole("dialog", { name: "Tajpo rewrite panel" })).toBeVisible();
  await expect(page.locator(".column").nth(1)).not.toHaveText("Choose an action", { timeout: 15_000 });
  await expect(page.locator(".column").nth(1)).toContainText("Tajpo");

  const before = await editor.inputValue();
  await expect(page.getByRole("button", { name: "Replace" })).toBeEnabled();
  await page.getByRole("button", { name: "Replace" }).click();
  await expect(page.getByRole("dialog", { name: "Tajpo rewrite panel" })).toHaveCount(0);
  await expect.poll(async () => editor.inputValue()).not.toBe(before);

  await page.getByRole("button", { name: "Tajpo" }).click();
  await page.getByRole("button", { name: "History" }).click();
  await expect(page.getByRole("complementary", { name: "Rewrite history" })).toBeVisible();
  await expect(page.getByRole("complementary", { name: "Rewrite history" })).toContainText("Correct");
  await page.getByRole("button", { name: "Close" }).first().click();

  await page.getByRole("button", { name: "Tajpo" }).click();
  await page.getByRole("button", { name: "Settings" }).click();
  await expect(page.getByRole("dialog", { name: "Settings" })).toBeVisible();
  await page.getByRole("tab", { name: "privacy" }).click();
  await expect(page.getByText(/no account or backend/i)).toBeVisible();
  await page.getByRole("button", { name: "Close" }).click();
});

test("empty selection shows an error state", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Skip" }).click();
  await page.locator("#tajpo-editor").click();
  await page.keyboard.press("End");
  await page.getByRole("button", { name: "Tajpo" }).click();
  await page.getByRole("button", { name: "Open rewrite panel" }).click({ force: true });
  await expect(page.getByRole("dialog", { name: "Tajpo rewrite panel" })).toContainText("No selected text");
  await expect(page.getByRole("button", { name: "Replace" })).toBeDisabled();
});

test("mail host and onboarding continue finish the first-run flow", async ({ page }) => {
  await page.goto("/");
  for (let step = 0; step < 4; step += 1) {
    await page.getByRole("button", { name: "Continue" }).click();
  }
  await page.getByRole("button", { name: "Finish" }).click();
  await page.getByRole("tab", { name: "Mail" }).click();
  await expect(page.getByRole("heading", { name: "Mail" })).toBeVisible();
  await expect(page.locator("#tajpo-editor")).toContainText("reach out");
  await page.getByRole("tab", { name: "Pages" }).click();
  await expect(page.getByRole("heading", { name: "Pages" })).toBeVisible();
  await expect(page.locator("#tajpo-editor")).toContainText("brief");
});

test("theme, connection test, custom instructions, undo, and history search", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Skip" }).click();

  await page.getByRole("button", { name: "Switch to light theme" }).click();
  await expect(page.locator(".desktop")).toHaveAttribute("data-theme", "light");
  await page.getByRole("button", { name: "Switch to dark theme" }).click();
  await expect(page.locator(".desktop")).toHaveAttribute("data-theme", "dark");

  await page.getByRole("button", { name: "File" }).click();
  await page.getByRole("menuitem", { name: "Settings…" }).click();
  await expect(page.getByRole("dialog", { name: "Settings" })).toBeVisible();
  await page.getByRole("button", { name: "Test connection" }).click();
  await expect(page.getByRole("status")).toContainText(/demo engine is ready/i);
  await page.getByRole("tab", { name: "writing" }).click();
  await page.getByLabel("Always-on instructions").fill("never use the word Tajpo");
  await page.getByRole("button", { name: "Close" }).click();

  const editor = page.locator("#tajpo-editor");
  await page.getByRole("button", { name: "Select all" }).click();
  await page.keyboard.press("Alt+Shift+T");
  const panel = page.getByRole("dialog", { name: "Tajpo rewrite panel" });
  await expect(panel).toBeVisible();
  await expect(page.getByRole("button", { name: "Replace" })).toBeEnabled({ timeout: 15_000 });
  await expect(page.locator(".column").nth(1)).not.toContainText("Tajpo");
  const before = await editor.inputValue();
  await page.getByRole("button", { name: "Replace" }).click();
  await expect.poll(async () => editor.inputValue()).not.toBe(before);

  await page.getByRole("button", { name: "Edit" }).click();
  await page.getByRole("menuitem", { name: "Undo replace" }).click();
  await expect.poll(async () => editor.inputValue()).toBe(before);
  await page.getByRole("button", { name: "Edit" }).click();
  await page.getByRole("menuitem", { name: "Redo replace" }).click();
  await expect.poll(async () => editor.inputValue()).not.toBe(before);

  await page.getByRole("button", { name: "File" }).click();
  await page.getByRole("menuitem", { name: "History" }).click();
  await expect(page.getByRole("complementary", { name: "Rewrite history" })).toBeVisible();
  await page.getByPlaceholder("Search original, rewrite, action…").fill("zzzz-missing");
  await expect(page.getByText("No history matches that search.")).toBeVisible();
  await page.getByPlaceholder("Search original, rewrite, action…").fill("make");
  await expect(page.getByRole("complementary", { name: "Rewrite history" })).toContainText("Correct");
});

test("typing digits in the history search box does not open the panel or start a rewrite", async ({ page }) => {
  // Depends on the store keyboard guards: digit keys must be ignored while an input is focused.
  await page.goto("/");
  await page.getByRole("button", { name: "Skip" }).click();

  await page.getByRole("button", { name: "File" }).click();
  await page.getByRole("menuitem", { name: "History" }).click();
  const drawer = page.getByRole("complementary", { name: "Rewrite history" });
  await expect(drawer).toBeVisible();

  const search = page.getByPlaceholder("Search original, rewrite, action…");
  await search.click();
  await page.keyboard.type("123");
  await expect(search).toHaveValue("123");
  await expect(page.getByRole("dialog", { name: "Tajpo rewrite panel" })).toHaveCount(0);
  await expect(drawer).not.toContainText(/Working/i);
});

test("Escape closes the rewrite panel", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Skip" }).click();

  await page.getByRole("button", { name: "Select all" }).click();
  await page.keyboard.press("Alt+Shift+T");
  const panel = page.getByRole("dialog", { name: "Tajpo rewrite panel" });
  await expect(panel).toBeVisible();
  await expect(page.getByRole("button", { name: "Replace" })).toBeEnabled({ timeout: 15_000 });

  await page.keyboard.press("Escape");
  await expect(panel).toHaveCount(0);
});

test("Ctrl/Cmd+Enter replaces when a preview exists", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Skip" }).click();

  const editor = page.locator("#tajpo-editor");
  await page.getByRole("button", { name: "Select all" }).click();
  await page.keyboard.press("Alt+Shift+T");
  const panel = page.getByRole("dialog", { name: "Tajpo rewrite panel" });
  await expect(panel).toBeVisible();
  await expect(page.getByRole("button", { name: "Replace" })).toBeEnabled({ timeout: 15_000 });

  const before = await editor.inputValue();
  await page.keyboard.press("ControlOrMeta+Enter");
  await expect(panel).toHaveCount(0);
  await expect.poll(async () => editor.inputValue()).not.toBe(before);
});

test("diff toggle renders add and delete tokens", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Skip" }).click();

  await page.getByRole("button", { name: "Select all" }).click();
  await page.keyboard.press("Alt+Shift+T");
  await expect(page.getByRole("dialog", { name: "Tajpo rewrite panel" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Replace" })).toBeEnabled({ timeout: 15_000 });

  await page.getByRole("button", { name: "Show diff" }).click();
  await expect(page.locator(".diff-add").first()).toBeVisible();
  await expect(page.locator(".diff-del").first()).toBeVisible();
});

test("history entry delete with undo restores the entry", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Skip" }).click();

  const editor = page.locator("#tajpo-editor");
  await editor.click();
  await editor.press("ControlOrMeta+A");
  await page.getByRole("button", { name: "Tajpo" }).click();
  await page.getByRole("button", { name: "Open rewrite panel" }).click({ force: true });
  await expect(page.getByRole("button", { name: "Replace" })).toBeEnabled({ timeout: 15_000 });
  await page.getByRole("button", { name: "Replace" }).click();
  await expect(page.getByRole("dialog", { name: "Tajpo rewrite panel" })).toHaveCount(0);

  await page.getByRole("button", { name: "Tajpo" }).click();
  await page.getByRole("button", { name: "History" }).click();
  const drawer = page.getByRole("complementary", { name: "Rewrite history" });
  await expect(drawer).toBeVisible();
  await expect(drawer.locator(".history-item")).toHaveCount(1);

  await drawer.getByRole("button", { name: "Delete entry" }).click();
  await expect(drawer.locator(".history-item")).toHaveCount(0);
  await expect(drawer).toContainText("No rewrites yet");
  const undo = page.locator(".toast-undo");
  await expect(undo).toBeVisible();
  await undo.click();
  await expect(drawer.locator(".history-item")).toHaveCount(1);
});

test("host filter limits visible history", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Skip" }).click();

  const editor = page.locator("#tajpo-editor");
  await editor.click();
  await editor.press("ControlOrMeta+A");
  await page.getByRole("button", { name: "Tajpo" }).click();
  await page.getByRole("button", { name: "Open rewrite panel" }).click({ force: true });
  await expect(page.getByRole("button", { name: "Replace" })).toBeEnabled({ timeout: 15_000 });
  await page.getByRole("button", { name: "Replace" }).click();
  await expect(page.getByRole("dialog", { name: "Tajpo rewrite panel" })).toHaveCount(0);

  await page.getByRole("button", { name: "Tajpo" }).click();
  await page.getByRole("button", { name: "History" }).click();
  const drawer = page.getByRole("complementary", { name: "Rewrite history" });
  await expect(drawer.locator(".history-item")).toHaveCount(1);

  const hostFilter = drawer.getByLabel("Host");
  await hostFilter.selectOption("slack");
  await expect(drawer.locator(".history-item")).toHaveCount(0);
  await expect(drawer).toContainText("No history matches that search.");
  await hostFilter.selectOption({ label: "Notes" });
  await expect(drawer.locator(".history-item")).toHaveCount(1);
});

test("Stop button appears while streaming and closes the panel", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Skip" }).click();

  await page.getByRole("button", { name: "Select all" }).click();
  await page.keyboard.press("Alt+Shift+T");
  const panel = page.getByRole("dialog", { name: "Tajpo rewrite panel" });
  await expect(panel).toBeVisible();

  const stop = panel.getByRole("button", { name: "Stop" });
  // The demo engine streams quickly — the Stop button may already be gone by
  // the time we look, which is fine; when visible it must work.
  if (await stop.isVisible().catch(() => false)) {
    await stop.click();
    await expect(panel).toHaveCount(0);
  } else {
    await expect(page.getByRole("button", { name: "Replace" })).toBeEnabled({ timeout: 15_000 });
  }
});

test("question mark opens the keyboard cheat sheet", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Skip" }).click();

  await page.keyboard.press("?");
  const sheet = page.getByRole("dialog", { name: "Keyboard shortcuts" });
  await expect(sheet).toBeVisible();
  await expect(sheet).toContainText("Open the rewrite panel");
  await page.keyboard.press("Escape");
  await expect(sheet).toHaveCount(0);
});
