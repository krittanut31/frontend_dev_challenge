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

## AI usage log

_To fill in as I go._

## Design questions

_Q1–Q3 to be answered._

## Time spent

_To fill in._
