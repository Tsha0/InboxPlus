# Inbox+ website

The product site for [inboxplus.chat](https://inboxplus.chat), with one Vercel feedback function.
It has no build step.

## Preview

From the repository root:

```bash
python3 -m http.server 4173 --bind 127.0.0.1 --directory website
```

Open <http://127.0.0.1:4173>. Stop the server with Ctrl-C. This server does not run the feedback relay.

## Deploy

Sign in to the `tsha0s-projects` Vercel account and run from the repository root:

```bash
cd website
npm exec --yes --package=vercel@65.11.0 -- vercel link --yes --project inboxplus --scope tsha0s-projects
npm exec --yes --package=vercel@65.11.0 -- vercel deploy --prod --scope tsha0s-projects
```

For a Git-based deployment, set **Root Directory** to `website` and the framework preset to
**Other**. Leave the build command empty.

## Edit

- Keep the supported networks, requirements and early-release notes in line with the main
  [README](../README.md).
- Keep the theme values in line with `apps/inboxplus/lib/ui/inbox_ui_controller.dart`.
- Keep the page working with Reduced Motion turned on.
- After you edit `assets/social.svg`, render it again to `assets/social.png` at 1200 × 630.
- Copy platform icons unchanged from `Scripts/brand-icons`.

## Feedback relay

The macOS app submits feedback to `POST https://inboxplus.chat/api/feedback`.
Keep the relay disabled until its credentials and firewall rate limit are configured.
The Mac download links to the latest release’s `InboxPlus-*.dmg` installer.

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

7. Deploy with the commands in [Deploy](#deploy). Vercel applies changed environment variables
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

- Platform SVGs come from [Simple Icons](https://simpleicons.org) 13.20.0, under CC0-1.0. Their
  trademarks belong to their owners. No affiliation or endorsement is implied.
- Bricolage Grotesque and DM Sans are self-hosted fonts from Google Fonts under the SIL Open Font
  License. Their license files are in `assets/fonts/`.
