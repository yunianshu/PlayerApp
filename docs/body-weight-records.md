# Body weight records and optional AI context

Measurements are local calendar-day kg records (one per day), not fitness scores. The 20–500 kg input range is a broad typo/unit guard, not a medical classification or training eligibility test. There is no BMI, target weight, diet plan or weight-triggered automatic training change. No legacy body-weight field exists in the baseline, so no historical measurements are invented.

The profile page provides create, explicit edit and confirmed delete. Real dates drive the scatter chart; missing measurements are left unknown. Single-key serialized persistence reloads the preferences cache on native write failure. Duplicate dates must be edited explicitly. Backup optionally includes weight only after the user chooses it; import keeps existing local dates and validates the entire incoming weight batch before writing. Normal training-plan sharing excludes weight.

Every new-plan or adjustment request has an unchecked optional consent control inside the provider/endpoint disclosure. Only the recent 28-day bounded summary is sent, including first/last values and the adjacent-week aggregate fields described below. No daily history or inferred missing values are sent. No measurements means normal plan generation remains available without weight. Summaries are never persisted into inputProfile and cannot be silently sent in later adjustments. Changes to consented records invalidate pending generation and draft save. Existing training-validation limits remain independent of weight; model instructions prohibit weight-driven load increases, faster pace, weight loss or diet prescriptions. Generated text is still an AI suggestion, not a medical evaluation.

Safety rationale: [Australian Sports Commission / AIS physique considerations](https://www.ausport.gov.au/ais/position_statements/physique-considerations) emphasizes individual context, voluntary assessment, consent, careful interpretation and wellbeing rather than compulsory body assessment. [NHS unintentional weight loss](https://www.nhs.uk/symptoms/unintentional-weight-loss/) advises professional assessment for continuing unintended weight loss, especially with other symptoms. The app does not invent numeric clinical thresholds from these sources. Reviewed 2026-10-23.

All automated tests use synthetic measurements and fake transports; no real health data or credentials are transmitted.

Validation status for the recovered checkout (2026-10-24 21:26 UTC): a fresh run of the 10-file adaptive/results/generator/revision/preview/weight-service/consent-flow group passed all 92 tests. This includes stale weight consent, concurrent failure recovery, three-theme adjustment previews and narrow-screen results. This is a focused run, not a claim that the complete suite, Android APK, Harmony HAP or real device validation passed. UI CRUD and full-suite/build results are tracked separately by integration.

## Weight-aware adaptive proposals

The opt-in summary includes two adjacent UTC calendar windows (today−13..−7,
then today−6..today), each observed mean/count, snapshot date, last-measurement
age and mean difference. Each window needs three distinct measurement dates.
This is a product data-quality gate, not a clinical threshold. Single, sparse or
stale samples do not imply a usable trend. Missing days are never interpolated;
no daily readings are sent and the consent text lists every aggregate field.

With consented weight, the AI response must include `weightAssessment` (`used`,
`reason`, `supportingSignals`). Claims of using weight are rejected unless the
trend gate passes and the named actual-training/fatigue signal exists within the
same 14-day window. Missing fatigue is not replaced with zero. Unknown/duplicate
signals and contradictory use flags fail closed. This validates evidence
existence, not the causal truth of model prose. Weight never expands distance or
pace limits and there is no weight-to-kilometre/performance formula or forced
weight-loss target. The original reference HTML and its synthetic 74 kg baseline
are not copied into measured history.

Review shows factual evidence even for an unchanged proposal (Apply disabled).
Evidence remains transient, not saved as plan metadata or silently resent.
Changes to weight, activity duration/source, recovery, completion, revision or
calendar date invalidate a proposal before sending, previewing or saving. User
confirmation remains mandatory; cancel/back preserves the plan. Generated notes
can still contain sensitive context, so sharing full notes remains opt-in.

## Actual activity evidence and known limits

Deduplicated, valid records supply a 28-day activity count/total distance,
longest single activity, active seconds and weighted mean pace only for records
with usable duration, and GPS/manual/GPX source counts. The same deduplication
powers day-by-day distance results. No GPS, notes or invented sensor fields are
sent. Heart rate and sleep are explicitly uncollected, not normal/zero values.
Observed pace is not a predicted marathon pace or finish-time guarantee.

The next-seven-day preview flags LONG tasks longer than the observed longest
single activity, or without records, as unverified. An unchanged 20→26 km schedule
is not marked safe merely because its date arrived. This is a review warning,
not safe positive progression. Current adjustments only reduce load or make
bounded same-week moves; dynamic finish-time forecasting, positive progression,
heart-rate collection and sleep input are not implemented. Race goals remain
pending reassessment.

The local fallback no longer converts absent/partially imported records into
zero adherence. Distance-based reduction requires explicit valid observations
on every past planned run day; real fatigue/pain may prompt recovery separately.
Weekly running-day count derives actual tasks, excluding strength/rest/cross/race,
not the count of available training weekdays.

Regression coverage includes all these evidence guards, 4 selected weekdays
rejecting a fifth run day, rest/strength excluded from run counts, unchanged
proposal evidence, and preservation of stale-plan protection. BodyWeightService
also tests serial concurrent writes with a failed head and later recovery; the
queue clears its completed Future without dropping queued operations. Narrow
screens/large text retain complete recovery-card labels using Flexible layout.

Recovery checkpoint 2026-10-24: this implementation and tests were reconstructed
after an environment rollback. The focused 92-test run above was executed again
against the restored checkout, rather than inherited from earlier results.
Source formatting and integration analysis/build checks are separate. No commit
or publication is implied by this document.

## Integrated recovery verification — 2026-10-24

Current recovered source: Flutter 3.47.5 / Dart 3.13.4 analyzer passed with no issues; the full suite passed 572/572 tests. Native host-policy checks passed (Python: 19 passed, one existing skip). Android APK validation awaits the exact published commit’s CI run. Harmony HAP compilation, physical device vibration and native sharing are not verified by these tests.
