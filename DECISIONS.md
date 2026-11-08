# Corva: UI skeleton decisions

This document covers what was built, how the code is organised, why the data model looks the
way it does, the judgement calls I made, and what I'd revisit. It reflects three passes:
1. The original skeleton.
2. A denser, analytics-heavy redesign after your feedback that the first version looked bland.
3. Four new features: **bio age**, **best vs worst days**, **experiments** (all in a new
   **Lab** tab), and **pacts**, goals with money on them (a new **Pacts** tab).

**State of the build:**
- The target is **iOS 26.0, iPhone only**.
- Clean `xcodebuild` runs for the iPhone 18 Pro simulator (iOS 27.2) and the iPhone 17 Pro
  simulator (iOS 26.2) both give zero errors and zero warnings. The `Core` layer also compiles
  on its own as a command-line tool with zero warnings.
- I checked every new screen in the iOS 26.2 simulator, including tagging an experiment
  evening and creating a pact end to end.
- No third-party dependencies.
- The project file has exactly three edits, listed under "Target settings".

---

## Things to look at first

1. **Target settings (changed at your request).** In `Corva.xcodeproj/project.xcproj`:
   - `IPHONEOS_DEPLOYMENT_TARGET` 27.2 → **26.0**
   - `SUPPORTED_PLATFORMS` → `iphoneos iphonesimulator`
   - `TARGETED_DEVICE_FAMILY` → `1` (iPhone)

   iPads still appear as run destinations, because iPhone apps run on iPad in compatibility
   mode. There are no native Mac or visionOS builds any more. I left the inert template
   settings that only apply to macOS and iPad, such as the sandbox and iPad orientations.
2. **The bundle identifier is still the template placeholder** (`devplaceholder.…`).
3. **Two rules from the original brief are deliberately bent in the redesign.** Your feedback
   asked for more analytics and more visual punch.
   - *"Few elements per screen"* no longer holds. Today is now a dense overview with six
     sections.
   - *"No decorative gradients"*: there are now gradients, but every one encodes data, so none
     is decorative:
     - A soft glow at the top of each screen in the colour of its headline metric: today's
       recovery zone on Today, blue on Strain, purple on Sleep, amber when a vital is out of
       range.
     - Gradients along ring strokes and progress bars.
     - Fades under line charts.

     The glow also matters for Liquid Glass. Glass only looks like glass when there's colour
     behind it to refract; over flat near-black it looked like grey plastic, which was most of
     the "bland" problem.
4. **Glass on content cards goes against Apple's guidance.** The HIG reserves Liquid Glass for
   the navigation layer. You asked for glass cards, so they use the real `.glassEffect`, tinted
   faintly with each metric's colour. If that ever reads as too much, swapping `GlassCard` to
   an opaque `surface` token is a one-file change.
5. **Pacts break two more rules from the original brief, at your request.** The brief said "no
   social features, no gamification". A pact with a friend and money on it is both. I kept it
   as plain as possible: no streaks, badges or leaderboards, just the goal, the dots, and who
   owes whom.
6. **Pacts need legal and payments work before real money moves.** The feature tracks stakes
   but moves nothing. Before it does:
   - **Payments:** you need a payment provider to hold stakes and pay out, plus a backend.
   - **Regulation:** head-to-head stakes, where the loser pays the winner, may count as
     betting. That could fall under the UK Gambling Act and the App Store's rules on
     real-money gaming. Charity-only stakes (commitment contracts) are the lower-risk shape.
     Get legal advice first; I'm not qualified to call it.
7. **Pacts aren't unique as a concept.** Commitment-contract apps (stickK, Beeminder) and
   step-betting apps already exist. What's different here:
   - **The wearable is the referee:** no self-reporting.
   - **A sick-day pass** that Corva detects from your vitals, so it can't be claimed falsely.
   - **It sits inside the analytics app,** next to the data that explains why you missed.

---

## What each screen shows now

The tab bar has five tabs: Today, Trends, Lab, Pacts and Settings.

**Today.** Previous/next-day arrows in a glass toolbar let you browse any of the last 90 days.
- **Three dials** (sleep, recovery, strain) with gradient strokes and glow, each with its
  delta against the 30-day average. The recovery zone now sits on its own line in the zone
  colour; "Recovery · Moderate" used to wrap.
- **Strain target:** today's strain against a range set by recovery.
- **Health monitor:** five vitals, now including SpO₂. Each has a range bar against its typical
  range, the baseline, the delta, and an alert colour when out of range, plus an "n of 5 in
  range" count.
- **Sleep:** asleep against need, stage mix, efficiency, deep-plus-REM share and 7-day sleep
  debt.
- **Activity:** active energy, steps, average and max HR, heart-rate zone mix and today's
  sessions.
- **Last 7 days:** recovery bars with that day's strain as a line, plus weekly averages.

**Recovery.**
- Score with its zone.
- Each contributor's own 0–100 sub-score as a bar, shown with its weight. The parts add up to
  the score exactly.
- Last 30 days with average, best and lowest, a chart you can scrub, and the zone mix.
- HRV and resting HR over 30 days with typical-range bands.
- A **strain → next-day recovery** scatter over 90 days, with r and a plain-number slope
  ("each +10 strain ≈ −5 recovery").

**Strain.**
- Target range.
- Six-stat grid.
- Heart-rate zones with time and share.
- **Training load:** the 7-day ÷ 28-day load ratio, with a balanced band at 0.8–1.3.
- 28-day strain chart.
- 14 days of strain against recovery.
- Activities with per-session zone bars, average/max HR and energy.

**Sleep.**
- Duration against need, and how far short.
- Quality grid: efficiency, latency, wakes, deep + REM, 7-day debt, time in bed.
- Hypnogram with each stage compared with its 30-day average.
- 14 nights of sleep against need.
- Bed and wake consistency.

**Trends** (7D / 30D / 90D).
- Three tinted summary cards with sparklines.
- A chart for every score and vital, each with average, low, high and change, and scrubbing.
- Recovery zone mix for the period.
- Weekday patterns over 90 days.
- **Relationships:** four correlations with r, strength and a ±1 bar. Tap one to plot its
  scatter.

**Metric detail** (any vital).
- Value, delta and an in/out-of-range badge.
- A range bar.
- A 30-day chart with a band.
- Average, low, high, the last 7 days against the 30-day average, days out of range, and spread.

**Lab** (teal glow).
- **Bio age card:** bio age, years younger or older than your age, an age scale, an 8-week
  sparkline, and the biggest factors for and against.
  - **Detail:** the number, the change since the first weekly point, net years by area
    (fitness, heart, activity, sleep), a weekly trend against your age, and all nine markers.
    Each marker shows your value, the typical value for your age, and a diverging bar of
    years added or taken off.
- **Best vs worst days card:** the average score on your best and worst quarter of days, and
  the top three factors that separated them.
  - **Detail:** rank by recovery, HRV or sleep performance.
    - A strip of all 89 days with the best and worst marked, so clusters such as illness
      show up.
    - Every factor as a dumbbell: best-day average against worst-day average on one scale,
      with a size label.
    - Factors cover the day before (strain, hard minutes, steps), the night (bed and wake
      time, time in bed and asleep, deep + REM, wake-ups), weekend mornings, unwell days,
      and **any on & off experiment's tags**. That's how alcohol shows up as a separator.
- **Experiments list:** design, day *n* of *N*, the headline measure's change, a verdict
  badge, and a forest-plot bar.
  - **Detail:**
    - The headline change with its 95% interval and a plain sentence.
    - Every measure with before → after.
    - A dot chart of each morning with group means.
    - A **tap-to-tag evening grid** (on & off designs), where results update live.
    - **Sensitivity:** the smallest effect the data can catch now and by the planned end.
    - A method note saying how many unwell days were left out.
    - A menu to end early or delete.
  - **New experiment sheet:** title with suggestions, design, measures (the first is the
    headline) and length.

**Pacts** (pink glow).
- **Record:** pacts kept out of finished, money won, money paid.
- **Active pact cards:**
  - The goal, the terms, and a row of day dots each for you and (head-to-head) your friend:
    met, missed, sick day, today, upcoming.
  - Today's running total for activity goals.
  - A status line ("No misses left · 4 days to go", "Broken · you owe Sam £5").
- **Finished list:** each pact with Kept or Broken and who paid whom.
- **Detail:**
  - Both participants' dots.
  - A chart of each day against the target line, with the friend's days as diamonds.
  - A day-by-day table, and the terms.
- **New pact sheet:**
  - Goal (steps, sleep, exercise, strain, bedtime), target, length, and "must hit *n* of *N*".
  - Head to head or just me; if just me, pay a friend or a charity.
  - Stake, sick-day pass, and a plain-English "The deal" summary.

**Settings** gains two sections:
- **Profile:** age and sex, used only for bio age reference values.
- **Pacts:** currency for new stakes, defaulting to the region's (pounds on a UK device).

---

## Folder structure

```
Corva/
├── App/                         Entry point, tab bar, environment, settings store, preview helpers
├── DesignSystem/
│   ├── Tokens/                  Colours (incl. alert), metric→colour mapping, spacing/radii/sizes, type styles
│   └── Components/
│       ├── ScoreRing            Gradient + glow ring, small/medium/large
│       ├── MetricCard           Tinted glass card with label, value, unit, delta, sparkline
│       ├── Sparkline, SectionHeader, StatRow, DeltaLabel
│       ├── StatGrid             StatTile + equal-width grid
│       ├── Bars                 RangeBar, TargetBar, ProgressBar, SegmentedBar, ChartLegend
│       ├── TrendChart           Bars/line + band + reference + scrubbing with a glass bubble
│       ├── ComboChart           Bars and a line on one day axis
│       ├── ScatterChart         Paired values with fitted line
│       ├── AnalyticsBars        IntervalBar (forest plot), DumbbellBar, DivergingBar
│       ├── Surfaces             GlassCard (tintable), CardHeader, CardDivider, ambient glow background
│       └── LoadStateView
├── Features/
│   ├── Today/                   Overview + day navigation
│   ├── Recovery/  Strain/  Sleep/   Detail screens (Strain also owns the shared ActivityRow)
│   ├── MetricDetail/            Any single vital
│   ├── Trends/
│   ├── Lab/                     Lab tab, bio age, best vs worst days, experiment detail, new experiment
│   ├── Pacts/                   Pacts tab, pact detail, new pact
│   └── Settings/
└── Core/
    ├── Models/                  DailySummary, SleepStage/Segment/Metrics, Activity, HeartRateZone,
    │                            DataSource, Metric, Baseline, Units, Profile, Experiment, Pact
    ├── Data/                    HealthDataProvider protocol, MockHealthDataProvider (+ MockLifestyle),
    │                            seeded RNG, ExperimentStore, PactStore
    ├── Analytics/               Scoring, Statistics, Insights, BioAge, DayContrast,
    │                            ExperimentAnalysis, PactEvaluation (+ unwell-day detection)
    └── Formatting/              MetricFormatter, MetricFormatter+Lab (signs, clock times, money, goals)
```

The Lab screens share one view model type, `LabViewModel`, which loads 90 days and runs the
analyses. Each screen owns its own instance, so the rule of one view model per screen still
holds. Pacts work the same way with `PactsViewModel`.

`Core/Analytics` and `Core/Formatting` go beyond the folders in the brief. Analytics is Corva's
product, so it gets its own home as pure, deterministic functions. Every number in the UI goes
through `MetricFormatter`, so units and precision stay consistent.

---

## Data model, and why it's shaped this way

### `DailySummary` is morning-anchored

```
DailySummary(date)
├── sleep     the night that ended on the morning of `date`
├── vitals    HRV, resting HR, respiratory rate, SpO₂, skin temperature (measured that night)
├── recovery  scored from that night's vitals and sleep
├── strain    the rest of `date`: score, zones, activities, energy, steps, avg/max HR
└── baseline  30-day stats as they stood that morning
```

This matches how people experience the data: you wake up, see your recovery, then build strain.
It also makes the causal chain explicit. Day N's strain affects night N+1, which feeds day
N+1's recovery.

### Scores are computed by Corva, not taken from a source

Neither Google Health nor Apple Health supplies Corva's scores, and their own scores differ.
`Scoring` turns raw signals into scores so a recovery of 72 means the same thing whatever the
source. Recovery's sub-scores are separate public functions, so the Recovery screen can show
exactly how the score was built.

### Each day stores its own baseline snapshot

`DailySummary.baseline` holds the mean and SD of every metric over the **preceding** 30 days,
with no look-ahead. It's stored so a historical score can always be explained against the
baseline it was actually scored with. The "typical range" is mean ± 1.5 SD, so roughly seven
days in eight fall inside it. I widened it from ±1 SD so the health monitor flags about 0.8
vitals a day rather than crying wolf.

### Everything else

- **Sleep durations are derived from the segments**, so the hypnogram and the headline numbers
  can't disagree.
- **`Metric` is the shared vocabulary** for baselines, charts, colours, formatting, the health
  monitor and relationships. SpO₂ was a one-case addition that appeared everywhere.
- **Storage uses canonical units:** ms, bpm, breaths/min, %, °C absolute, metres. Conversion
  happens only at display time.
- **The data layer is `nonisolated` and `Sendable`; UI and view models are `@MainActor`.** This
  matters because the project uses MainActor default isolation.
- **`HealthDataProvider` has two requirements:** summaries in a date range, and connection
  status. Views get `any HealthDataProvider` from the environment, so only `CorvaApp` names a
  concrete provider.
- **VO2 max lives on `Vitals`.** Sources report the latest estimate, which moves slowly, so
  every day carries it. It isn't a `Metric` case because it isn't a nightly vital and shouldn't
  appear in the health monitor.

### Experiments and pacts are user content, not health data

Health data comes from a provider. Experiments and pacts are things the user creates, so
they live in two small `@Observable` stores, `ExperimentStore` and `PactStore`, injected into
the environment. Both are **in memory only**, matching the brief's "no persistence yet".
When persistence arrives, the stores keep their methods and get SwiftData or a sync service
behind them. Analyses never live in the stores: views pass a store's items plus provider data
into pure functions in `Core/Analytics`.

### Experiment dates are evenings

Most changes (a drink, a supplement, a bedtime) happen in the evening and show up in the next
morning's summary. So an experiment's `start` and its tags are **evenings**, and the
analysis reads the summary of the morning after each one. Pact days follow the same rule for
sleep and bedtime goals: the night that starts on pact day *D* is settled by the summary of
*D* + 1. Activity goals are settled by day *D* itself.

---

## Scoring and analytics (v0, uncalibrated)

| What | Definition |
|---|---|
| **Recovery** | 50% HRV + 20% resting HR + 30% sleep, each a 0–100 sub-score. HRV: 58 at baseline, ±2.5 per 1% from baseline. RHR: 58 at baseline, +8 per bpm below baseline. Sleep: 100 at full performance, −2 per point short. Zones: ≥67 high, 34–66 moderate, ≤33 low. |
| **Strain** | Edwards TRIMP (zone-weighted minutes) through `100·(1 − e^(−load/250))`. Saturating. |
| **Sleep** | Time asleep ÷ need, capped at 100. Need = 7h45m + up to 35 min for the previous day's strain + up to 40 min towards sleep debt. |
| **Consistency** | 100 − the average of the bedtime and wake-time SDs, in minutes, over 7 nights. |
| **Strain target** | `22 + 0.55 × recovery`, ±7. 30% recovery gives ~32–46; 90% gives ~64–78. |
| **Training load** | Mean daily load over 7 days ÷ over 28 days. 0.8–1.3 is "balanced". |
| **Sleep debt (7d)** | Sum of shortfalls against need over the last 7 nights. Surplus nights don't repay it. |
| **Relationships** | Pearson r and a least-squares fit, x on day N against y on day N + lag. |
| **Trend "change"** | Change along the least-squares line across the period, not period-over-period (there is no "previous 90 days" in 90 days of data). |
| **Unwell day** | Three or more vitals outside their typical range *in the direction illness pushes them*: HRV or SpO₂ low; resting HR, breathing rate or skin temperature high. Used to set days aside, never to diagnose. |
| **Bio age** | Calendar age plus years from nine markers over the last 30 days, each capped (see below). |
| **Best vs worst days** | The top and bottom quarter of 89 days by recovery, HRV or sleep performance. Factors are ordered by Cohen's d (difference in means ÷ pooled SD). Size labels: under 0.2 none, under 0.5 small, under 0.8 clear, 0.8 and over big. |
| **Experiments** | Welch two-sample comparison of mornings with and without the change. The interval is the difference ± t × SE, with Welch–Satterthwaite degrees of freedom. The verdict is "better" or "worse" only when the 95% interval excludes zero. "Can detect" is (t + 0.84) × SE: the effect size with 80% power. Unwell days are dropped from both groups. Each group needs 5 days first. Before & after compares with the 28 mornings before the start; on & off compares tagged and untagged mornings within the experiment. |
| **Pacts** | Each day is met, missed, a sick day, today, or upcoming. Sick days come off the pact, so the requirement becomes min(required, length − sick days). A pact is **kept** once met ≥ required, even early, and **broken** once met + days remaining < required. Head to head: one kept and one broken means the broken side pays; both the same means nobody pays. A finished day with no data counts as a miss, because the wearable is the referee. |

**Bio age markers.** Typical values are for your age, and for your sex where set; "not set"
uses the midpoint between the two.

| Marker | Typical value | Years | Cap |
|---|---|---|---|
| VO2 max | 42 at 25 (male 46, female 38), −0.4 a year after 25 | −0.3 per ml/kg/min above | ±4 |
| Resting HR | 65.5 (male 64, female 67) | +0.12 per bpm above | ±2.5 |
| HRV | 92 × e^(−0.022 × age) | −3 × ln(yours ÷ typical) | ±2.5 |
| Daily steps | 7,500 | −0.4 per 1,000 above | −1.5 to +2.5 |
| Moderate cardio (zones 2–3) | 150 min a week | 1.2 × (1 − yours ÷ 150) | ±1.2 |
| Vigorous cardio (zones 4–5) | 75 min a week | 0.8 × (1 − yours ÷ 75) | ±0.8 |
| Strength sessions | 2 a week | 0.4 per session short | ±0.8 |
| Sleep duration | 7–9 h | +0.9 per hour under 7, +0.6 per hour over 9 | 0 to +2.5 |
| Sleep consistency | 80 | +0.04 per point under | −0.6 to +1.5 |

None of this is coaching: there are no prose recommendations anywhere, only numbers and how
they were made. All constants live in `Scoring.swift`, `Insights.swift`, `BioAge.swift` and
`ExperimentAnalysis.swift`.

---

## Mock data

There are 90 visible days plus 30 hidden warm-up days, from a seeded SplitMix64 RNG, so the
data is identical on every launch. The days are causally linked:
- **Weekly plan:** strength Monday, tempo run Tuesday, walk Wednesday, intervals Thursday,
  optional yoga Friday, long run or ride Saturday, easy Sunday.
- **Recovery shapes training:** low recovery shortens sessions; high recovery pushes harder.
- **Strain shapes the night:** yesterday's strain raises tonight's sleep need and restlessness,
  and lowers HRV the next morning.
- **Late nights:** Friday and Saturday bedtimes run later, and occasional late nights against a
  fixed alarm make short sleep, then low recovery.
- **Two colds:** skin temperature, respiratory rate and resting HR rise; HRV and SpO₂ fall;
  sleep fragments; training stops.
- **Steps** come from everyday walking plus cadence-based steps for walks, runs and strength
  sessions.
- **Alcohol** on about one evening in five, mostly Fridays and Saturdays, and never while ill.
  The next night's HRV falls 14% and resting HR rises 3 bpm, bedtime runs 20 minutes later,
  and sleep fragments.
- **An early-bedtime fortnight** about two months ago: in bed by about 10:20 PM every night.
- **Magnesium**, started 12 days ago, with **no effect at all**. It's the honest null result.
- **VO2 max** climbs slowly from about 44 to 46.

`MockLifestyle` exposes these behaviours, so the mock experiments and pacts are seeded from the
same events the data reflects. Their results aren't scripted: they come out of the generated
days. The behaviours and VO2 max draw from a **second RNG stream**, so the original
physiology sequence is unchanged. The alcohol effects still shift some days, which is why
today's recovery moved from 33 (red) to 63 (amber).

Resulting shape over 90 days:
- Mean recovery about 67: 51 high, 33 moderate and 6 low days.
- Mean sleep 7.65 h against an 8.2 h need.
- Correlations: strain → next-day recovery r ≈ −0.36, sleep → recovery about +0.6, strain →
  next-day HRV about −0.37, resting HR → recovery about −0.8. Alcohol is now a large source
  of variance, which weakens the strain links and strengthens the resting-HR one.
- Four days are flagged unwell: the two colds.
- **Bio age** comes out at 27.5 for the default age of 32.
- **Experiments:**
  - **Alcohol:** HRV −8 ms, resting HR +3 bpm and recovery −26%, all "worse"; sleep "no
    clear change".
  - **Magnesium:** no clear change anywhere.
  - **Early bedtime:** sleep +7% "better"; recovery and HRV not clear.
- **Pacts:** two active (one with no misses left, one with 2 to spare) and four finished.
  Of the finished ones, one was broken around the first cold, with 2 sick days excused.

Every day, today included, is treated as complete.

---

## Design system notes

- **Every colour is a token** with light and dark values. A light theme means tuning the light
  values and removing `.preferredColorScheme(.dark)`. The light values are untested.
- **One hue per metric:** recovery green, amber or red; strain blue; sleep purple. Zones and
  stages use opacity steps of their parent hue. A single extra **alert** colour (orange) marks
  out-of-range values. Deltas stay neutral grey with arrows.
- **New hues:** **bio age teal**, which also marks the Lab and the "with change" mornings in
  experiment charts, and **pact pink**.
- **Better and worse use recovery's green and red.** This applies to experiment verdicts,
  bio age factors, best and worst days, and met and missed pact days, so "good" looks the same
  everywhere. It bends the neutral-deltas rule on purpose: these are judgements, not raw
  changes. Metrics with no good direction (strain, breathing rate, skin temperature) get a
  neutral "higher" or "lower", never green or red.
- **The New experiment and New pact confirm buttons** are tinted teal and pink. Left alone,
  they'd render in system blue.
- **Liquid Glass, all native:** `.glassEffect` with tint and `.interactive()`,
  `GlassEffectContainer`, the system tab bar, toolbar and segmented control, and a glass bubble
  that floats over a chart while scrubbing.
- **Motion:**
  - Rings sweep in on appear and respect Reduce Motion.
  - A light haptic fires on tab change, on day change, and when you pick a relationship.
  - Charts react to scrubbing.
- **Two non-obvious fixes:**
  - **Glass isn't hit-testable**, so cards set an explicit `contentShape`.
  - **Swift Charts axis labels:**
    - On categorical axes, Swift Charts puts the labels inside the plot. The hypnogram and the
      bedtime chart use numeric rows instead.
    - On numeric axes, labels sit slightly right of their ticks. The weekday charts label each
      bar with an annotation instead.

---

## Unsure about, or would revisit

- **Calibration.** Every weight, the strain target and the training-load band are educated
  guesses. Validate them against real data before anyone relies on them.
- **Bio age is the most fragile number in the app.** Its references come from population norms,
  and its effect sizes are plausible guesses. They aren't fitted to outcome data. It's also
  generous to fit people: −4.5 years for the mock user.
  - Calibrate it, or soften it to an "age range", before launch.
  - Present it as "fitness age"-style framing, not a health claim. "Biological age" invites
    medical reading, so the footnote says it isn't a medical test.
- **Experiment statistics are honest but simple.**
  - **Optimistic intervals:** consecutive days are correlated, which the intervals ignore.
  - **Multiple comparisons:** each extra measure is another chance of a fluke. The sheet warns
    about this, but nothing corrects for it.
  - **Better options:** a block bootstrap, or a mixed model with day-of-week and strain as
    covariates.
- **Experiment tags only count over the tracked window.** In best vs worst days, days outside
  an experiment are treated as unknown rather than "didn't happen". A general journal (tag any
  evening, any time) would make that factor much stronger.
- **Pacts need a backend:**
  - stakes held by a payment provider;
  - friends with their own accounts, sending verified numbers (a friend's numbers are
    simulated now);
  - invitations and acceptance (a head-to-head pact currently starts without the friend
    agreeing);
  - a legal review (see the top of this document).
- **Pact edge cases:**
  - Today counts in progress until midnight. Real data will need to know when a day is
    truly over for each source's sync timing.
  - Nobody can cancel a pact, deliberately. Real pacts will need a dispute path for
    wearable gaps that aren't the user's fault.
- **Five tabs is the limit** before "More" appears. A sixth area would have to fold into Lab or
  Trends.
- **Persistence.** Experiments, tags and pacts reset on relaunch, as the brief asked for now.
- **Correlation is not causation.** The relationships card shows r honestly, but users may read
  causation into it. A minimum-days threshold and confidence intervals would help.
- **Merging two sources.** A composite provider will need per-metric provenance and a single
  scoring pass over merged raw data.
- **Baseline robustness.** Plain mean and SD let illness drag the baseline for a month. A median
  and MAD, or excluding flagged days, would be more robust.
- **Partial days.** The strain target and activity card don't yet show an "in progress" state
  for today.
- **Density versus accessibility.** I haven't tested the denser screens at large Dynamic Type
  sizes. The 4-column stat grid and the health monitor rows will likely need a stacked layout
  there.
- **Scatter axis labels** still sit a few points right of their grid lines (see above). The
  last date label on short line charts (the bio age trend) can truncate ("2 N…").
- **Still to do:**
  - time zones and DST;
  - localisation of strings built in code;
  - Swift 6 language mode;
  - unit tests for `Scoring`, `Insights`, `BioAge`, `DayContrast`, `ExperimentAnalysis` and
    `PactEvaluation`. They're all pure and easy to test; `PactEvaluation` and
    `ExperimentAnalysis` most need them, because money and verdicts depend on them.
- **Build log noise:** `appintentsmetadataprocessor` prints a "Metadata extraction skipped" line
  on every build. It's a tool log, not a compiler diagnostic.
- **Git:** nothing is committed. The template rename and removal are staged; everything else is
  untracked or modified.
