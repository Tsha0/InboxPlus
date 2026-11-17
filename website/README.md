# Inbox+ website

The static product site for [inboxplus.chat](https://inboxplus.chat). It has no build step.

## Preview

From the repository root:

```bash
python3 -m http.server 4173 --bind 127.0.0.1 --directory website
```

Open <http://127.0.0.1:4173>. Stop the server with Ctrl-C.

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

## Assets

- Platform SVGs come from [Simple Icons](https://simpleicons.org) 13.20.0, under CC0-1.0. Their
  trademarks belong to their owners. No affiliation or endorsement is implied.
- Bricolage Grotesque and DM Sans are self-hosted fonts from Google Fonts under the SIL Open Font
  License. Their license files are in `assets/fonts/`.
