# Inbox+ logo

Both original imagegen outputs are preserved without alteration:

- `inboxplus-logo-stacked.png`: the original x above the +.
- `inboxplus-logo.png`: the final unified eight-spoke asterisk.

The originals also ship as `InboxPlusLogoStacked.png` and `InboxPlusLogo.png` in the UI resources.
The identical artwork ships in `Sources/InboxPlusUI/Resources/InboxPlusLogo.png`.
The icon generator keeps the complete mark at every size on a black macOS icon plate.

## Final prompt

Edit this Inbox+ app logo. Replace the vertically separated x and + with ONE unified eight-spoke asterisk mark: superimpose the x directly over the +, with exactly the SAME center, so the four diagonal arms and four cardinal arms all radiate from one shared center at 45-degree intervals. Eight arms of equal radial length and uniform bold stroke width with subtly rounded ends. Center the single compact symbol in the square, occupying about 55 percent of the canvas width. Preserve the minimalist flat white-on-pure-black monochrome style. Crisp geometric vector-like edges, solid fills. No separate symbols, no vertical stacking, no gaps at the shared center, no text, no gradients, no texture, no shadows, no mockup. Single production-ready square logo.


## Click animation

Click the navigation-rail logo to open a small black animation panel. The original stacked artwork
transitions into native vector crosses, which pull together, twist, pulse and settle into the exact
final generated mark. Replay starts from the beginning; clicking outside dismisses the panel.
Reduce Motion replaces the movement with a short crossfade. The animation has no sound.

`inboxplus-logo-merge.gif` is a standalone preview rendered from the same SwiftUI artwork.
Regenerate it with:

```bash
swiftc -parse-as-library Sources/InboxPlusUI/LogoMergeArtwork.swift \
  Scripts/render-logo-animation.swift -o /tmp/render-inboxplus-logo
/tmp/render-inboxplus-logo /tmp/inboxplus-logo-preview
cp /tmp/inboxplus-logo-preview/inboxplus-logo-merge.gif docs/assets/inboxplus-logo-merge.gif
```
