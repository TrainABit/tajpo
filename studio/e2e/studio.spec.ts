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
  await editor.press("Control+A");

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
  await expect(page.getByRole("complementary")).toContainText("Correct");
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
});
