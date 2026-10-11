# Solutions

## Environment notes

My machine runs Xcode 27 / macOS 27 with a Thai system locale, which is newer
than the pinned toolchain. None of the fixes below touch app behaviour:

- **iOS:** Xcode 27 only supports deployment targets 15.0+, so the target was
  raised from 12.0 to 15.0 (`[SETUP]` commit). The iOS 27 simulator kills
  Flutter 3.27 apps at launch (UIScene lifecycle is enforced), so I tested on
  an iOS 26.4 simulator.
- **Android:** run with `--no-enable-impeller` on the emulator (Impeller
  rendered a black screen). Gradle's jar writer failed under the `th-TH`
  locale (Buddhist-era years); fixed in my user-level
  `~/.gradle/gradle.properties`, not in this repo.

---

## RES-101 · Search shows results for the wrong query

**Root cause.** `SearchDealsController` started a request on every keystroke
and wrote whichever response arrived into `results`, with no check that it
belonged to the latest query. The backend is slower for shorter queries
(`searchDeals` adds `1200 - length * 280` ms), so typing "sushi" sends "s"
(~1.1–1.6 s) before "sushi" (~0.2–0.5 s): the "sushi" results show first,
then the late "s" response overwrites them. The same race also turned off
`isLoading` as soon as *any* request finished, and a search still in flight
when the box was cleared would repopulate the empty screen.

**Fix.**
1. Each search gets an increasing id; a response (or error) is applied only if
   no newer search has started since. This is what fixes the bug: the result
   always matches the latest query, regardless of response order.
2. Keystrokes are debounced by 300 ms with a `Timer` owned by the
   controller, so fast typing sends one request instead of one per letter.
   This is load reduction, not the fix: a user who pauses longer than 300 ms
   between letters still produces overlapping requests, which (1) handles.
   The timer is cancelled in `onClose`.

The first version used GetX's `debounce` worker and assumed it was disposed
with the controller. Reading `get` 4.7.3 showed that is wrong twice over:
workers are never disposed automatically, and even `Worker.dispose()` only
cancels the stream subscription, not the debouncer's pending timer. A
keystroke right before leaving the screen still fired a search on the closed
controller. A plain `Timer` can be cancelled, so I switched to it (follow-up
`[RES-101]` commit, with a test).

**Alternatives considered.**
- *Debounce only.* Rejected: it narrows the window but does not close it,
  since a slow earlier request can still land after a later one.
- *Cancelling the previous request.* The fake API returns a plain `Future`
  with no cancellation, and a real HTTP cancel would still need a guard
  against a response already being processed. Ignoring stale responses is
  simpler and complete.
- *Comparing the response's query to the current text.* Works for this case
  but breaks if the user types "sushi", deletes, then retypes "sushi" while
  the first request is in flight; an id is unambiguous.

**Edge cases.**
- Clearing the box discards in-flight results and resets the empty state
  (covered by a test).
- An error for a stale query is ignored rather than logged against the
  current one.
- Not handled: when the *latest* search fails, the previous results stay on
  screen with no error message. The screen has no error state today; adding
  one is a UI decision outside this ticket.

**Verification.** `test/search_deals_controller_test.dart` drives the
controller with a fake repo whose responses resolve in an order the test
controls. The four race tests failed on the original code and pass after the
fix; a fifth checks that closing the screen cancels a pending search.
Manually, on the Android emulator, typing "sushi" letter by letter now logs a
single `GET /deals/search?q=sushi` and shows only sushi deals.

---

## RES-102 · Crash after leaving My orders

**Root cause.** `PickupCountdown` starts a `Timer.periodic` in `initState`
that calls `setState` every second, but never keeps a reference to it and
never cancels it. Navigating back disposes the `State`, yet the timer keeps
firing, so the next tick calls `setState` on a defunct `State` and Flutter
throws `setState() called after dispose()`. Only active orders show a
countdown, which is why the ticket needs an order with an upcoming pickup.
Each visit also leaked one timer per countdown for the rest of the session.

**Fix.** Keep the timer in a field and cancel it in `dispose()`. The timer's
lifetime now matches the widget that owns it.

**Alternatives considered.**
- *`if (mounted) setState(...)`.* Rejected: it hides the crash but the timers
  keep running forever, one more set per visit. That is exactly the
  symptom-hiding fix the brief warns against.
- *Moving the tick into `OrdersController`.* A shared one-second ticker in the
  controller would also work, and GetX would close it in `onClose`, but the
  countdown is purely presentational and local to this widget, so the widget
  is the right owner. Worth revisiting if F-1 introduces a shared clock.

**Edge cases.**
- The timer keeps ticking after the pickup window opens, although the text no
  longer changes. Harmless and cheap; left as is to keep the fix minimal.
- Each card rebuilds only its own `PickupCountdown`, not the list, so the
  per-second rebuild is already scoped to the changing text.

**Verification.** `test/pickup_countdown_test.dart` pumps the widget, removes
it from the tree and advances the clock 3 s. It failed with the exact error
from the ticket before the fix and passes after. Manually, on the Android
emulator, opening My orders (three countdowns) and going back produces no
error in the console.

---

## RES-104 · Duplicate deals in the home feed

**Root cause.** `HomeController` mutated its paging state *before* a request
finished, and never told an in-flight page request that the list it was meant
for had been replaced:

1. With 2 pages loaded, `loadMore` sets `_page = 3` and awaits page 3.
2. Pull to refresh: `refreshDeals` sets `_page = 1` and awaits page 1.
3. The refresh lands: the list is page 1 (20 items).
4. Page 3 lands and is appended: the list is pages 1 + 3, `_page` is 1.
5. Scrolling on loads page 2 and then page 3 *again*: duplicates, and more
   items than the catalog once it reaches the end.

A failed refresh caused the same thing on its own: `_page` was reset to 1
before the request, so after a failure (the fake API fails intermittently)
the old 60-item list stayed while the next scroll fetched page 2 again. The
`_page--` rollback in `loadMore` could also undo a reset made by a refresh in
between.

**Fix.**
- Paging state (`_page`, `_totalPages`) changes only when a response is
  applied, never before the request.
- `_listVersion` increases whenever a refresh replaces the list. `loadMore`
  remembers the version it started with and drops its page if the list has
  been replaced since. This also covers a load-more started *while* a
  refresh was in flight.
- `_latestRefreshId` makes only the most recent refresh replace the list.
- A failed refresh keeps the current list and paging, and calls
  `refreshFailed()` so the pull-to-refresh spinner stops (before, the
  exception escaped and `refreshCompleted()` was never called).

**Alternatives considered.**
- *De-duplicating by `id` before appending.* Rejected: it hides the symptom.
  The feed would still skip page 2 (pages 1 + 3 shown as if complete) and
  paging would still be out of sync with the list.
- *Blocking pull-to-refresh while a page is loading.* Users expect refresh to
  work at any time, and it would not cover a failed refresh.
- *Cancelling the in-flight request.* The fake API has no cancellation, and a
  real one would still need the version check for a response already in
  progress.

**Edge cases.**
- A load-more that lands *before* the refresh is harmless: the refresh
  replaces the list afterwards (kept as a regression test).
- A stale load-more still calls `loadComplete()` so the footer resets.
- Not changed: after reaching the end (`loadNoData`), refreshing does not
  reset the footer's "no more data" state. Out of scope for this ticket.

**Verification.** `test/home_controller_test.dart` drives the controller with
a fake repo whose pages resolve in a chosen order: page 3 after a refresh, a
load-more started during a refresh, a failed refresh, and repeated
refresh/load-more races until the end of the catalog. Three of these failed
on the original code (with duplicates or more items than the catalog); the
"page 3 lands first" case passed before and is kept as a guard. All pass
after the fix. On the Android emulator, paging and pull-to-refresh still
work; I could not hit the race timing reliably by hand, so the race itself
is covered by the tests only.

---

## RES-107 · Deep link opens to a crash

**Root cause.** `DealDetailsController.onInit` took the deal only from
`Get.arguments as DealModel`. In-app taps (`DealCard`, the flash rail) pass
the model as `arguments`, but a deep link is just a URL:
`rescu://open/deal?id=42&source=push` becomes the route
`/deal?id=42&source=push` with no arguments, so `null as DealModel` threw.
The id the page needs was already in the route; nothing read it.

**Fix.**
1. The route id is the source of truth. If a `DealModel` was passed *and* its
   id matches the route, it is shown immediately (no extra request, same as
   before for in-app taps). Otherwise the page fetches `GET /deals/:id`,
   shows a spinner, and on failure shows "Couldn't load this deal" with a
   *Try again* button. That is a transient-failure state, not the fallback
   screen the ticket rules out: the fake API fails intermittently, and a
   retry lands on the working deal page.
2. Cold start. When the link opens the app from scratch, GetX builds the
   navigation stack from the deep-link route alone
   (`GetMaterialApp.initialRoutesGenerate`), so the deal page had no back
   button and system back did not lead into the app. When the page is the
   root route it now shows a back button, and system back goes to Home
   (`PopScope` + `Get.offAllNamed(Routes.home)`). A user arriving from a
   push notification can buy the deal and then continue browsing.

`deal_details_view` analytics now use the id from the route, so deep-link
views are logged with `source: push`.

**Alternatives considered.**
- *Passing the model from the deep-link handler.* There is no handler to
  change for real links: Flutter's built-in deep linking pushes the route
  name itself. The page has to work from the URL alone.
- *Redirect middleware that fetches the deal before the page opens.*
  Navigation would block on a network call with nothing on screen, and the
  failure case would still need a home.
- *A `/` route redirecting to Home, so Flutter builds `/` + `/deal`.* GetX
  replaces the initial-route generator when `getPages` is set and only builds
  the deep-link route, so this has no effect.

**Edge cases.**
- An argument whose id does not match the route is ignored in favour of the
  route.
- A route with a missing or non-numeric id shows the retry state (logged),
  rather than crashing.
- Not handled: an id that does not exist (404) shows the same retry state.
  Deal 42 exists, and a dedicated "deal no longer available" screen is a
  product decision.

**Verification.** `test/deal_details_deep_link_test.dart`:
- navigating to `/deal?id=42&source=push` with no arguments failed with the
  ticket's exact error (`type 'Null' is not a subtype of type 'DealModel'`)
  before the fix; it now shows a spinner, then the deal and *Add to bag*,
  and logs `{deal_id: 42, source: push}`;
- a failed load shows *Try again*, which recovers;
- an in-app tap with the model renders at once with no request;
- starting the app at the deal route, both the app-bar back button and system
  back lead to Home (both failed before the second commit).

On the Android emulator: `adb shell am start ... "rescu://open/deal?id=42&source=push"`
with the app running opens deal 42 and *Add to bag* works; with the app
stopped, the deal page opens, and both back paths reach Home. (Launching the
debug APK outside `flutter run` uses Impeller, which hangs on this emulator;
the cold-start checks were done with `--no-enable-impeller --route`.)

---

## RES-103 · Requests pile up the longer you browse

**Root cause.** `DealDetailsController.onInit` registers
`ever(cartService.itemCount, ...)` to re-check stock when the cart changes,
and drops the returned `Worker`. `CartService` is a permanent service, so its
`itemCount` stream lives for the whole session. When a deal page is closed,
GetX deletes the controller (`onClose`), but GetX does **not** dispose
workers created by a controller (`ever` just calls `listen` on the Rx and
returns the subscription's `cancel` as a `Worker`). The subscription, and
the closure holding the closed controller, stays on the service's stream.
Every cart change then runs `_recheckAvailability` for every deal page
opened earlier in the session: one `GET /deals/:id` each, growing with
browsing. It also leaks each closed controller.

**Fix.** Keep the `Worker` and dispose it in `onClose`. The open page still
re-checks its own stock; closed pages stop.

**Alternatives considered.**
- *Guarding the callback with `isClosed`.* Stops the requests but keeps every
  subscription and controller alive: still a leak, only quieter.
- *Moving the re-check into the screen with an `Obx`/`StatefulWidget`.* Would
  tie it to widget lifecycle, but the controller is the right owner of "keep
  this deal's stock fresh"; it just has to clean up after itself.

**Edge cases.**
- A re-check already in flight when the page closes still completes and
  updates the closed controller's `_quantityLeft`. Harmless (nothing listens)
  and it does not repeat.
- Not changed: `_recheckAvailability` has no error handling, so an
  intermittent API failure surfaces as an uncaught error in the console.
  Separate from this ticket.

**Verification.** `test/deal_details_lifecycle_test.dart` opens and closes
deals 1, 2 and 3, then changes the cart. Before the fix it re-fetched
`[1, 2, 3]`; now nothing. A second test checks the open page still re-checks
its own deal. On the Android emulator, after opening and closing two deals
and adding a third to the bag, the log shows a single `GET /deals/:id` for
the open deal.

This is also my answer to Q1's "name a bug": RES-103 (and RES-102) exist
because a subscription or timer was treated as if it shared the owner's
lifecycle.

---

## RES-106 · Wrong pickup times; "Pickup today" filter misses deals

**Root cause.** The backend is right: it sends UTC instants
(`2026-01-01T23:00:00.000Z`). `DateTime.parse` keeps those as **UTC**
`DateTime`s, and `PickupWindowModel` then read them as if they were local
wall-clock times:

- `label` formatted `start`/`end` with `DateFormat('HH:mm')`, which prints the
  UTC hour. A bakery open 06:00–09:30 in Bangkok (UTC+7) is 23:00–02:30 UTC,
  exactly the label in the ticket. People read the wrong hours and went to
  closed stores; `isOpenNow` itself compares instants and was correct.
- `isToday` compared `start.day` (the UTC day of month) with
  `DateTime.now().day` (the local one). Every window starting before 07:00
  Bangkok time falls on the previous UTC day, so early stores disappeared
  from "Pickup today", while tomorrow's early windows (still "today" in UTC)
  showed up. It also compared only the day of the month, so 2 January and
  2 February matched.

**Fix.** Keep `start`/`end` as UTC instants (the existing `model_test.dart`
asserts `isUtc`, and instants are the right storage) and convert to local
time exactly where a wall clock is read:
- `label` formats `start.toLocal()` / `end.toLocal()`;
- "today" means the window **overlaps the local calendar day** of `now`. That
  also counts an overnight window that started yesterday at 22:00 and is
  still open at 00:30, which "starts today" would miss.

**Alternatives considered.**
- *`.toLocal()` in `fromJson`.* Fixes the symptoms too, but breaks the
  model's existing contract (and test) that it holds UTC instants, and hides
  the conversion from readers of the model.
- *Formatting in the store's time zone instead of the device's.* More correct
  for a user looking at Bangkok stores from abroad, but the API sends no time
  zone, and hard-coding UTC+7 in the app would duplicate a backend detail. For
  users in the market the two are the same.
- *Comparing `start.toLocal().day == now.day`.* Fixes the time-zone part but
  keeps the month bug and misses overnight windows.

**Edge cases.** Overnight windows (22:00–01:00) format and filter correctly
(tests). Windows the backend has rolled to tomorrow are excluded. Not
handled: time-zone changes while the app is open re-evaluate on the next
build, which is fine for a label.

**Making it testable (Q3).** `isToday` read `DateTime.now()` directly, so a
test could only run "now". A first, behaviour-preserving commit added
`isTodayAt(DateTime now)` with `isToday` delegating to it. The tests in
`test/pickup_window_model_test.dart` build the API payload from a *local*
wall-clock time converted to UTC, as the backend does, so they hold in any
zone except UTC, where this bug cannot appear. Run under several zones:

```
TZ=Asia/Bangkok flutter test     # before the fix: label '23:00 – 02:30'
TZ=America/New_York flutter test
TZ=Pacific/Kiritimati flutter test
```

Before the fix, Bangkok failed 5 of 7 (including the exact ticket label) and
even UTC failed the month and overnight cases. After the fix, all tests pass
in all four zones. On the Android emulator (Asia/Bangkok), Baan Somtam
Kitchen now shows "05:30 – 08:00" instead of "22:30 – 01:00", and at 11:05
"Pickup today" lists tonight's 22:00–01:00 windows and no longer lists
tomorrow's 05:30 window.

---

## RES-105 · Home feed is janky and memory keeps climbing

**Root causes.**
1. **The whole screen rebuilt on every scroll pixel.** `HomeScreen` wrapped
   the entire `Scaffold` in one `Obx` that read `scrollOffset`, and
   `HomeController._onScroll` wrote the offset on every scroll event. The
   value was only used for two thresholds (app-bar shadow at > 4 px, the
   scroll-to-top button at > 800 px), but each pixel rebuilt the app bar,
   the `SmartRefresher`, the list and every card.
2. **Every rebuild created every card.** The feed was
   `ListView(children: [...visibleDeals.map(DealCard)])`. Elements are
   still mounted lazily by the sliver, but the list of `DealCard` widgets
   for *all* loaded deals (up to 122) was allocated on every build, so the
   cost of (1) grew with each page loaded.
3. **Images were decoded at source size.** The API serves 1600×1200 photos;
   `CachedNetworkImage` decoded them at full size (~7.7 MB of pixels each)
   to fill 160 dp-tall cards. The 100 MB image cache was full after 13
   images, so scrolling churned through decode/evict of very large bitmaps.

**Fixes.**
1. `scrollOffset` replaced by `isScrolled` / `showScrollToTop` `RxBool`s.
   Rx only notifies when the value changes, so these fire once when a
   threshold is crossed, not per pixel. `Obx` is scoped to what each part
   shows: the app bar (shadow), the body (loading, deals, filter), the
   filter chip, and the FAB.
2. `ListView.builder`, so only cards near the viewport are created.
3. `TheNetworkImage` passes `memCacheWidth` (or `memCacheHeight` for boxes
   taller than wide) = laid-out size × device pixel ratio. Only one side is
   set so the aspect ratio is kept. `width: double.infinity` falls back to
   the layout width (a bug in my first version, caught by reviewing the
   call sites and now covered by `test/the_network_image_test.dart`).

**Measurements.** Temporary instrumentation (not committed) counted rebuilds
with `debugOnRebuildDirtyWidget`, frame timings with
`addTimingsCallback`, and read `imageCache` and `ProcessInfo.currentRss`
every second, while an adb script made the same 60 flings through all 7
pages. Android emulator (API 37, Skia), debug build:

| | before | after |
|---|---|---|
| `DealCard` rebuilds during the scroll | 716 | 154 |
| all widget rebuilds during the scroll | 55,188 | 9,183 |
| decoded size per card image | ~7.7 MB | ~3.0 MB |
| images held by the full 100 MB cache | 13 | 35 |
| peak RSS (debug / profile) | 484 / 317 MB | 471 / 301 MB |

**What these numbers do not show.** Frame times on this emulator are not
usable: it renders on the CPU (no GPU, the same reason Impeller fails), so
raster p90 is ~380–490 ms in both versions, even in profile mode, and the
frame rate is raster-bound before and after. Peak RSS barely moves because
the image cache was already capped at 100 MB; the fix makes each image
2.6× cheaper rather than lowering the cap. Frame-time and memory evidence
from DevTools should be captured on a physical mid-range device in profile
mode; I have not done that.

**Alternatives considered.**
- *Throttling the scroll listener.* Fewer updates, but still rebuilds the
  whole screen each time; the problem is the scope, not the rate.
- *`NotificationListener<ScrollNotification>` with a `StatefulWidget` for
  the shadow.* Also fine; the two `RxBool`s keep the controller pattern the
  codebase already uses.
- *Lowering `imageCache.maximumSizeBytes`.* A global policy change that
  trades memory for re-decoding; with right-sized decodes the default cap
  holds 35 card images, so I left it.

**Not changed.** Card images still show a shimmer while loading, which
animates every frame per loading card; that is intended UX.

---

## F-1 · Live flash-sale countdowns

**Design.**
- **One clock for the whole app.** `ClockService` owns a single
  `Timer.periodic(1s)` and publishes `now` as an `Rx<DateTime>`. With 100+
  countdowns there is still one timer, not one per card. The time source is
  injectable (`ClockService(clock: ...)`) so tests drive it.
- **Only the text rebuilds every second.** `FlashCountdownText` is an `Obx`
  around a single `Text` that formats `endsAt - clock.now`. Nothing above it
  reads the clock, so cards, the rail and the list are not rebuilt by ticks.
- **The card changes state once.** `FlashExpiryBuilder` gives its builder
  `isExpired` and arms a one-shot `Timer` for the moment the sale ends, so
  the card rebuilds exactly once, when it becomes "Expired". (Deriving the
  expired flag from `clock.now` inside an `Obx` would have rebuilt the whole
  card every second.)
- **Format.** `mm:ss`, `hh:mm:ss` from one hour, partial seconds rounded up
  so `00:00` appears when time is up, not a second early
  (`util/countdown_format.dart`, pure and unit-tested).
- **Where it shows.** Flash rail (replaces "Ends soon"), home-feed and search
  cards ("FLASH SALE · 12:34"), and the details page ("Flash sale ends in
  12:34"). Digits use tabular figures so the text does not jitter.

**At zero.**
- Cards switch to a dimmed "Expired" state and are **not tappable**: the deal
  can no longer be bought, so opening it would lead to a page with nothing
  to do. The details page, if already open, shows "Flash sale ended" and
  disables the button.
- **The rule lives in the cart, not just the UI.** `CartService.add` refuses
  an ended flash deal and now returns whether it added anything (the
  details page only shows "Added to bag" when it did). The button can be
  tapped in the same frame the sale ends; the cart is what guarantees it.
- **Removal from the bag.** `FlashSaleExpiryService` (app-wide) runs on each
  clock tick, asks the cart to remove ended flash lines
  (`removeExpiredFlashDeals`), and shows a snackbar naming them. It is a
  separate service so `CartService` stays free of UI calls and is testable
  on its own. Removal happens within one second of the end, on any screen.

**Performance evidence.** `test/flash_countdown_test.dart` builds a list of
120 flash `DealCard`s, records every widget rebuild with
`debugOnRebuildDirtyWidget`, and advances the clock 5 seconds: the only
rebuilds are one `Obx` + `Text` per visible countdown per second (plus the
image placeholder's shimmer, which animates regardless). `DealCard`,
`FlashExpiryBuilder`, `Card`, `InkWell`, `Column`, `Stack` and `ListView`
rebuild zero times. I have not profiled F-1 in DevTools on a real device
(same emulator limits as RES-105).

**Checked in the app** (Android emulator): countdowns run in the rail, the
feed badge and the details page, and the same deal shows the same time in
both places. I added *Last-call Bakery Box* (8-minute sale) to the bag and
waited: at zero its rail card dimmed to "Expired" and the snackbar "Removed
from your bag — The flash sale ended for Last-call Bakery Box." appeared on
the home screen.

**Alternatives considered.**
- *A `Timer` or `StreamBuilder` per countdown.* Works, but 100+ timers firing
  at slightly different phases means 100+ separate rebuild callbacks per
  second instead of one notification.
- *`AnimationController`/`Ticker` per countdown.* Ticks every frame (60/s)
  for a value that changes once a second.
- *Removing expired lines only when the bag is opened or at checkout.*
  Simpler, but the brief asks for a visible notice when it happens, and the
  bag badge would be wrong in the meantime.

**Edge cases.**
- A sale ending while the details page is open: banner and button switch at
  zero, and the cart rejects a tap that races the switch.
- The same deal in the rail and the feed counts down in sync (same clock).
- Behaviour change: `CartService.add` returning false also stops the
  "Added to bag" snackbar when the stock limit is reached, which previously
  showed even though nothing was added.
- Not handled: checkout in the sub-second window between a sale ending and
  the next tick sends that line to the backend. With reservations (F-3) the
  backend would reject it; without them I accepted the one-second window.
- Not handled: device clock changes. The countdown trusts the device clock
  against the server's `flashSaleEndsAt`; a skewed clock shows a skewed
  countdown. A server time offset would fix that and is out of scope.

---

## AI usage log

_To fill in as I go._

## Design questions

_Q1–Q3 to be answered._

## Time spent

_To fill in._
