import assert from "node:assert/strict";
import { test } from "node:test";

import { handleFeedback } from "../../website/api/feedback.mjs";

const env = {
  FEEDBACK_DISABLED: "0",
  FEEDBACK_GITHUB_ISSUES_TOKEN: "issues-token-secret",
  FEEDBACK_GITHUB_MEDIA_TOKEN: "media-token-secret",
  FEEDBACK_MEDIA_REPO: "Tsha0/InboxPlus-feedback-media",
  FEEDBACK_RESEND_API_KEY: "resend-key-secret",
  FEEDBACK_EMAIL_TO: "developer@example.com",
};

const issueUrl = "https://github.com/Tsha0/InboxPlus/issues/42";
const upstreamSecret = "upstream-body-with-internal-detail";
const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

function png(size = 64) {
  const bytes = Buffer.alloc(size, 7);
  Buffer.from(pngSignature).copy(bytes);
  return bytes;
}

function rendered(markdown) {
  return markdown.replace(/\\(.)/g, "$1");
}

function request(overrides = {}) {
  return {
    kind: "bug",
    text: "Sending a photo fails\nIt spins forever.",
    app: { version: "1.4.0", build: "88", platform: "macOS 26.1" },
    ...overrides,
  };
}

function fakeFetch(failures = {}) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    const call = { url, method: init.method, headers: init.headers, body: JSON.parse(init.body) };
    calls.push(call);
    const destination = url.includes("/contents/")
      ? "media"
      : url.endsWith("/issues")
        ? "issue"
        : "email";
    if (failures[destination] === "reject") throw new Error(upstreamSecret);
    if (failures[destination]) {
      return { ok: false, status: failures[destination], json: async () => ({ message: upstreamSecret }) };
    }
    const payload = {
      media: { content: {} },
      issue: { html_url: issueUrl },
      email: { id: "email-id" },
    }[destination];
    return { ok: true, status: destination === "email" ? 200 : 201, json: async () => payload };
  };
  return { calls, fetchImpl };
}

function post(body, options = {}) {
  const { calls, fetchImpl } = fakeFetch(options.failures);
  const bodyText = typeof body === "string" ? body : JSON.stringify(body);
  return handleFeedback(
    { method: options.method ?? "POST", bodyText },
    options.env ?? env,
    fetchImpl,
  ).then((response) => ({ response, calls }));
}

const issueKinds = [
  { kind: "bug", labels: ["external", "bug"], prefix: "[Bug] " },
  { kind: "feature", labels: ["external", "enhancement"], prefix: "[Feature request] " },
  { kind: "needsWork", labels: ["external"], prefix: "[Needs work] " },
];

for (const { kind, labels, prefix } of issueKinds) {
  test(`${kind} files one labeled issue in Tsha0/InboxPlus`, async () => {
    const { response, calls } = await post(request({ kind }));

    assert.deepEqual(response, { status: 200, body: { issueUrl } });
    assert.equal(calls.length, 1);
    const [issue] = calls;
    assert.equal(issue.method, "POST");
    assert.equal(issue.url, "https://api.github.com/repos/Tsha0/InboxPlus/issues");
    assert.equal(issue.headers.Authorization, "Bearer issues-token-secret");
    assert.equal(issue.headers["X-GitHub-Api-Version"], "2022-11-28");
    assert.ok(issue.headers["User-Agent"]);
    assert.deepEqual(issue.body.labels, labels);
    assert.equal(issue.body.title, `${prefix}Sending a photo fails`);
    assert.match(issue.body.body, /Sending a photo fails\nIt spins forever\./);
    assert.ok(rendered(issue.body.body).includes("Inbox+ 1.4.0 (build 88) on macOS 26.1"));
  });
}

test("praise sends one email and never calls GitHub", async () => {
  const { response, calls } = await post(
    request({ kind: "praise", text: "Love the app!", diagnostics: { locale: "en_US" } }),
  );

  assert.deepEqual(response, { status: 200, body: {} });
  assert.equal(calls.length, 1);
  const [email] = calls;
  assert.equal(email.url, "https://api.resend.com/emails");
  assert.equal(email.headers.Authorization, "Bearer resend-key-secret");
  assert.equal(email.body.to, "developer@example.com");
  assert.equal(email.body.from, "Inbox+ Feedback <onboarding@resend.dev>");
  assert.equal(email.body.subject, "[Praise] Love the app!");
  assert.match(email.body.text, /^Love the app!/);
  assert.match(email.body.text, /Inbox\+ 1\.4\.0 \(build 88\) on macOS 26\.1/);
  assert.match(email.body.text, /"locale": "en_US"/);
  assert.equal(email.body.attachments, undefined);
});

test("praise attaches the screenshot and honors a configured sender", async () => {
  const image = png();
  const { response, calls } = await post(
    request({ kind: "praise", image: image.toString("base64") }),
    { env: { ...env, FEEDBACK_EMAIL_FROM: "Inbox+ <feedback@inboxplus.chat>" } },
  );

  assert.equal(response.status, 200);
  assert.equal(calls.length, 1);
  assert.ok(!calls.some((call) => call.url.includes("github.com")));
  assert.equal(calls[0].body.from, "Inbox+ <feedback@inboxplus.chat>");
  assert.deepEqual(calls[0].body.attachments, [
    { filename: "screenshot.png", content: image.toString("base64") },
  ]);
});

test("a screenshot is committed to the media repo before the issue links it", async () => {
  const image = png();
  const { response, calls } = await post(request({ image: image.toString("base64") }));

  assert.deepEqual(response, { status: 200, body: { issueUrl } });
  assert.equal(calls.length, 2);
  const [upload, issue] = calls;
  assert.equal(upload.method, "PUT");
  assert.match(
    upload.url,
    /^https:\/\/api\.github\.com\/repos\/Tsha0\/InboxPlus-feedback-media\/contents\/\d{4}\/\d{2}\/[0-9a-f-]{36}\.png$/,
  );
  assert.equal(upload.headers.Authorization, "Bearer media-token-secret");
  assert.equal(upload.body.content, image.toString("base64"));
  assert.ok(upload.body.message);
  assert.ok(issue.url.endsWith("/repos/Tsha0/InboxPlus/issues"));
  const path = upload.url.split("/contents/")[1];
  const screenshotUrl = `https://github.com/${env.FEEDBACK_MEDIA_REPO}/blob/HEAD/${path}`;
  assert.ok(issue.body.body.includes(`Screenshot (visible to maintainers only): ${screenshotUrl}`));
});

test("each upload gets its own path", async () => {
  const image = png().toString("base64");
  const first = await post(request({ image }));
  const second = await post(request({ image }));

  assert.notEqual(first.calls[0].url, second.calls[0].url);
});

test("mentions in the title, text, and app fields cannot ping GitHub users", async () => {
  const { calls } = await post(
    request({
      text: "@octocat broke it, cc @Tsha0/maintainers and @someone",
      app: { version: "1.0", build: "1", platform: "@ghost" },
      diagnostics: { note: "@hubot" },
    }),
  );

  const [{ body }] = calls;
  assert.doesNotMatch(body.title, /@[A-Za-z0-9]/);
  assert.doesNotMatch(body.body, /@[A-Za-z0-9]/);
  assert.match(body.title, /octocat broke it/);
  assert.match(body.body, /Tsha0\/maintainers/);
});

test("user text cannot close its block or hide the footer", async () => {
  const text = "Steps\n````\n</details>\n<!--\n# Heading\n```json";
  const { calls } = await post(
    request({ text, diagnostics: { log: "```\n</details>" } }),
  );

  const body = calls[0].body.body;
  const fence = body.match(/^`+/)[0];
  assert.ok(fence.length > 4, "fence is longer than any backtick run in the text");
  const closing = body.indexOf(`\n${fence}\n`);
  assert.ok(closing > body.indexOf(text), "text sits inside the opening fence");
  assert.ok(body.indexOf("on macOS") > closing, "footer follows the closed block");
  assert.ok(body.trimEnd().endsWith("</details>"), "diagnostics details stays last");
  assert.match(body, /<details>\n<summary>Diagnostics<\/summary>\n\n````json\n/);
});

test("app fields cannot inject markdown or HTML into the footer", async () => {
  const { calls } = await post(
    request({ app: { version: "<img src=x>", build: "[a](b)", platform: "\n\n# x" } }),
  );

  const body = calls[0].body.body;
  assert.doesNotMatch(body, /(^|[^\\])[<[#]/m, "every markup character is escaped");
  assert.ok(rendered(body).includes("Inbox+ <img src=x> (build [a](b)) on # x"));
});

test("long first lines are trimmed in the title", async () => {
  const { calls } = await post(request({ text: `${"a".repeat(120)}\nsecond line` }));

  const { title } = calls[0].body;
  assert.ok(title.startsWith("[Bug] aaaa"));
  assert.ok([...title].length <= "[Bug] ".length + 70);
  assert.ok(title.endsWith("…"));
});

test("text at the length limit and the largest image are accepted", async () => {
  const { response } = await post(
    request({ text: "x".repeat(5000), image: png(3 * 1024 * 1024).toString("base64") }),
  );

  assert.equal(response.status, 200);
});

test("diagnostics fit alongside long multibyte Details and a maximum-size screenshot", async () => {
  const { response, calls } = await post(request({
    text: `a${"\u0301".repeat(6)}`.repeat(5000),
    image: png(3 * 1024 * 1024).toString("base64"),
    diagnostics: { note: "x".repeat(2000) },
  }));

  assert.equal(response.status, 200);
  assert.equal(calls.length, 2);
});

test("5000 family emoji fit alongside diagnostics and a maximum-size screenshot", async () => {
  const text = "👨‍👩‍👧‍👦".repeat(5000);
  const { response, calls } = await post(request({
    text,
    image: png(3 * 1024 * 1024).toString("base64"),
    diagnostics: { note: "x".repeat(2000) },
  }));

  assert.deepEqual(response, { status: 200, body: { issueUrl } });
  assert.equal(calls.length, 2);
  assert.ok(calls[1].body.body.includes(text));
});

test("public feedback that would exceed the issue body limit is rejected before upload", async () => {
  const text = `a${"\u0301".repeat(12)}`.repeat(5000);
  const diagnostics = { note: "x".repeat(2000) };
  for (const image of [undefined, png().toString("base64")]) {
    const { response, calls } = await post(request({ text, diagnostics, image }));
    assert.deepEqual(response, { status: 413, body: { error: "too_large" } });
    assert.equal(calls.length, 0);
  }

  const { response, calls } = await post(request({ kind: "praise", text, diagnostics }));
  assert.deepEqual(response, { status: 200, body: {} });
  assert.equal(calls.length, 1);
  assert.ok(calls[0].body.text.includes(text));
});

test("the issue body limit includes formatting and the screenshot link", async () => {
  const text = `\`\`\`@dev ${`a${"\u0301".repeat(12)}`.repeat(4992)}`;
  const sample = await post(request({ text, diagnostics: { note: "" } }));
  const remaining = 65_536 - [...sample.calls[0].body.body].length;
  const atLimit = request({ text, diagnostics: { note: "x".repeat(remaining) } });

  const accepted = await post(atLimit);
  assert.equal(accepted.response.status, 200);
  assert.equal([...accepted.calls[0].body.body].length, 65_536);

  const rejected = await post({ ...atLimit, image: png().toString("base64") });
  assert.deepEqual(rejected.response, { status: 413, body: { error: "too_large" } });
  assert.equal(rejected.calls.length, 0);
});

for (const character of ["😀", "𠀀", "e\u0301", "👨‍👩‍👧‍👦"]) {
  test(`text limit counts grapheme clusters for ${character}`, async () => {
    for (const text of ["x".repeat(4999) + character, character.repeat(5000)]) {
      const { response } = await post(request({ text }));
      assert.equal(response.status, 200);
    }
    const { response, calls } = await post(request({ text: character.repeat(5001) }));
    assert.equal(response.status, 400);
    assert.equal(calls.length, 0);
  });
}

const rejections = [
  ["malformed JSON", "{", 400],
  ["a JSON array", "[]", 400],
  ["an unknown kind", request({ kind: "rant" }), 400],
  ["an inherited property as kind", request({ kind: "toString" }), 400],
  ["a missing kind", request({ kind: undefined }), 400],
  ["empty text", request({ text: "" }), 400],
  ["whitespace text", request({ text: " \n\t " }), 400],
  ["text over 5000 characters", request({ text: "x".repeat(5001) }), 400],
  ["non-string text", request({ text: 7 }), 400],
  ["a missing app", request({ app: undefined }), 400],
  ["a missing app field", request({ app: { version: "1", build: "1" } }), 400],
  ["an app field over 32 characters", request({ app: { version: "1".repeat(33), build: "1", platform: "macOS" } }), 400],
  ["array diagnostics", request({ diagnostics: [] }), 400],
  ["diagnostics over 16 KB", request({ diagnostics: { log: "x".repeat(16 * 1024) } }), 413],
  ["a non-string image", request({ image: 5 }), 400],
  ["an image that is not base64", request({ image: "not base64!" }), 400],
  ["an image that is not a PNG", request({ image: Buffer.from("GIF89a-not-png").toString("base64") }), 400],
  ["an image over 3 MB", request({ image: png(3 * 1024 * 1024 + 1).toString("base64") }), 413],
  ["a body over the size cap", request({ text: "x", padding: "x".repeat(5 * 1024 * 1024) }), 413],
];

for (const [name, body, status] of rejections) {
  test(`rejects ${name} with ${status} and no upstream call`, async () => {
    const { response, calls } = await post(body);

    assert.equal(response.status, status);
    assert.deepEqual(response.body, { error: status === 413 ? "too_large" : "invalid_request" });
    assert.equal(calls.length, 0);
  });
}

test("non-POST methods get 405 and no upstream call", async () => {
  for (const method of ["GET", "PUT", "OPTIONS"]) {
    const { response, calls } = await post("", { method });

    assert.deepEqual(response, { status: 405, body: { error: "method_not_allowed" } });
    assert.equal(calls.length, 0);
  }
});

test("FEEDBACK_DISABLED turns every kind away with 503", async () => {
  for (const kind of ["bug", "praise"]) {
    const { response, calls } = await post(request({ kind }), {
      env: { ...env, FEEDBACK_DISABLED: "1" },
    });

    assert.deepEqual(response, { status: 503, body: { error: "unavailable" } });
    assert.equal(calls.length, 0);
  }
});

test("relay stays disabled unless explicitly enabled after firewall verification", async () => {
  for (const value of [undefined, "", "1", "false"]) {
    for (const kind of ["bug", "feature", "needsWork", "praise"]) {
      const { response, calls } = await post(request({ kind }), {
        env: { ...env, FEEDBACK_DISABLED: value },
      });
      assert.deepEqual(response, { status: 503, body: { error: "unavailable" } });
      assert.equal(calls.length, 0);
    }
  }
});

const requiredEnv = [
  ["bug", "FEEDBACK_GITHUB_ISSUES_TOKEN"],
  ["bug", "FEEDBACK_GITHUB_MEDIA_TOKEN"],
  ["bug", "FEEDBACK_MEDIA_REPO"],
  ["praise", "FEEDBACK_RESEND_API_KEY"],
  ["praise", "FEEDBACK_EMAIL_TO"],
];

for (const [kind, name] of requiredEnv) {
  test(`${kind} returns 503 without ${name}`, async () => {
    const { response, calls } = await post(request({ kind }), { env: { ...env, [name]: "" } });

    assert.deepEqual(response, { status: 503, body: { error: "unavailable" } });
    assert.equal(calls.length, 0);
  });
}

const upstreamFailures = [
  ["issue creation fails", request(), { issue: 500 }, "500"],
  ["issue creation is unreachable", request(), { issue: "reject" }, null],
  ["email delivery fails", request({ kind: "praise" }), { email: 422 }, "422"],
  [
    "screenshot upload fails",
    request({ image: png().toString("base64") }),
    { media: 409 },
    "409",
  ],
];

for (const [name, body, failures, status] of upstreamFailures) {
  test(`returns 503 without leaking details when ${name}`, async (t) => {
    const log = t.mock.method(console, "error", () => {});
    const { response, calls } = await post(body, { failures });

    assert.deepEqual(response, { status: 503, body: { error: "unavailable" } });
    const logged = log.mock.calls.map((call) => call.arguments.join(" ")).join("\n");
    assert.match(logged, new RegExp(body.kind));
    if (status) assert.match(logged, new RegExp(`HTTP ${status}`));
    const privateSettings = Object.entries(env)
      .filter(([name]) => name !== "FEEDBACK_DISABLED")
      .map(([, value]) => value);
    for (const secret of [upstreamSecret, body.text, ...privateSettings]) {
      assert.ok(!logged.includes(secret), "log line holds no upstream body, user text, or env");
      assert.ok(!JSON.stringify(response).includes(secret));
    }
    if (failures.media) {
      assert.equal(calls.length, 1, "no issue is filed after a failed upload");
    }
  });
}
