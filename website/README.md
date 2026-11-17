# Inbox+ website

A self-contained product site for [inboxplus.chat](https://inboxplus.chat). The site is static
except for one Vercel function, the [feedback relay](#feedback-relay). No dependencies, build
step, analytics, or external font requests.

## Preview

From the repository root:

```bash
python3 -m http.server 4173 --bind 127.0.0.1 --directory website
```

Open <http://127.0.0.1:4173>. Stop the server with Ctrl-C. This server only serves files. It
does not run `api/feedback.mjs`.

## Vercel

Live at **[inboxplus.chat](https://inboxplus.chat)** in the existing `inboxplus`
project under `tsha0s-projects`. The domain is verified and serves the production
deployment over HTTPS.

To deploy the saved files again, run from the repository root while authenticated
to that Vercel account:

```bash
cd website
npm exec --yes --package=vercel@65.11.0 -- vercel link --yes --project inboxplus --scope tsha0s-projects
npm exec --yes --package=vercel@65.11.0 -- vercel deploy --prod --scope tsha0s-projects
```

The local project link and environment files are ignored by Git. `README.md` is
excluded from deployment by `.vercelignore`.

For future Git-based deployments, set **Root Directory** to `website` and use
**Other** as the framework preset. Leave the build command empty; the output
directory is `.` (also specified in `vercel.json`).

## Editing

- `index.html`: product copy, sections, and download destinations.
- `styles.css`: responsive layout, shared gradient canvas, entrance, cursor, and motion.
- `app.js`: fictional demo conversations, scroll colors, theme/appearance switching,
  and Easter eggs.
- `assets/social.svg`: editable source for the 1200 × 630 social sharing image,
  rendered to `assets/social.png`.
- `api/feedback.mjs`: the feedback relay function.

Demo replies live only in memory in the current tab. Nothing is sent or persisted.
The preview is an illustration of the native app, not a running messaging client.
Keep supported networks, requirements, and early-release notes aligned with the main
repository README. The **Download the app** menu's Mac option asks the GitHub API for the latest
release and links straight to its `InboxPlus-*.dmg` installer, falling back to the latest release page.
Windows and Linux stay marked as coming soon until those releases exist.

The first screen starts in Classic monochrome. Scrolling blends through Grape Soda,
Bubblegum, Mint Chip, and Sunset on one continuous background. The preview follows
that palette until a visitor chooses a swatch. The theme values match
`apps/inboxplus/lib/ui/inbox_ui_controller.dart`; update them together if the app changes.
Surprise me cycles through all ten app presets, including Classic.

The opening animation assembles four strokes into the Inbox+ asterisk, then docks
the mark in the header as the homepage appears. Skip intro, Escape, or scrolling
skips it. Replay hello in the header and One more hello in the footer replay it.
The logo cursor is enabled only for a mouse;
inputs keep their text cursor. Reduced Motion skips the entrance and disables
particles, parallax, tilt, and animated reveals while retaining the scroll colors.

Easter eggs: click the header logo or large +, say hello to the illustrated device,
or type `hello` while focus is outside a text field. All effects stay in the tab.

## Feedback relay

The macOS app sends in-app feedback to `POST https://inboxplus.chat/api/feedback`. The app
cannot hold a GitHub token, so `api/feedback.mjs` holds the secrets and forwards each report:

| `kind` | Destination | Labels |
| --- | --- | --- |
| `bug` | New issue in `Tsha0/InboxPlus` titled `[Bug] …` | `external`, `bug` |
| `feature` | New issue titled `[Feature request] …` | `external`, `enhancement` |
| `needsWork` | New issue titled `[Needs work] …` | `external` |
| `praise` | Email to `FEEDBACK_EMAIL_TO` through Resend | None |

The request body is JSON with `kind`, `text` (1 to 5,000 grapheme clusters after trimming, matching
the app), `app` (`version`, `build`, and `platform`, each up to 32 characters), an optional `diagnostics` object
of up to 16 KB, and an optional `image`. The image is a base64 PNG of up to 3 MB.

For an issue with a screenshot, the function first commits the PNG to a private media repository
at `YYYY/MM/<uuid>.png`. The issue then links to that file, so only people with access to the media
repository can open the screenshot. A praise email attaches the PNG instead. If the screenshot
upload fails, the function files no issue and returns 503, so the app can retry with the
screenshot still attached.

The issue body puts the user's text in a code block, then the app version, build, and platform,
then the screenshot link, then the diagnostics in a collapsed `<details>` section. The function
puts a zero-width space after every `@` in the title and body, so a report cannot notify GitHub
users or teams.

Every response is JSON:

| Status | Body | Cause |
| --- | --- | --- |
| 200 | `{"issueUrl": "https://github.com/Tsha0/InboxPlus/issues/N"}` | An issue was filed. |
| 200 | `{}` | The praise email was sent. |
| 400 | `{"error":"invalid_request"}` | The body failed validation. |
| 405 | `{"error":"method_not_allowed"}` | The method was not `POST`. |
| 413 | `{"error":"too_large"}` | The body, the diagnostics, or the image is over its limit. |
| 503 | `{"error":"unavailable"}` | The relay is disabled or missing a setting, or GitHub or Resend failed. |

Vercel rejects a request body over 4.5 MB with its own 413 response before the function runs.

Responses and logs never contain the user's text, a token, or an upstream error body. A log line
names only the feedback kind, the failed step, and the upstream HTTP status.

### Environment variables

| Name | Value |
| --- | --- |
| `FEEDBACK_GITHUB_ISSUES_TOKEN` | Fine-grained token that can create issues in `Tsha0/InboxPlus` |
| `FEEDBACK_GITHUB_MEDIA_TOKEN` | Fine-grained token that can write files in the media repository only |
| `FEEDBACK_MEDIA_REPO` | The media repository as `owner/name`, such as `Tsha0/InboxPlus-feedback-media` |
| `FEEDBACK_RESEND_API_KEY` | Resend API key |
| `FEEDBACK_EMAIL_TO` | Address that receives praise |
| `FEEDBACK_EMAIL_FROM` | Optional sender. The default is `Inbox+ Feedback <onboarding@resend.dev>`. |
| `FEEDBACK_DISABLED` | Disabled by default. Only `0` enables delivery; set it only after verifying the firewall rate limit. Missing, empty and all other values return 503. |

The issue kinds need the first three variables. Praise needs `FEEDBACK_RESEND_API_KEY` and
`FEEDBACK_EMAIL_TO`. If a kind's variables are missing, requests of that kind return 503.

### Set up the relay

The function has no secrets until the owner completes these steps once.

1. Set `FEEDBACK_DISABLED=1` in the Vercel project’s Production and Preview environments before
   adding credentials. The code also rejects delivery when this variable is missing.
2. Create a private repository for screenshots, such as `Tsha0/InboxPlus-feedback-media`.
   Initialize it with a README so that it has a default branch.
3. Create a fine-grained personal access token for issues. Limit its repository access to
   `Tsha0/InboxPlus` and grant **Issues: Read and write**. The token's owner needs push access to
   `Tsha0/InboxPlus`. Without push access, GitHub creates the issue but drops the labels.
4. Create a second fine-grained token for screenshots. Limit its repository access to the media
   repository and grant **Contents: Read and write**.
5. Create a Resend API key with sending access. With the default sender, `onboarding@resend.dev`,
   Resend delivers only to the email address of the Resend account. To send praise to another
   address, verify a domain in Resend and set `FEEDBACK_EMAIL_FROM` to an address on that domain.
6. Add each variable to the Vercel project's Production environment as a Secret, which is
   write-only after saving. Run this from `website` once per variable, and paste the value when
   prompted:

   ```bash
   npm exec --yes --package=vercel@65.11.0 -- vercel env add FEEDBACK_GITHUB_ISSUES_TOKEN production --sensitive --scope tsha0s-projects
   ```

7. Deploy with the commands in [Vercel](#vercel). Vercel applies changed environment variables
   only to new deployments.
8. Confirm the disabled function runs and that Vercel does not serve its source:

   ```bash
   curl -s -X POST https://inboxplus.chat/api/feedback -H 'Content-Type: application/json' -d '{}'
   curl -s -o /dev/null -w '%{http_code}\n' https://inboxplus.chat/api/feedback.mjs
   ```

   The first command prints `{"error":"unavailable"}` with status 503. The second prints `404`.
9. Configure and verify the [firewall rate limit](#limit-abuse). Keep `FEEDBACK_DISABLED=1` until
   this succeeds. Only then set `FEEDBACK_DISABLED=0` in the protected environment and redeploy.
   Repeating the first command should now return `{"error":"invalid_request"}` with status 400.

Fine-grained tokens expire. Replace each token before its expiry date. An expired issues token
makes bug, feature, and needs-work reports return 503.

### Turn the relay off

Set `FEEDBACK_DISABLED` to `1` in the Vercel project and redeploy. Every request then returns
503 and the function calls neither GitHub nor Resend. To turn the relay back on, verify the firewall
again, then set `FEEDBACK_DISABLED=0` and redeploy.

### Limit abuse

The function has no in-code rate limiting and stays disabled by default. Before enabling it:

1. Confirm the project's Vercel plan supports a Firewall rate-limit rule, then configure one for
   `/api/feedback` by client IP, covering POST requests and every deployment that will be enabled.
2. While `FEEDBACK_DISABLED=1`, send a bounded sequence of empty JSON requests to that path and
   verify requests over the configured threshold are blocked with 429 in both the response and
   Firewall events. These probes must not create issues, upload screenshots or send email.
3. Record the tested deployment, rule, threshold and result in the deployment change before setting
   `FEEDBACK_DISABLED=0`. Leave Preview disabled unless it has equivalent protection.

No plan support or live rule has been verified yet. If Firewall rate limits are unavailable, keep
`FEEDBACK_DISABLED=1` until a durable per-IP limiter is implemented and tested before delivery.
Deleting issues does not reclaim screenshot commits in the media repository.

### Run the tests

The tests call the function's core with fake GitHub and Resend endpoints. They make no network
requests. Run them from the repository root:

```bash
node --test 'Tests/Website/*.test.mjs'
```

CI does not run these tests. A passing run does not show that the live GitHub and Resend calls
work.

## Assets

The asterisk follows Inbox+’s existing eight-spoke identity. Platform SVGs are
unchanged copies from `Scripts/brand-icons` (Simple Icons 13.20.0, CC0-1.0).
Their trademarks belong to their owners; no affiliation or endorsement is implied.

Bricolage Grotesque and DM Sans are self-hosted Latin variable fonts from Google
Fonts, distributed under the SIL Open Font License. Their license files are in
`assets/fonts/`. No third-party scripts or runtime packages are used.
