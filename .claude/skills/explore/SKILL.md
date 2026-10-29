---
name: explore
description: Use the Inbox+ macOS app like a person — click through the running demo inbox, look at every screen, and report confirmed bugs and concrete improvement ideas as findings. Run by the Explore workflow on a GitHub macOS runner, or locally on a Mac with the demo inbox.
---

# Explore

You are testing Inbox+ by using it. The app is running on the **demo inbox**: made-up
conversations held in memory, no accounts, no network. Look at it, click through it, try what
a real person would try, and report what is broken or could clearly be better.

Your output is `build/explore/findings.jsonl` (one finding per line, written as you go) and
`build/explore/summary.md` at the end. The workflow turns findings into GitHub issues.

## Your tools

Everything goes through `ui` (on your PATH). One action per call; check the result before the
next one.

| Command | What it does |
| --- | --- |
| `ui tree` | Lists windows, sheets, menus and their elements as `[ref] role "title" id=… value=… (x,y w×h)`. |
| `ui press <ref or text>` | Presses an element by its `[ref]` from the latest `tree`, or by label or identifier (`ui press rail-settings`, `ui press "Send message"`). Refs change when the screen changes: run `tree` again after anything that changes the screen. Some identifiers are shared by every control in a view, so prefer refs or labels. |
| `ui click <x> <y>` · `doubleclick` · `rightclick` | Mouse at screen points, the same coordinates `tree` prints. |
| `ui type "text"` | Types into the focused field, as a keyboard would. Opening a conversation focuses its message field; otherwise press or click the field first. |
| `ui key <combo>` | `return`, `escape`, `tab`, `down`, `cmd+f`, `cmd+w`, `cmd+shift+…` |
| `ui scroll <x> <y> <lines>` | Positive scrolls up, negative scrolls down. |
| `ui resize <w> <h>` | Resizes the window, to check small and large layouts. |
| `ui shot build/explore/shots/<name>.png [window]` | Screenshot of the screen, or only the main window; then `Read` it to look. |
| `ui pause <seconds>` | Waits for an animation. |
| `ui relaunch` | Restarts the app, which resets the demo inbox. |
| `ui crashlog` | Shows why the app died. |

Look before and after each meaningful action: take a screenshot and **read the image**. The
accessibility tree says what exists; only the screenshot shows what a person sees: clipping,
overlap, wrong colours, empty space, and text that does not fit.

Name screenshots in order, such as `07-retry-failed-message.png`, and keep the ones a finding
cites.

## What is in the demo

- **Maya Chen**: a person linked across WhatsApp and Instagram (2 unread on WhatsApp).
- **Family** (Telegram): a 40-message thread to scroll.
- **Design crit** (Telegram): a title far too long to fit, with 12 unread.
- **Sam** (iMessage): the last outgoing message **failed**, so it can be retried.
- **Leo Martín** (Messenger): text only, with no attachments allowed.
- **Priya** (WhatsApp): cannot send at all.
- **@noah** (Instagram): a long multi-paragraph message with a link.

Sending text works and is acknowledged at once. Restart with `ui relaunch` to get the original
state back.

## Expected in the demo, not bugs

- Adding a network or signing in offers no login: the demo has no runtime.
- Images and files from others never download: the demo has no media server.
- No system notifications or update checks: the app runs as a bare executable.
- An empty file picker, or a picker you cannot complete. Do not spend time on system dialogs.

## How to explore

Spend about two thirds of your time on a broad tour, and the rest digging into whatever looked
wrong. If the workflow gave you a focus area, start there.

1. **Tour.** Visit every section in the navigation rail, the inbox, a conversation, contacts,
   settings and accounts, the menu bar panel, and the app menus (`ui tree` lists them at the
   end). Screenshot each one.
2. **Inbox.** Search: matching, no match, clearing it. The All/Unread filters. Unread counts
   before and after opening a conversation. Favourites. Selection, and the arrow keys. Ordering.
3. **Conversation.** Scroll the long thread to the top and back. Send a message: normal,
   empty, only spaces, very long, emoji, several lines. Retry Sam's failed message. Check the
   composer in Leo's and Priya's conversations. Switch conversations with a draft typed, then
   come back. Select and copy text. Check that the link looks like a link, but do not open it:
   that would leave the app for a browser.
4. **Contacts.** Maya's linked identities; link and unlink a person; empty and invalid names.
5. **Settings and accounts.** Every control does something, or clearly says why it cannot.
6. **Layout.** The runner's screen is 1024×768. Try `ui resize 1000 690`, `ui resize 700 500`
   and the smallest size the app allows (`ui resize 300 200`; it stops at its minimum). Look for
   clipping, overlap and controls that disappear.
7. **Keyboard.** Tab through a screen, Escape out of sheets, ⌘W, ⌘F.
8. **Accessibility.** In `tree`, a button marked `NO-LABEL` has nothing for VoiceOver to read.

## What counts

**A bug** is behaviour you **reproduced twice** that is wrong. For example: a crash or hang; an
action that does nothing or does the wrong thing; state that does not update (unread counts,
previews, ordering); text cut off with no way to read it; overlapping or vanishing controls; a
control with no label; keyboard focus that gets stuck; an error with no message. Severity:

- **P1**: crash, hang, lost data, or a main flow (reading, sending) blocked.
- **P2**: wrong behaviour with a workaround.
- **P3**: cosmetic.

**An improvement** is a specific change that would make a real task easier, grounded in
something you saw. "Show the network next to each search result, because Maya appears twice
with no way to tell which is which" is useful. "Improve the design" is not. File at most 3 per
run, and only the strongest.

Before reporting, read `build/explore/existing-issues.md`. If a finding is already there, reuse
its fingerprint, so it becomes a "seen again" comment, not a duplicate.

## Writing a finding

Append one line of JSON to `build/explore/findings.jsonl` as soon as a finding is confirmed;
do not wait for the end. The run can be cut off.

```json
{"kind": "bug", "fingerprint": "retry-leaves-message-failed", "title": "Retrying Sam's failed message leaves it marked failed", "area": "Conversation", "severity": "P2", "steps": ["ui press inbox-item-…", "ui press Retry"], "observed": "…", "expected": "…", "why": "…", "screenshots": ["07-retry-before.png", "08-retry-after.png"]}
```

- `kind`: `bug` or `improvement`. Improvements use `"suggestion"` instead of `"expected"`.
- `fingerprint`: a short, stable, lowercase-dashed name for the problem itself, not for this
  run. The same problem must get the same fingerprint every time.
- `title`: what a person sees, in plain words, under 100 characters.
- `steps`: the exact `ui` commands, or plain steps, that reproduce it from a fresh launch.
- `observed` and `expected` (or `suggestion`): concrete and short.
- `screenshots`: up to 2 file names from `build/explore/shots/` that show it.

Never put anything in a finding that did not come from this app.

## Finish

Stop when you have covered the tour and dug into what you found, or when you are told time is
nearly up. Write `build/explore/summary.md`: the screens you visited, what you tried in each, the
findings (titles only), and anything you could not check and why. Keep it under 40 lines.
