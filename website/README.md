# Inbox+ website

The static product site for [inboxplus.chat](https://inboxplus.chat). It has no dependencies, build
step, analytics or external font requests.

## Preview

From the repository root:

```bash
python3 -m http.server 4173 --bind 127.0.0.1 --directory website
```

Open <http://127.0.0.1:4173>. Stop the server with Ctrl-C.

## Deploy

The site is live in the Vercel project `inboxplus` under `tsha0s-projects`. To deploy the saved
files again, sign in to that Vercel account and run from the repository root:

```bash
cd website
npm exec --yes --package=vercel@65.11.0 -- vercel link --yes --project inboxplus --scope tsha0s-projects
npm exec --yes --package=vercel@65.11.0 -- vercel deploy --prod --scope tsha0s-projects
```

- Git ignores the local project link and environment files. `.vercelignore` keeps `README.md` out
  of the deployment.
- For a Git-based deployment, set **Root Directory** to `website` and the framework preset to
  **Other**. Leave the build command empty. The output directory is `.`, as `vercel.json` states.

## Edit

| File | Contents |
| --- | --- |
| `index.html` | Product copy, sections and download destinations |
| `styles.css` | Responsive layout, shared gradient canvas, entrance, cursor and motion |
| `app.js` | Fictional demo conversations, scroll colors, theme switching and Easter eggs |
| `assets/social.svg` | Source for the 1200 × 630 social sharing image, rendered to `assets/social.png` |

Keep these in sync with the app:

- Supported networks, requirements and early-release notes match the main repository README.
- Theme values match `apps/inboxplus/lib/ui/inbox_ui_controller.dart`. **Surprise me** cycles
  through all ten app presets, including Classic.
- The **Download the app** menu's Mac option asks the GitHub API for the latest release and links
  to its `InboxPlus-*.zip` asset. It falls back to the latest release page. Windows and Linux stay
  marked as coming soon until those releases exist.

Keep these behaviors when you change the page:

- The demo is an illustration, not a messaging client. Replies live in memory in the current tab,
  and nothing is sent or saved.
- The first screen starts in Classic monochrome. Scrolling blends through Grape Soda, Bubblegum,
  Mint Chip and Sunset, and the preview follows that palette until a visitor picks a swatch.
- **Skip intro**, Escape or scrolling skips the opening animation. **Replay hello** in the header
  and **One more hello** in the footer replay it.
- Reduced Motion skips the entrance and turns off particles, parallax, tilt and animated reveals.
  The scroll colors stay.
- The logo cursor appears only for a mouse. Inputs keep their text cursor.
- Easter eggs: click the header logo or the large +, say hello to the illustrated device, or type
  `hello` while focus is outside a text field.

## Assets

- The asterisk follows the Inbox+ eight-spoke identity.
- Platform SVGs are unchanged copies from `Scripts/brand-icons` (Simple Icons 13.20.0, CC0-1.0).
  Their trademarks belong to their owners. No affiliation or endorsement is implied.
- Bricolage Grotesque and DM Sans are self-hosted Latin variable fonts from Google Fonts under the
  SIL Open Font License. Their license files are in `assets/fonts/`.
