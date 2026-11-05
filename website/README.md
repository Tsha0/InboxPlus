# Inbox+ website

A self-contained, static product site for [inboxplus.chat](https://inboxplus.chat).
No dependencies, build step, analytics, or external font requests.

## Preview

From the repository root:

```bash
python3 -m http.server 4173 --bind 127.0.0.1 --directory website
```

Open <http://127.0.0.1:4173>. Stop the server with Ctrl-C.

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

Demo replies live only in memory in the current tab. Nothing is sent or persisted.
The preview is an illustration of the native app, not a running messaging client.
Keep supported networks, requirements, and early-release notes aligned with the main
repository README. Download links point to GitHub’s latest release page, so they
do not need updating for each version.

The first screen starts in Classic monochrome. Scrolling blends through Grape Soda,
Bubblegum, Mint Chip, and Sunset on one continuous background. The preview follows
that palette until a visitor chooses a swatch. The theme values match
`Sources/InboxPlusFeatures/AppTheme.swift`; update them together if the app changes.
Surprise me cycles through all ten app presets, including Classic.

The opening animation assembles four strokes into the Inbox+ asterisk, then docks
the mark in the header as the homepage appears. Skip intro, Escape, or scrolling
skips it. Replay hello in the header and One more hello in the footer replay it.
The logo cursor is enabled only for a mouse;
inputs keep their text cursor. Reduced Motion skips the entrance and disables
particles, parallax, tilt, and animated reveals while retaining the scroll colors.

Easter eggs: click the header logo or large +, say hello to the illustrated device,
or type `hello` while focus is outside a text field. All effects stay in the tab.

## Assets

The asterisk follows Inbox+’s existing eight-spoke identity. Platform SVGs are
unchanged copies from `Scripts/brand-icons` (Simple Icons 13.20.0, CC0-1.0).
Their trademarks belong to their owners; no affiliation or endorsement is implied.

Bricolage Grotesque and DM Sans are self-hosted Latin variable fonts from Google
Fonts, distributed under the SIL Open Font License. Their license files are in
`assets/fonts/`. No third-party scripts or runtime packages are used.
