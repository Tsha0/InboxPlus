# Phase 5 message and media — developer acceptance

Phase 5 turns the transcript from a list of sentences into rendered content: photos are drawn,
audio and video play inline, files open in Finder, app-only content offers a verified way out to
its own app, and anything Mimo cannot draw still says what the bridge reported.

## What Phase 5 changed

Phase 3 normalized every Matrix event into a `Message` and then threw away what it was — the
gateway called `normalize(...).message` and dropped the kind. An image arrived as the word
"Photo". Phase 5 carries the payload the whole way:

- `MessageKind` and `MessageAttachment` in `MimoCore`, so the renderer switches on content
  without importing an SDK.
- `MatrixEventNormalizer` populates attachments — source, thumbnail, mime type, size, dimensions,
  duration — from what the bridge actually reported.
- `MediaCache` and `MediaLoader` in `MimoGateway`: lazy, bounded, LRU, private on disk.
- `MediaController` in `MimoFeatures` makes loading observable per attachment.
- `AttachmentView` in `MimoUI` renders each kind, including the fallbacks.
- `DeepLinkVerifier` in `MimoCore` decides what may be handed to the system.
- `OutgoingAttachment` and `ConversationCapabilities` add the sending half, with the composer's
  attach control driven by what the conversation actually accepts.

## 1. Automated checks

```sh
swift test && swift build -c release && git diff --check
```

Expect 489 tests passing (419 before Phase 5). The live-runtime tests remain opt-in behind
`MIMO_RUNTIME_PYTHON`, unchanged.

## 2. See media arrive

With a profile running and an account connected (Phase 4), send yourself a photo, a voice message
and a video from the connected network. Each appears in the transcript as the thing itself.

An image event can also be injected directly, which is how the pipeline was exercised without
relying on a real network:

```sh
# as the bridge's own appservice, into an existing portal room
curl -X POST -H "Authorization: Bearer $AS_TOKEN" -H "Content-Type: image/png" \
  --data-binary @photo.png \
  "$HS/_matrix/media/v3/upload?filename=photo.png&user_id=$GHOST"
curl -X PUT -H "Authorization: Bearer $AS_TOKEN" -H "Content-Type: application/json" \
  "$HS/_matrix/client/v3/rooms/$ROOM/send/m.room.message/$TXN?user_id=$GHOST" \
  -d '{"msgtype":"m.image","body":"photo.png","url":"'"$MXC"'","info":{"mimetype":"image/png","w":240,"h":240,"size":1097}}'
```

Nothing is downloaded until the conversation is opened. `<profile>/media/` stays empty until then,
which is the cheapest possible way to observe that the cache is genuinely lazy.

## 3. Send an attachment

Open a conversation and click the paperclip. The system's own open panel appears, so Mimo reads
only the file actually chosen. The file is staged as a removable chip below the composer and is not
sent until Send is pressed — staging is not sending.

The paperclip is **absent**, not greyed out, in a conversation whose network takes no attachments.

## What Phase 5 guarantees

**Nothing is downloaded speculatively.** A download starts when an attachment view appears and not
before, so opening a conversation with a hundred photos costs nothing. Two views asking for the
same media share one download rather than racing two writers onto one path.

**A cached file can always be explained.** Every entry retains its source adapter, remote message
identifier, content type, size, and deep link, so an evicted file can be fetched again from where
it came from. The filename is a digest of the media's own identifier, so a remote-chosen name can
never steer a write.

**Cleanup never destroys anything irreplaceable.** Eviction is least-recently-used and touches only
reproducible files. A file that cannot be fetched again is kept even when that leaves the cache
over budget — being over budget is a smaller harm than losing something permanently. Under disk
pressure Mimo stops downloading and says so, in words that state nothing was deleted; a silent
stop reads as a broken app, and a user who fears their history was trimmed will not trust it again.

**Only a verified link leaves the app.** An **Open in app** action is built solely from an `https`
URL on a domain the named platform demonstrably owns, checked with a leading-dot suffix match so
`evil-instagram.com` cannot pass as Instagram. Custom schemes such as `instagram://` are rejected
on purpose: any installed application can claim a scheme, so following one hands a message's
contents to whatever registered it first, whereas macOS resolves an `https` link against the
domain's own app-site association. A stored link is re-verified when it is read back, so a link
that was trusted when written is not trusted merely because it was written.

**Nothing is ever silently dropped.** Every kind reaches a visible view. An unknown gallery item,
an undecryptable event, bytes that arrive but will not decode, a failed download, a paused
download — each produces a card naming what happened. A failure offers a retry, because a
transient network blip must not cost a photo permanently.

**Nothing is invented.** A duration, size or dimension the bridge did not report is left out rather
than shown as zero. A `0:00` under a voice message is a claim; absence is the truth.

**Mimo does not autoplay.** Audio and video present controls and wait.

**A file is refused when it is chosen, not when it is sent.** Kind and size are checked against the
conversation's declared capabilities at the moment of picking, and the refusal names both the file's
size and the limit so it is actionable. A kind the network will not take is refused rather than
silently downgraded to a plain file — quietly sending something other than what was picked is a
surprise, and the choice belongs to the user. A file that fails to send stays staged, because
dropping it would lose their choice with nothing to show for it.

## Known limitations entering Phase 6

- **Capabilities are declared, not discovered.** `ConversationCapabilities` gates the composer and
  defaults to Matrix's own abilities. Nothing yet reads a bridge's `bridgev2` capability report, so
  a network that refuses video will still be offered video until that is wired up.
- **Live media rendering is unverified on screen.** The pipeline is covered by unit tests end to
  end and an `m.image` event was delivered into a real portal room, but the rendered result was
  never observed: screen capture against the ad-hoc-signed development binary returns black, which
  is the same code-identity problem that causes the repeated permission prompts.
- **Galleries render as a stack, not a grid.** Every item is present and individually loadable;
  the layout is simply one per row.
- **Link previews are not generated.** The design lists them as a supported category. Mimo shows
  what a bridge supplies and does not fetch page metadata itself.
- **Thumbnails are parsed but not preferred.** `MessageAttachment.thumbnail` is populated from the
  event, but the full-size source is what gets downloaded; a slow connection therefore waits for
  the whole image.
- **Editing, reactions and replies are still flattened.** The design's message contract lists them;
  the normalizer records the events but the transcript does not yet group them.
- **The cache budget is fixed.** 2 GiB, with no setting and no visible indication of how much is
  in use.
- **Still SQLite.** Phase 2's verdict was `Require PostgreSQL`, and media metadata adds to it.
