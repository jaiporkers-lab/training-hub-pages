# Using GarHub

Open the question-mark toolbar button for welcome setup and the live app tour. The tour opens actual sections, highlights navigation and analysis controls, and finishes with highlighted new options. Back, Show this section and End tour are available throughout. Setup appears on first use, after an app update and after more than three months away.

## Home and activity library

Use the logo or Command–1 to return Home. **Customise Home** offers sport presets, card toggles and saved layouts. Presets choose a sport focus and visible cards. The triathlon preset shows all sports with volume, goals and recent recordings; recovery emphasises health and volume. Saved layouts do not contain activities or credentials.

Search, filter and sort the sidebar. **Views** saves filter combinations. Each original multisport recording has one expandable row, with individual legs beneath it. **Import all history** imports Garmin history in resumable batches; it does not upload files to Garmin. FIT imports are deduplicated by original-file hash.

## Activity analysis

Hover a graph for recorded values. Click or drag to pin the inspection. Whole multisport charts identify the leg at that point. Use smoothing for display, and the time-range sliders to analyse an interval. Statistics use raw samples. Laps can focus the chart. Set your own thresholds in Zones. All stats searches original session fields; Pool lengths shows recorded lengths and rest information when available.

### Running and cycling performance

Open a run or bike leg and choose **Performance**.

Running splits use elapsed time and interpolated recorded distance, including a final partial split. Missing distance, a reset or a recording gap over 30 seconds prevents a split crossing that gap. Best distance efforts include internal pauses in elapsed duration.

Select a steady interval and another run for a comparison of the same relative elapsed range. Drift compares speed/HR efficiency in equal elapsed halves. It requires at least 10 minutes, with at least 80% paired coverage in each half. Speed must exceed 0.5 m/s. Positive drift means efficiency decreased. Speed variation is the time-weighted within-half coefficient of variation. These values do not adjust for heat, terrain or conditions.

Cycling power curves use best covered averages for 5, 15 and 30 seconds and 1, 2, 5, 10, 20, 30 and 60 minutes. A reading holds until the next sample, for up to 30 seconds. Missing power and longer gaps break an effort; zero watts is valid. Enter your FTP for percentages, or use zero to disable them. FTP is not estimated.

## Calendar and goals

Create a workout or race with a title, date, sport and planned minutes. Drag a planned card to another day to retain its clock time on the new date. Completed recordings open activity analysis. Plans and completed recordings remain separate; plans are not sent to a Garmin device. **Undo last change** reverses the latest plan edit while the calendar is open.

**Watch calendar** explains the current integration limit. Garmin's Personal API exposes no workout/calendar scheduling writes. Automatic publishing requires the separate [Training API with Enterprise access](https://developer.garmin.com/gc-developer-program/enterprise/training-api/). The Personal API key already used by GarHub cannot enable that. Use a plan's context menu to **Copy details for Garmin Connect**, create and schedule the workout there, then sync your compatible watch. Local plan changes do not update the watch. [Garmin scheduling instructions](https://support.garmin.com/en-US/?faq=XRcMvEtKdf7yBf8My9jua6). Checked against Garmin's published API documentation on 14 November 2026.

Goals track imported weekly time and distance, starting Monday, and a cumulative recorded-distance milestone. Zero disables a target. The recorded-bests scan reads individual running or cycling sessions, including multisport legs. Recalculate after new imports. Results can differ from Garmin's proprietary personal records.

## Routes

**Map** shows outdoor GPS heat density. Filter by period, sport or recording. Hover to count nearby activities and click to pin the list. Open an activity from that list. Basemaps default on and can be disabled. The idle-edge switch defaults on and trims only established stationary time before and after movement. Mid-activity pauses remain.

In an outdoor leg's **Route** tab, colour tracks by HR, pace, power or elevation. Grey means missing sensor data. GPS gaps and implausible jumps break the route. View elevation by recorded distance.

Climbs need at least 50 m net rise over 300 m. Elevation is smoothed using five points spaced about 20 m apart; an 8 m descent ends a climb. These are local heuristics, not certified segments.

**Find similar recordings** checks the same sport, distance within 20% and bidirectional GPS-footprint coverage in neighbouring 100 m cells. Minimum distance is 500 m and minimum coverage is 65%. Matches are approximate and may differ in direction or exact course. Compare summary differences and elevation profiles, or open a matching recording for the full activity comparison tools.

## Health and recovery

**Health** compares two completed-day periods. **Recovery** aligns daily imported training with any supported saved health metric and a 7-day rolling mean. Hover for the date, measurement, rolling coverage and imported training.

The recent mean covers the last seven completed days. Its baseline is the preceding 28 days. Coverage counts accompany both. Associations use Pearson correlation, at least 10 paired days, and nonzero variation. Choose same-day or next-day health. This is descriptive, not causal or diagnostic.

A day without an imported activity is zero imported training, not proof of rest. Health gaps remain missing. Training volume sums recorded timer time, falling back to elapsed duration, on the recording's start date. Sleep follows Garmin's calendar date. Health sync retrieves the selected comparison periods, at most 60 days per action; longer views use retained local history.

## Privacy and recovery of data

Original FIT files and SQLite data remain local. Calendar plans, goals and dashboard settings are included in library backups; Garmin keys are excluded. Settings → Library creates and restores checked backups. Keep backups and exports private. The prompt builder creates text locally and only copies when you choose; it makes no AI calls.

Apple Maps can receive viewed map areas when the street basemap is enabled. See [Security and privacy](../SECURITY.md) for network and data boundaries.
