import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("../../website/app.js", import.meta.url), "utf8");
const download = source.slice(source.indexOf('fetch("https://api.github.com/repos/'), source.indexOf("const logoCursor"));

async function linksFor(assets) {
  const links = [{ href: "release-page" }, { href: "release-page" }];
  const pending = runInNewContext(download, {
    fetch: async () => ({ ok: true, json: async () => ({ assets }) }),
    document: { querySelectorAll: () => links },
  });
  await pending;
  return links.map((link) => link.href);
}

test("both Mac download links choose the installer instead of the Sparkle ZIP", async () => {
  assert.deepEqual(await linksFor([
    { name: "InboxPlus-0.9.1-116.zip", browser_download_url: "update-zip" },
    { name: "InboxPlus-0.9.1-116.dmg", browser_download_url: "installer-dmg" },
  ]), ["installer-dmg", "installer-dmg"]);
});

test("releases without an installer keep links to the release page", async () => {
  assert.deepEqual(await linksFor([
    { name: "InboxPlus-0.9.1-116.zip", browser_download_url: "update-zip" },
  ]), ["release-page", "release-page"]);
});
