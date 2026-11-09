# Corva review: November 2026

Five reviewers went through the app in parallel:
- **Data and maths:** scoring, analytics, and pact rules on the phone and on the server.
- **Backend and security:** the Supabase database, access rules, the Google Health function and pact settlement.
- **App plumbing:** sign-in, sync, concurrency and caching.
- **Design and accessibility:** every screen with real data, VoiceOver, text sizes and contrast.
- **Product strategy:** competitors, launch requirements and what to build next.

I checked every claim marked ✓ against the code. Findings that more than one reviewer reported are merged. Paths are relative to the repository root.

**Status (10 Nov):**
- **Pacts are paused.** The tab shows a Coming soon screen, and the pact items below (#1-6) are deferred, untouched.
- **Fixed:**
  - #7 privacy copy;
  - #10 clean sign-out;
  - #12 failed pushes kept and retried, with pulls merging unsent edits (in memory: an app kill still loses them);
  - #13 single-flight token refresh, signing out only on a real rejection;
  - #14 screens reload in place instead of rebuilding;
  - #15 demo data after re-sign-in;
  - #16 cold-launch sync, per-operation busy state and no echoed profile pushes;
  - #18 Today falls back to the latest day, with retry on empty and error states (days without a night are still dropped);
  - #19 calendar windows and date-keyed pairing;
  - #20 a 7-reading baseline minimum, with a calibrating note;
  - #21 Google's sleep totals, classic sleep marked and handled;
  - #22 sleep debt counted once;
  - #23 no fake zeros, source workout names;
  - #26 statistics minimums;
  - #27 bio age needs your age and explains the missing VO2 max;
  - #33 the demo notice on Today, Trends and Lab.
- **Still open (non-pact):** #8, #9, #11, #17 (backend and privacy), #24 (today's partial strain), #25 (daylight saving), and P2 accessibility and design #28-31, #34-37.

**Priority:** P0 means fix before anyone else uses pacts or the app. P1 means fix soon (real-data correctness). P2 means quality, accessibility and polish.

---

## P0: money, trust, security and data loss

### Pacts: the server and the app disagree about who owes whom
1. **One bad pact stops all pact settlement, for everyone.** ✓
   - The database lets a solo pact be saved without a recipient name (`supabase/migrations/20261108190547_initial_schema.sql:150`), but a ledger row needs one (`:392`).
   - `settle_pacts()` runs as one transaction with no error handling (`…google_health_and_settlement.sql:195`). The first broken pact without a name rolls back the whole hourly run, every hour.
   - An absurd `start_date` does the same.
   - **Fix:** require a recipient name for solo pacts, sanity-check `target` and `start_date`, and wrap each pact in its own exception block.
2. **Pacts can be backdated.** ✓
   - `start_date` is never validated, and `accept_pact_invite` doesn't check whether the pact has already started.
   - A creator can backdate a pact to days they already know they hit. The friend is then scored on history, and `pact_progress` reveals the friend's data from before they joined.
   - **Fix:** validate start dates on create, and reject acceptance after the start.
3. **A broken sync turns into debts.** ✓
   - A day with no data settles as missed after 2 UTC days (`…settlement.sql:212-217`), even when the sync itself failed.
   - In Google's testing mode, refresh tokens expire every 7 days, so any pact longer than about 9 days is guaranteed to hit this.
   - **Fix:** settle no-data days only if the user's connection synced cleanly past that day. Otherwise hold the day, then mark it "no data" (not "missed") after a cutoff, and ask the user to reconnect.
4. **The app computes pact outcomes itself, by different rules from the server.** ✓
   - **Friend's sick days:** the app never excuses them (`Corva/Core/Analytics/PactEvaluation.swift:80` passes `isUnwell: false`).
   - **No grace period:** the app has none; the server waits 1-2 days. A morning before the overnight sync shows "Broken · you owe Priya £20".
   - **Strain rounding:** the app rounds strain (`Scoring.swift:72`) and the SQL doesn't, so 49.6 against a target of 50 is met on the phone and missed on the server.
   - **Unwell check:** the app's version has no minimum history (see P1 #13), while the SQL needs 7 readings.
   - **Server status ignored:** `PactProgressRow` doesn't even decode the server's settled `status` (`Corva/App/AccountService.swift:536`).
   - **Fix:** make the server the only referee. Use its settled status per day and compute only unsettled days locally, with the same grace rules. Add a shared test that runs the same rows through both and checks they agree.
5. **Bedtime "met" settles too early, and the main sleep choice depends on order.**
   - A doze before the real sleep can lock in a met bedtime.
   - In `supabase/functions/google-health/index.ts`, `|| asleep > currentAsleep` lets a longer nap replace the main sleep, depending on the order Google returns them.
6. **Finishing a pact isn't idempotent.** Overlapping runs could write two ledger rows. **Fix:** add a status guard and a unique index on `(pact_id, from_user)`.

### Security and privacy
7. **The privacy copy is false.** ✓ `Corva/Features/Settings/AccountSection.swift:60` says "Health data stays on this phone", but `daily_records` live on the server. All three reviewers flagged this; fix it before any privacy policy.
8. **Consent phishing.**
   - The OAuth `state` is tied to whoever started the connection, not to the device that finishes consent.
   - An attacker can send their connect link to a friend, and the friend's Google Health data then syncs into the attacker's account.
   - It's blocked today because the Google project is in testing mode with test users only, but it must be fixed before publishing.
   - **Fix:** bind state to a verifier held by the app, and complete the link through an authenticated `finish` call.
9. **Deleting data:**
   - A sync already running when you disconnect can re-insert data after the delete.
   - Account deletion fails for anyone owed money (the ledger check), and deleting a pact creator cascades away the opponent's pact and debts.
   - There's no in-app account deletion, which App Store guideline 5.1.1(v) requires.
   - Google tokens are stored in plaintext.
10. **Signing out leaks into the next account.** ✓
    - `queue?.cancel()` (`Corva/App/AccountService.swift:132`) only cancels the last pending push. Earlier ones keep running and can land in a newly signed-in account.
    - Settings aren't reset on sign-out.
    - Logout uses Supabase's default "global" scope, so it signs out every device.
11. **Defence in depth:**
    - `anon` has write grants on public tables, so RLS is the only barrier.
    - Clients can set invite `code` and `expires_at`.
    - The cron secret is compared with a non-constant-time `!==`.
    - Raw database and Google errors reach the app.

### Sync reliability
12. **Offline edits are lost.** ✓
    - A failed push is only logged (`enqueue`), and the next refresh replaces the list with the server's, so the experiment, tag or pact disappears.
    - Edits made during a refresh are also wiped, because refresh only waits for pushes queued before it started.
    - Creating a pact takes two requests and isn't atomic.
    - **Fix:** persist an outbox keyed by the client's UUIDs, retry with backoff, and merge on pull rather than replacing.
13. **Avoidable sign-outs.** ✓ Token refresh isn't single-flight, and any 4xx (including 429) wipes the session (`SupabaseClient.swift:139`). Two screens refreshing at once can sign you out.
14. **Every sync throws away what you're doing.** ✓ `.id(account.dataVersion)` rebuilds the data tabs, which closes an open New Experiment or New Pact sheet (losing its form), pops detail screens and resets Today's date. **Fix:** reload with `.task(id:)` instead.
15. **Demo data reappears unlabelled.** After a forced sign-out and signing back in, the screens keep demo data without the demo banner.
16. **Smaller sync issues:**
    - The sync on opening the app never runs on a cold launch.
    - One `isWorking` flag is shared by six operations.
    - A profile push can revert a just-made settings change.
    - The record cache refetches once per screen.
17. **Server sync won't scale.**
    - `sync-all` runs users one after another (about 15 calls each) inside one function call. Hit a timeout, and the same users at the end of the list are never synced.
    - `/sync` has no rate limit.

---

## P1: real data still breaks assumptions made for the demo

18. **Today goes blank whenever last night hasn't synced.** ✓
    - Any day without sleep, HRV and resting HR is dropped entirely (`Corva/Core/Backend/DailyRecords.swift:63-67`), steps and workouts included.
    - The empty state can't be pulled to refresh.
    - **Fix:** fall back to the latest day with a "Last night hasn't synced yet" note, keep daytime-only days, and add a retry.
19. **Days are paired by position, not by date.** ✓
    - Previous day: `DayContrast.swift:193`. Lagged relationships: `Insights.swift:162`. Training-load windows, bio age windows, and "Last 7 days / 14 nights / 30 days" across screens all count entries, not calendar days.
    - With gaps, "strain the day before" can come from days earlier.
    - Charts draw smooth lines across missing nights.
20. **Baselines are trusted from 1-2 days.** ✓
    - `Baseline.Stat` has no count, so on day 2 the spread is 0 and every vital reads "outside range".
    - Recovery is scored against one night. Sick-day passes and experiment days are skewed.
    - **Fix:** store a count, require 7+ readings, and show "Calibrating (n/7)".
21. **Sleep without stages is shown as 100% light sleep**, with 0% deep and REM, 0 wake-ups and 100% efficiency.
    - The app ignores Google's `minutes_asleep` and takes bedtime and wake time from the stages, not the session.
    - So the Sleep screen and a sleep pact can disagree.
22. **Sleep debt is counted twice.** ✓ Need already includes debt repayment (`Scoring.swift:85`), and `Insights.sleepDebt` then adds up shortfalls against it, so 2 h of lost sleep shows as about 3 h 26 m.
23. **Missing values show as 0:**
    - Average and max HR show "0 bpm".
    - A "Zone 1 · 0m" row always appears (Google has no zone 1).
    - Activities show "0 kcal" and "0 strain".
    - Badminton and field hockey both show as "Workout".
    - A vital that's never recorded gets a Trends card full of zeros.
24. **Today's unfinished day is counted as complete.** At 8 AM today's strain is about 0, which drags down training load ("Below usual"), averages and experiments.
25. **Daylight saving and odd bedtimes:**
    - Wake times on clock-change mornings are off by an hour.
    - A bedtime before 6 PM is "met" on the phone and "missed" on the server.
26. **Statistics from too little data:**
    - A relationship from 3 days can read as "Strong".
    - With 7 days of data, the training-load ratio is 1.00 by construction.
    - **Fix:** require 14+ pairs for relationships and 28 days for training load.
27. **Bio age misleads:**
    - Age defaults to 32 but reads as "your age".
    - VO2 max, the biggest marker at ±4 years, is dropped silently.
    - Team sports never count as strength, so most users get +0.8 y by default.
    - **Fix:** require the user's real age, show the missing markers, and consider calling it "fitness age" or showing a range.

---

## P2: accessibility, design and polish

28. **Met and missed rely on colour alone.** Pact dots, the best/worst strip and pact bars use green against red only; for deuteranopes these are about 1.1-1.4:1 apart. **Fix:** add check and cross glyphs.
29. **Light-mode contrast fails WCAG.** `textTertiary` is 2.82:1, the "Moderate" label 2.64:1 and alert text 3.27:1. Increase Contrast isn't supported.
30. **VoiceOver:**
    - No chart has labels, so VoiceOver reads "Bar 63" or "Stage 1.12".
    - Card headers aren't headings.
    - Whole cards read as very long buttons.
31. **Dynamic Type:** rings have fixed sizes, numbers shrink instead of growing, and fixed widths truncate text. The experiment tag cells are only 40 pt tall.
32. **30-day pacts overflow.** ✓ 30 dots need about 360 pt, but the row is about 210 pt. **Fix:** use a 7-column calendar grid.
33. **Demo data is only labelled on Today.** Trends and Lab show demo numbers ("4.5 years younger than your age, 32") as if they were yours.
34. **Flow papercuts:**
    - The signed-out "Join with a code" alert is a dead end.
    - "End now" on an experiment has no confirmation.
    - In Join a pact, "Look up" turns into "Accept" in the same spot, so a double tap accepts.
    - Filled-in sheets can be swiped away without a warning.
    - Settings has two "Sync now" buttons that do different things.
    - There's no way to cancel a pending invite.
    - The ledger says "Won" and "Paid" although no money moves.
35. **Glass on every content card (52 of them)**, including glass chips inside glass cards. Apple's guidelines reserve glass for navigation. Consider opaque cards.
36. **Copy:**
    - "your vitals show you were unwell" reads like a diagnosis.
    - "recommended range" is coaching.
    - "0m short" appears even when sleep need is met.
    - "1 SD" is jargon.
37. **Performance:** bio age, best/worst days and every experiment analysis are recomputed in `body` on every render (the experiment detail runs its analysis twice). Compute them once per load.

---

## Launch blockers outside the code

- **Google:**
  - All Google Health scopes are *restricted*.
  - Going past 100 users needs OAuth verification plus the yearly CASA security assessment, with a verified domain, homepage, privacy policy and demo video. Start now: it takes weeks.
  - Until then, every user must reconnect every 7 days.
- **UK GDPR (health data is special category):**
  - a privacy policy;
  - explicit consent;
  - a data protection impact assessment;
  - the ICO data protection fee;
  - a data processing agreement with Supabase;
  - data export;
  - in-app account deletion.
- **Apple:**
  - The paid Developer Program (£79 a year) is needed for TestFlight, push and Sign in with Apple.
  - Guideline 4.8 likely requires Sign in with Apple alongside Google sign-in.
  - Guideline 1.4.1 means health claims need care ("not a medical device").
- **Money:**
  - Under the UK Gambling Act, head-to-head pacts where the loser pays are very likely betting, and "it's a game of skill" doesn't help. Apple's guideline 5.3.4 would then need licences.
  - Charity stakes must be collected outside the app unless you're an approved nonprofit (3.2.2).
  - **Recommendation:** v1 moves no money. Next, refundable charity stakes after legal advice. Head-to-head cash last, or never. Get a UK gambling solicitor's opinion.

---

## Brainstorm: making Corva better

**Positioning.** Bevel already reads Fitbit Air data through Google Health, free. "Whoop for Fitbit Air" isn't enough; Corva should be *the app that finds out what works for you, then holds you to it*. Where Corva already leads:
- open scoring that adds up exactly;
- real statistics on experiments;
- best vs worst days;
- pacts refereed by the wearable;
- no paywalled AI coach.

**Gaps that matter most:**
- Apple Health support. Google Health now writes into Apple Health, so this adds Apple Watch, Oura and Garmin users.
- Notifications, widgets and Live Activities.
- A general evening journal, beyond experiment tags.
- Showing the illness detection, which already runs, to the user.
- Cycle-aware baselines (the luteal phase can trip the "unwell" check).
- Onboarding with a calibration period.

**Ideas only Corva can do well:**
1. **Randomised experiments (M).** Corva picks ON and OFF nights, balanced by weekday, and a 6 PM notification says "Tonight is an OFF night". Before starting, it shows "21 nights to detect a 4 ms change". This removes the confounding that every competitor's "insights" suffer from.
2. **Protocol pacts (S-M).** Put a stake on an experiment, so the wearable checks you stuck to it and the experiment measures the effect.
3. **Pact goals only an analytics app can referee (S):**
   - "inside my strain target 5 of 7 days";
   - "sleep debt under 2 h";
   - "bedtime consistency ≥ 80";
   - "training load between 0.8 and 1.3 for 4 weeks", a pact that rewards rest.
4. **"Test this" (S).** A button on each best vs worst factor opens a pre-filled experiment.
5. **"Found in your data" (M).** Automatic comparisons on things the wearable already sees (late bedtimes, travel, late workouts), shown only if they survive a multiple-testing correction.
6. **An illness banner that pauses pacts (S).** "3 of 5 vitals moved the way illness moves them", and active pacts pause automatically. The partner only sees "paused".
7. **Pact day receipts (M):** value, source, sync time, wear time and a dispute window. When money is involved, this is what earns trust.
8. **Group pacts (M).** Everyone hits the goal, or the group's stakes go to a charity they chose together. Nobody wins money, which is probably the safest legal shape.

**Retention that fits a data-first brand:**
- A morning notification when last night's data lands ("Recovery 71 · HRV +8 ms").
- One-tap evening tagging (notification buttons, Shortcuts, a Control Center control).
- Widgets for the recovery dial, pact dots and "Tonight: ON night".
- A pact Live Activity in the final hours of a pact day.
- A Monday report: the week against baseline, experiment progress and the pact ledger. No streaks.

---

## Suggested order

1. **P0 pacts and money (#1-6):**
   - server-side validation and per-pact error handling;
   - "no data" ≠ "missed" when the sync broke;
   - the server is the only referee.
2. **P0 trust and data loss (#7, #10, #12-15):**
   - fix the privacy copy;
   - clean sign-out;
   - an offline outbox;
   - single-flight token refresh;
   - `.task(id:)` instead of `.id`.
3. **P1 real data (#18-27):**
   - Today never blank;
   - date-keyed windows;
   - calibrating baselines;
   - sleep from Google's totals;
   - optional values, no zeros.
4. **Launch track, alongside:** Google verification, the compliance pack, the paid Apple account with Sign in with Apple and TestFlight, and pacts without money.
5. **Accessibility pass (#28-31)** and the 30-day pact layout.
6. **Product:** randomised experiments and protocol pacts, notifications and widgets, the illness banner, then Apple Health.
