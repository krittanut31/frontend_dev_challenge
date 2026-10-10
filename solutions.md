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
2. Keystrokes are debounced by 300 ms with a GetX `debounce` worker, so fast
   typing sends one request instead of one per letter. This is load
   reduction, not the fix: a user who pauses longer than 300 ms between
   letters still produces overlapping requests, which (1) handles.

The worker is registered in `onInit`, so it is disposed with the controller.

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
controls. All four tests failed on the original code and pass after the fix.
Manually, on the Android emulator, typing "sushi" letter by letter now logs a
single `GET /deals/search?q=sushi` and shows only sushi deals.

---

## AI usage log

_To fill in as I go._

## Design questions

_Q1–Q3 to be answered._

## Time spent

_To fill in._
