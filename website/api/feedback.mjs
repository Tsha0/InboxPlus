import { randomUUID } from "node:crypto";

const issueRepo = "Tsha0/InboxPlus";
const maxBodyBytes = 4 * 1024 * 1024 + 64 * 1024;
const maxTextLength = 5000;
const maxAppFieldLength = 32;
const maxDiagnosticsBytes = 16 * 1024;
const maxImageBytes = 3 * 1024 * 1024;
const titleLength = 70;
const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const defaultEmailFrom = "Inbox+ Feedback <onboarding@resend.dev>";

const invalidRequest = { status: 400, body: { error: "invalid_request" } };
const methodNotAllowed = { status: 405, body: { error: "method_not_allowed" } };
const tooLarge = { status: 413, body: { error: "too_large" } };
const unavailable = { status: 503, body: { error: "unavailable" } };

const issueDestination = {
  requiredEnv: [
    "FEEDBACK_GITHUB_ISSUES_TOKEN",
    "FEEDBACK_GITHUB_MEDIA_TOKEN",
    "FEEDBACK_MEDIA_REPO",
  ],
  deliver: fileIssue,
};

const emailDestination = {
  requiredEnv: ["FEEDBACK_RESEND_API_KEY", "FEEDBACK_EMAIL_TO"],
  deliver: sendEmail,
};

const routes = {
  bug: { destination: issueDestination, labels: ["external", "bug"], prefix: "Bug" },
  feature: {
    destination: issueDestination,
    labels: ["external", "enhancement"],
    prefix: "Feature request",
  },
  needsWork: { destination: issueDestination, labels: ["external"], prefix: "Needs work" },
  praise: { destination: emailDestination, prefix: "Praise" },
};

export async function handleFeedback({ method, bodyText }, env, fetchImpl) {
  if (method !== "POST") return methodNotAllowed;
  if (env.FEEDBACK_DISABLED) return unavailable;
  if (Buffer.byteLength(bodyText) > maxBodyBytes) return tooLarge;

  const { feedback, rejection } = parseFeedback(bodyText);
  if (rejection) return rejection;

  const route = routes[feedback.kind];
  if (route.destination.requiredEnv.some((name) => !env[name])) return unavailable;

  const body = await route.destination.deliver(feedback, route, env, fetchImpl);
  return body ? { status: 200, body } : unavailable;
}

function parseFeedback(bodyText) {
  let request;
  try {
    request = JSON.parse(bodyText);
  } catch {
    return { rejection: invalidRequest };
  }
  if (!isPlainObject(request) || !Object.hasOwn(routes, request.kind)) {
    return { rejection: invalidRequest };
  }

  const text = typeof request.text === "string" ? request.text.trim() : "";
  if (text.length === 0 || text.length > maxTextLength) return { rejection: invalidRequest };

  const { app } = request;
  const appFields = ["version", "build", "platform"];
  if (
    !isPlainObject(app) ||
    !appFields.every(
      (field) => typeof app[field] === "string" && app[field].length <= maxAppFieldLength,
    )
  ) {
    return { rejection: invalidRequest };
  }

  const diagnostics = request.diagnostics ?? null;
  if (diagnostics !== null) {
    if (!isPlainObject(diagnostics)) return { rejection: invalidRequest };
    if (Buffer.byteLength(JSON.stringify(diagnostics)) > maxDiagnosticsBytes) {
      return { rejection: tooLarge };
    }
  }

  let image = null;
  if (request.image != null) {
    if (typeof request.image !== "string" || !/^[A-Za-z0-9+/]*={0,2}$/.test(request.image)) {
      return { rejection: invalidRequest };
    }
    image = Buffer.from(request.image, "base64");
    if (image.length > maxImageBytes) return { rejection: tooLarge };
    if (!image.subarray(0, pngSignature.length).equals(pngSignature)) {
      return { rejection: invalidRequest };
    }
  }

  return {
    feedback: {
      kind: request.kind,
      text,
      app: { version: app.version, build: app.build, platform: app.platform },
      diagnostics,
      image,
    },
  };
}

async function fileIssue(feedback, route, env, fetchImpl) {
  let screenshotUrl = null;
  if (feedback.image) {
    const now = new Date();
    const month = String(now.getUTCMonth() + 1).padStart(2, "0");
    const path = `${now.getUTCFullYear()}/${month}/${randomUUID()}.png`;
    const upload = await callUpstream(fetchImpl, feedback.kind, "screenshot upload", {
      url: `https://api.github.com/repos/${env.FEEDBACK_MEDIA_REPO}/contents/${path}`,
      method: "PUT",
      headers: githubHeaders(env.FEEDBACK_GITHUB_MEDIA_TOKEN),
      body: { message: "Add feedback screenshot", content: feedback.image.toString("base64") },
    });
    if (!upload) return null;
    screenshotUrl = upload.content.html_url;
  }

  const issue = await callUpstream(fetchImpl, feedback.kind, "issue", {
    url: `https://api.github.com/repos/${issueRepo}/issues`,
    method: "POST",
    headers: githubHeaders(env.FEEDBACK_GITHUB_ISSUES_TOKEN),
    body: {
      title: neutralizeMentions(title(route.prefix, feedback.text)),
      body: issueBody(feedback, screenshotUrl),
      labels: route.labels,
    },
  });
  return issue && { issueUrl: issue.html_url };
}

async function sendEmail(feedback, route, env, fetchImpl) {
  const sections = [feedback.text, appFooter(feedback.app)];
  if (feedback.diagnostics) {
    sections.push(`Diagnostics:\n${JSON.stringify(feedback.diagnostics, null, 2)}`);
  }
  const email = {
    from: env.FEEDBACK_EMAIL_FROM || defaultEmailFrom,
    to: env.FEEDBACK_EMAIL_TO,
    subject: title(route.prefix, feedback.text),
    text: sections.join("\n\n"),
  };
  if (feedback.image) {
    email.attachments = [{ filename: "screenshot.png", content: feedback.image.toString("base64") }];
  }

  const sent = await callUpstream(fetchImpl, feedback.kind, "email", {
    url: "https://api.resend.com/emails",
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.FEEDBACK_RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: email,
  });
  return sent && {};
}

async function callUpstream(fetchImpl, kind, step, { url, method, headers, body }) {
  let response;
  try {
    response = await fetchImpl(url, { method, headers, body: JSON.stringify(body) });
  } catch {
    console.error(`feedback ${kind}: ${step} request failed`);
    return null;
  }
  if (!response.ok) {
    console.error(`feedback ${kind}: ${step} returned HTTP ${response.status}`);
    return null;
  }
  return response.json();
}

function githubHeaders(token) {
  return {
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
    "User-Agent": "InboxPlus-feedback-relay",
    "X-GitHub-Api-Version": "2022-11-28",
  };
}

function issueBody(feedback, screenshotUrl) {
  const sections = [
    codeBlock("text", neutralizeMentions(feedback.text)),
    escapeMarkdown(appFooter(feedback.app)),
  ];
  if (screenshotUrl) {
    sections.push(`Screenshot (visible to maintainers only): ${screenshotUrl}`);
  }
  if (feedback.diagnostics) {
    const json = neutralizeMentions(JSON.stringify(feedback.diagnostics, null, 2));
    sections.push(
      `<details>\n<summary>Diagnostics</summary>\n\n${codeBlock("json", json)}\n\n</details>`,
    );
  }
  return sections.join("\n\n");
}

function title(prefix, text) {
  const firstLine = [...text.split(/[\r\n]/)[0].trim()];
  const summary =
    firstLine.length > titleLength
      ? `${firstLine.slice(0, titleLength - 1).join("").trimEnd()}…`
      : firstLine.join("");
  return `[${prefix}] ${summary}`;
}

function appFooter({ version, build, platform }) {
  return `Inbox+ ${version} (build ${build}) on ${platform}`.replace(/\s+/g, " ");
}

function codeBlock(language, content) {
  const longestRun = Math.max(0, ...(content.match(/`+/g) ?? []).map((run) => run.length));
  const fence = "`".repeat(Math.max(3, longestRun + 1));
  return `${fence}${language}\n${content}\n${fence}`;
}

// A zero-width space after "@" keeps the text readable while stopping GitHub from linking or
// notifying the named user or team.
function neutralizeMentions(text) {
  return text.replace(/@(?=[A-Za-z0-9])/g, "@\u200b");
}

function escapeMarkdown(text) {
  return neutralizeMentions(text).replace(/[\\`*_{}[\]()<>#+\-.!|~&]/g, "\\$&");
}

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export default {
  async fetch(request) {
    const { status, body } = await handleFeedback(
      { method: request.method, bodyText: await request.text() },
      process.env,
      fetch,
    );
    return Response.json(body, { status });
  },
};
