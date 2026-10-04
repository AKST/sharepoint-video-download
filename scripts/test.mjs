// Runs the COMPILED out/extension/inject.js in a stub page and checks the
// download URL it builds. See docs/architecture.md for the derivation itself.
//
//   node --test scripts/test.mjs      (after scripts/build.sh)

import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { createContext, runInContext } from "node:vm";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const INJECT = join(dirname(fileURLToPath(import.meta.url)), "..", "out", "extension", "inject.js");
const source = readFileSync(INJECT, "utf8");

/** Run inject.js as if the tab were showing `href`. */
function run(href) {
  let navigated = null;
  const element = () => ({ id: "", textContent: "", style: { cssText: "" }, remove() {} });
  const toasts = [];
  const context = createContext({
    URL,
    console: { log() {}, error() {} },
    setTimeout() {},
    location: { href, assign: (url) => { navigated = url; } },
    document: {
      getElementById: () => null,
      createElement: () => { const el = element(); toasts.push(el); return el; },
      documentElement: { append() {} },
    },
  });
  return { outcome: runInContext(source, context), navigated, toasts };
}

// The real page this was built for: OneDrive for Business, a library called
// "Documents", a file name carrying spaces and a dash.
const UNSW =
  "https://unsw-my.sharepoint.com/personal/z3522766_ad_unsw_edu_au/_layouts/15/stream.aspx" +
  "?id=%2Fpersonal%2Fz3522766%5Fad%5Funsw%5Fedu%5Fau%2FDocuments%2FECON2112%20Videos" +
  "%2FLecture%20Video%20%2D%20September%2023%2Emov&nav=eyJyZWZlcnJhbEluZm8iOnt9fQ&ga=1";

test("the real UNSW lecture page", () => {
  const { outcome, navigated } = run(UNSW);
  assert.equal(outcome.ok, true);
  assert.equal(outcome.name, "Lecture Video - September 23.mov");
  assert.equal(navigated, outcome.href);

  const url = new URL(navigated);
  assert.equal(
    url.origin + url.pathname,
    "https://unsw-my.sharepoint.com/personal/z3522766_ad_unsw_edu_au/_layouts/15/download.aspx",
  );
  assert.equal(
    url.searchParams.get("SourceUrl"),
    "https://unsw-my.sharepoint.com/personal/z3522766_ad_unsw_edu_au/Documents/" +
      "ECON2112 Videos/Lecture Video - September 23.mov",
  );
  // The player's own tracking parameters are not carried over.
  assert.equal(url.searchParams.get("nav"), null);
});

test("a team site whose library is called Shared Documents", () => {
  // Splitting the file path on "/Documents/" finds nothing here, because the
  // character before "Documents" is a space. Reading the page path does.
  const { outcome, navigated } = run(
    "https://org.sharepoint.com/sites/ECON2112/_layouts/15/stream.aspx" +
      "?id=%2Fsites%2FECON2112%2FShared%20Documents%2Fweek1.mp4",
  );
  assert.equal(outcome.ok, true);
  const url = new URL(navigated);
  assert.equal(
    url.origin + url.pathname,
    "https://org.sharepoint.com/sites/ECON2112/_layouts/15/download.aspx",
  );
  assert.equal(
    url.searchParams.get("SourceUrl"),
    "https://org.sharepoint.com/sites/ECON2112/Shared Documents/week1.mp4",
  );
});

test("a subsite, where the file path alone would guess the wrong web", () => {
  const { navigated } = run(
    "https://org.sharepoint.com/sites/Faculty/ECON/_layouts/15/stream.aspx" +
      "?id=%2Fsites%2FFaculty%2FECON%2FShared%20Documents%2Flecture.mp4",
  );
  assert.equal(
    new URL(navigated).pathname,
    "/sites/Faculty/ECON/_layouts/15/download.aspx",
  );
});

test("the root site collection, which has no /sites/ prefix", () => {
  const { navigated } = run(
    "https://org.sharepoint.com/_layouts/15/stream.aspx?id=%2FShared%20Documents%2Fa.mp4",
  );
  assert.equal(new URL(navigated).pathname, "/_layouts/15/download.aspx");
});

test("an ?id= that is a whole URL rather than a path", () => {
  const { navigated } = run(
    "https://org.sharepoint.com/sites/X/_layouts/15/stream.aspx" +
      "?id=https%3A%2F%2Forg.sharepoint.com%2Fsites%2FX%2FShared%20Documents%2Fb.mp4",
  );
  assert.equal(
    new URL(navigated).searchParams.get("SourceUrl"),
    "https://org.sharepoint.com/sites/X/Shared Documents/b.mp4",
  );
});

test("a folder listing, which has no file to download", () => {
  const { outcome, navigated, toasts } = run(
    "https://org.sharepoint.com/sites/X/Shared%20Documents/Forms/AllItems.aspx",
  );
  assert.equal(outcome.ok, false);
  assert.equal(outcome.reason, "no-id");
  assert.equal(navigated, null, "it must not navigate when there is nothing to fetch");
  assert.match(toasts[0].textContent, /Open the video itself/);
});

test("a file name containing a percent sign", () => {
  // filePath arrives decoded, so decoding the last segment a second time to get
  // a display name would throw URIError on this and lose the download entirely.
  const { outcome, navigated } = run(
    "https://org.sharepoint.com/sites/X/_layouts/15/stream.aspx" +
      "?id=%2Fsites%2FX%2FShared%20Documents%2F100%25%20exam.mp4",
  );
  assert.equal(outcome.ok, true);
  assert.equal(outcome.name, "100% exam.mp4");
  assert.equal(
    new URL(navigated).searchParams.get("SourceUrl"),
    "https://org.sharepoint.com/sites/X/Shared Documents/100% exam.mp4",
  );
});
