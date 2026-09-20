# Conversation workspace (map / Ask Solo / discover)

Status: implemented in the iOS app (SwiftUI). Approved 2026-09-20; supersedes
the older map-first / no-tabs guidance in `docs/PRODUCT_BRIEF.md` where they
disagree. Native validation and remaining limits are recorded below.

## What changed

The chat was a modal `.sheet` that was created on open and discarded on close.
The map, the chat and discovery could not share state, and closing the chat
threw the agent away. The app now has **one continuous map/chat scene**:

- `ConversationWorkspaceState` owns the surface (map / Ask Solo / discover),
  the panel detent, the draft + staged attachments, the explicit-ask channel and
  scroll intent.
- `ConversationPanel` renders the panel and owns the grabber drag.
- `WorkspaceDock` renders the three-item dock and reuses `PlusActionButton` +
  `SoloMascotView` for the centre 问问 item.
- `DiscoverWorkspaceView` is a real discovery surface over `RoutesSection`,
  `CreateRouteEntryCard` and `NearbySection` — the same data and actions the map
  sheet used.
- `ChatSheet` became embeddable (`workspace:` + `embedded:`) and keeps its
  existing look, copy, voice flow, cards, history and orchestrator pipeline.
- `VoiceAgentOrchestrator` retains the existing Agent pipeline. It now protects
  scope changes, stops hidden audio, preserves conversations through errors,
  and exposes a recoverable timeout instead of silently stopping.
- `VoiceAgentSession.transcript` retains the full conversation for presentation
  and persistence; `messages` remains the bounded model context. Model-context
  compaction no longer removes the message a traveler is reading.

The old `BottomInfoSheet` and the duplicate amber "+" FAB are no longer
rendered; their code is kept behind `CompassMapContentView.showsLegacyBottomSheet`
for a clean rollback. Settings / explore stay reachable on the map surface and
via the avatar.

## States

| State         | Surface     | Detent          | Panel height            |
| ------------- | ----------- | --------------- | ----------------------- |
| Default       | `.ask`      | `.conversation` | 78% of the container    |
| Expanded chat | `.ask`      | `.expanded`     | 95%                     |
| Map           | `.map`      | `.collapsed`    | 136pt handle + dock bar |
| Discovery     | `.discover` | `.expanded`     | 95%                     |

Tab selection and detent are one state machine (`selectSurface` /
`selectDetent`), so a drag that settles onto the collapsed detent also selects
the map tab, and expanding from the map returns to the chat tab.

## Gesture ownership

- **Panel drag lives on the grabber only.** The message `ScrollView` keeps its
  own vertical scroll; MapKit keeps its pan/zoom. No gesture is attached to the
  whole message list.
- The live translation is a `@GestureState` with an animated reset transaction,
  disabled for Reduce Motion. SwiftUI resets it whenever the
  gesture becomes inactive — so a cancelled gesture (rotation, backgrounding, a
  system takeover) can never leave the panel stuck at a stale height.
- Drag is 1:1 inside the bounds and rubber-banded past them. On release the
  snap uses `predictedEndTranslation` as a **displacement** (not a velocity) to
  project where the gesture was heading, picks the detent nearest that
  projection, then clamps the move to one step from the current detent — one
  flick cannot skip the detent the user was aiming at.
- The grabber is a 44pt control with a tap toggle, an accessibility value for
  the current detent and a VoiceOver adjustable action; the drag uses a
  movement threshold so a tap is never swallowed.
- The panel changes only its own height; the MapKit tree is never re-laid out on
  a drag frame. The container height is measured once per layout via a
  background `GeometryReader` + preference, not per frame.

## State preservation

Draft, staged attachments, conversation, scoped experience and reading anchor
live in `ConversationWorkspaceState` / `VoiceAgentOrchestrator`, not in the
chat's transient view state. The workspace mounts only the active surface, so a
hidden chat is **unmounted** rather than kept at zero opacity: native R0 showed
that its intrinsic layout pushed the dock off-screen and that its controls were
still exposed to VoiceOver. Because all durable state lives outside the view,
unmounting loses neither draft nor conversation nor scope. The **reading anchor**
(the message at the top of the viewport, tracked via iOS 17
`scrollPosition(id:)` + `scrollTargetLayout()`) is stored per conversation and
restored on remount; it is cleared only by an explicit send / return-to-latest or
a genuine conversation change (new chat, restored history). Disappearing also
stops the mic, the pending permission request, speech and the scroll jobs, and
clears the software-keyboard signal. The orchestrator is retained for the root's
lifetime and is **never** discarded merely because the user is looking at the
map.

Expanded inline-card state is not persisted across an unmount (only the anchor
and the text/conversation are); this is called out rather than claimed as full
continuity.

Explicit asks raised while the chat was already mounted (diagnostics seed,
FilterBar "Ask Solo" pill, place-scoped ask) are delivered through a
`promptToken` the chat observes, so they are neither missed nor submitted twice.
Voice via the dock long-press uses a separate `voiceStartToken`, since
`startInVoiceMode` is only read on first appear.

## Voice / speech lifecycle

Collapsing the panel, switching away from the chat surface, backgrounding, or
presenting any modal (history, settings, detail, routes, profile via the city
OS base sheet) raises a hibernation signal: the mic stream is torn down and
`stopSpeaking()` halts speech. The conversation and draft are retained. Audio is
never collected behind a hidden panel.

- A pending `requestPermission()` is tracked and invalidated by a generation
  token; if it resolves after a collapse/background it does not start the mic.
- The composer mic uses one gesture: a quick tap toggles voice, a genuine hold
  starts push-to-talk. The old simultaneous tap + zero-duration long-press that
  could start/stop/restart on a single tap is gone.
- `VoiceAgentOrchestrator.isSpeechSuppressed` blocks a late turn completion
  from speaking while the chat is hidden; it is cleared when the chat is visible
  and the app is active again.
- Scope and history transitions (`rebindContext` / `restoreConversation`) flip
  `isSeeded` false **synchronously**, so an immediate send is rejected as
  `.notReady` instead of racing the async reseed. `stop()` advances the context
  generation so a pending seed can never resurrect the old session.
- A canceled/superseded turn bails at every suspension point (after the planner,
  after streaming/fallback, after each tool) and cannot commit, speak or persist
  into the new context. Background map navigation keeps its explicit AI request
  running — only audio is suppressed.

## Send acceptance

The composer clears the draft and staged attachments only when `onSend` returns
`true`; a rejected send keeps the user's input. The agent pipeline accepts text
only, so a staged attachment is never silently dropped — it is retained with an
explicit localized "attachments aren't supported here yet" hint.

## Scope safety (global vs place)

- A global ask (diagnostics seed, FilterBar pill, explore handoff, base
  follow-up) clears a stale place scope first.
- A place-scoped ask rebinds to that place and persists the previous
  conversation under a new record id, so scopes can't overwrite each other.
- The dock's normal return to 问问 retains the current scope.
- History restore reopens under the saved record's own `scopedExperienceId`.
- `VoiceAgentOrchestrator` guards `start` / `rebindContext` / `restore` with a
  context generation so a slow prompt build cannot overwrite a newer scope.

## Scroll follow

- A user send or an explicit "return to latest" always follows. Scrolling away
  clears that follow intent, so a long token stream cannot keep yanking the
  reader down after they leave the bottom.
- On iOS 18+, [system scroll geometry](<https://developer.apple.com/documentation/swiftui/view/onscrollgeometrychange(for:of:action:)>)
  compares the content height with the visible rect. iOS 17 retains a bottom
  marker outside the lazy stack and a separately measured viewport. A reader
  drag immediately releases follow and cancels pending scroll work.
- Streaming scroll requests go through `ScrollFollowThrottle`: at most one
  scheduled trailing action per ~120ms window, with the follow intent
  re-evaluated at execution time. This is a bounded throttle, not a debounce, so
  a fast token stream cannot starve the follow until generation ends.
- Pending follow work is cancelled when the panel hides or the app backgrounds.
- A localized, accessible "Latest" pill appears when a reply arrived while the
  reader was scrolled up.
- Auto-expansion while the agent works happens only for the chat surface; a
  user-chosen map or discovery view is never overridden.
- Keyboard focus captures a restore snapshot (detent + manual revision); on blur
  the detent is restored only if the user made no manual choice since. Hiding
  the chat resigns the text-field focus while keeping the draft.

## Discovery

`DiscoverWorkspaceView` shows the city, a sort menu, offline/retry, loading
skeletons, an empty state, the routes section (Now context), the create-route
entry and the nearby list. Every action routes back through the map's real
flows (open detail, preview card, adopt route, place-scoped Ask Solo, web
search, switch city, zoom out, refresh).

## Content honesty

Recommendation cards render only real Experience fields: title, category,
`oneLiner`, `whyItMatters`, Solo score, confidence health, `sources.count` and
the first unrestricted best-time window. Place results are deliberately **not**
numbered; only a real route proposal uses an ordered stop strip. No travel
times, source counts, photos, best times or justifications are fabricated.

The model's internal reference markers (`[exp:<id>]` / `[exp_<id>]`, and the
`→` chains that join them) are stripped in the display layer **together with
their separators**, so a live reply reads `**route title**.` rather than the raw
ids or a dangling `→ → .`. Persisted/raw provider output is never modified and
ordinary user bracketed text / prose arrows are preserved.

## Accessibility

Stable identifiers (see `WorkspaceAccessibility`): `workspace.panel`,
`workspace.handle`, `workspace.dock`, `workspace.dock.map|ask|discover`,
`workspace.chat`, `workspace.chat.collapse`, `workspace.composer`,
`workspace.returnToLatest`, `workspace.discover`, `workspace.overlay`.

The panel handle and dock keep ≥44pt targets. English and Simplified Chinese
strings are checked statically; runtime Dynamic Type and dark mode are listed
separately in the acceptance evidence.

## Haptics

Dock taps and committed detent changes each fire one `Haptics.selection()`.
The centre 问问 press uses `PlusActionButton`'s single soft impact — there is no
second haptic on the same tap. Haptics honor the existing user preference and
are never fired per drag frame.

## Honest distance + permission entry

- `ExperienceDetailView` only offers an "≈ walk N min" estimate at walking
  scale (≤2.5 km) and labels it as an estimate; farther experiences show the
  straight-line distance only (with no walk minutes and no bearing), so a remote
  city never reads "walk 154983 min".
- Chat-first entry never escalates the location prompt: it requests location
  only when undecided, and otherwise just starts updates with the already-granted
  "While Using" access, so no "Change to Always Allow" alert interrupts entry.

## Validation and remaining limits

- The parent built the native app with XcodeGen and ran 132 focused XCTest
  cases (0 failures, 0 skipped).
  Primary iPhone replay found and fixed dock/composer overlap, software-keyboard
  occlusion, hidden city controls, raw history titles and scroll-follow defects.
- Native evidence uses the shared iPhone 17 Pro and, for keyboard / small-screen
  regression checks, the shared iPhone SE. The final acceptance ledger records
  exact checks, revisions and screenshots; no simulator matrix is implied.
- Local Xcode's compiler capability probe stalled on verbose diagnostic output.
  A task-local compiler wrapper removed `-v` only for the `/dev/null` macro probe;
  compilation and linking still used Xcode's compiler. Explicit C modules fell
  back to disabled. Ordinary CI remains the independent toolchain check.
- Physical haptic feel, frame-rate profiling, iOS 17 runtime, Reduce Transparency
  and complete VoiceOver traversal are not certified by this simulator pass.
  Native Liquid Glass, material fallbacks and Reduce Motion paths are retained.
  Dark dock/discovery text uses the warm accessible palette. Composer glyphs
  stay within 44pt controls even at the largest accessibility text size; message
  and input text continue to follow Dynamic Type.
- The message anchor is retained across map/discovery; sub-message pixel offset
  and expanded inline-card state are not persisted. Restored history keeps text
  and tool messages; rebuilding prior inline cards is outside this change.
- No full Agent/database redesign or social-source ingestion is included.
  A target of 95 is a product quality goal, not a score inferred from test count.

## Recovery and presentation details

- Text input and controls respect the keyboard and home-indicator safe areas;
  only the panel background extends to the physical bottom. The dock disappears
  while composing. City/avatar stay at the top and are excluded from accessibility
  when the expanded panel covers them.
- The timeout between tool rounds now exposes a localized retryable error and
  saves the partial conversation. Retrying an error/timeout resumes the seeded
  context synchronously; quota termination cannot be bypassed by network retry.
  Individual provider request timeouts are unchanged.
- New history titles exclude internal context envelopes. Existing affected
  titles are recovered for display from their full first user message, without
  rewriting stored content. Nearby rows never expose provider/grid city IDs.

## Reported Agent limitations (out of UI scope)

- A live request for a 1-hour walk returned a route card of ~1h45m. The route
  duration constraint lives in the agent/tool layer, not the UI; the panel
  reports this to the parent rather than presenting the unmet request as
  fulfilled.
