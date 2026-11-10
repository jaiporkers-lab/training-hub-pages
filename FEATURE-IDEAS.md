# Training Hub · feature ideas

Prioritised around useful local calculations and manual prompt sharing. The sections separate included features from proposals.

## Included through 0.8.5

- **Pool lengths:** recorded lengths, rests and strokes, plus calculated pace and SWOLF when the necessary fields are present.
- **Activity comparison:** sensor overlays by elapsed time or distance, shared inspection, whole activities and matched legs, duration bars, signed differences and direct navigation.
- **Personal heatmap:** continuous outdoor GPS heat by date, sport or recording. Hover to count nearby activities and click to open any matching recording. Indoor and virtual routes are excluded. Apple Maps streets and idle-edge trimming start on, and both can be turned off.
- **Welcome guide:** import or connect during setup, tour every workspace, and see the latest changes after an update or a long break.
- **Home dashboard:** recent activities, weekly totals, a user-set time goal, dated health snapshots, card visibility controls and quick navigation. The Home button and TH logo both return Home.

- **Mouse inspection:** activity, health and weekly charts show values on hover, with click/drag selection retained.
- **Training trends:** weekly time/distance, sport breakdown, and an aligned previous-period comparison.
- **Import all:** Garmin activity history continues through resumable batches; cancel without losing finished imports.
- **Health:** daily Garmin wellness, sleep, HRV and weight summaries where supplied; 7/14/30-day comparisons, units and recorded coverage. Missing values remain missing.
- **Prompt builder:** locally prepares a preview of training totals and optional selected health averages. You copy exactly the reviewed text into ChatGPT. No automatic sharing, AI API key or model calls. Health sharing is off by default; GPS, activity names, notes and credentials are excluded.
- **All stats:** searchable original FIT session/developer fields with recorded units, for individual activities, legs and whole-race inspection.
- Demo controls removed; existing synthetic activities are removed after a verified recovery backup.

## Highest-value next additions

| Feature | What it would add | Local computation |
| --- | --- | --- |
| Running consistency | Split pace, heart-rate drift and steady-effort comparison with coverage checks | Yes |
| Cycling power curve | Best 5-second to 60-minute efforts, with gap handling and configurable FTP | Yes |
| Training calendar | Weekly plan, completed sessions, race dates and drag-to-reschedule plans | Yes |
| Goals and personal records | Weekly volume targets, distance milestones and recorded best efforts | Yes |
| Route analysis | Colour tracks by HR/pace/power, find climbs, compare repeated routes, and show elevation profiles | Yes, optional street basemap |
| Health/training alignment | Place daily health and training volume on aligned plots; show associations without claiming causation | Yes |
| Dashboard presets | Save layouts for triathlon, running, cycling, swimming and recovery | Yes |
| Gear tracking | Shoes/bikes/components, mileage and configurable service reminders | Yes |
| Data quality centre | Import coverage, gaps, duplicate candidates, sensor dropouts and retry queue | Yes |
| Reports | Private PDF/HTML race and training summaries with selected charts | Yes |
| Race execution | Segment targets and planned versus recorded swim, bike, run and transition times | Yes |
| Workout library | Save reusable sessions and link completed recordings to them | Yes |
| Equipment history | Review mileage and service intervals by bike, shoes or component | Yes |
| Recovery trends | Track long-term sleep, resting heart rate and HRV alongside training volume | Yes |
| Library tools | Bulk tags, favourite routes and saved comparisons | Yes |

## Local prompt-builder evolution

1. **Included: reviewable ChatGPT brief.** Add your goal and available time, prepare the brief, inspect it, then copy it yourself. The app performs the numerical analysis locally; ChatGPT can interpret the summary after you choose to share it.
2. **Next: coaching context.** Race dates, preferred training days, target disciplines, subjective fatigue and athlete-entered limitations, with per-field inclusion controls.
3. **Next: structured follow-up.** Save a coach's proposed sessions as a draft plan, review each session, and compare completed work against that plan. No automatic changes to Garmin training plans.
Built-in AI conversations, model runtimes and AI API dependencies are excluded from the current scope. The prompt builder only prepares text for the athlete to review and share separately.

Coaching should cite the dates and observations behind each suggestion, ask for missing goals/context, distinguish facts from hypotheses and avoid invented readiness scores or medical diagnoses. Performance/health associations are exploratory.

## Suggested order after this release

Build a training calendar with completed sessions and planned race dates, then add personal records and cycling power-duration analysis. Verify a representative full-history import before relying on longitudinal conclusions. Keep each slice independently useful, tested and checkpointed. Expand the coaching brief using those already-computed results to minimise model usage.
