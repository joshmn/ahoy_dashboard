# Background jobs

The dashboard runs its scheduled work (Search Console syncs, rank checks, backlinks, the place list, alerts, alert emails, traffic emails and AI visibility) from one job your app schedules: `AhoyDashboard::TickJob`. You schedule the tick, and the tick decides what's due. The optional [precomputed dashboard](#precomputed-dashboard-refresh) also uses the tick to stay prepared while idle, when enabled in Settings, General.

## Schedule the tick

Run `AhoyDashboard::TickJob` every minute. Any job backend works, as long as a worker processes the `low` and `default` queues.

With sidekiq-scheduler, in `config/sidekiq.yml`:

```yaml
:scheduler:
  :schedule:
    ahoy_dashboard_tick:
      cron: "* * * * *"
      class: AhoyDashboard::TickJob
      queue: low
```

With Solid Queue, in `config/recurring.yml`:

```yaml
production:
  ahoy_dashboard_tick:
    class: AhoyDashboard::TickJob
    queue: low
    schedule: every minute
```

With plain cron and any Active Job backend:

```
* * * * * cd /app && bin/rails runner "AhoyDashboard::TickJob.perform_later"
```

The minute tick keeps an enabled default-dashboard snapshot prepared even when nobody visits. Other jobs retain their hourly, daily or monthly cadences: ticking more often does not make rank checks, imports or emails run every minute. A host upgrading from the previous 15-minute tick should update its recurring schedule once. Dashboard users only need the checkbox in Settings, General.

The tick only enqueues. It never does the work inside itself, so it's quick.

## What runs

| Job | Name on Settings, Jobs | Runs | Only when |
|---|---|---|---|
| `AhoyDashboard::Alerts::RunJob` | Alert rules | Every hour | Alerts are on and at least one rule is on |
| `AhoyDashboard::Alerts::DigestJob` | Alert emails | Daily at 7:00 in the time zone on Settings, General | Alerts are on, and Settings, Emails has a period and a recipient for alert emails |
| `AhoyDashboard::Reports::DigestJob` | Traffic emails | Daily at 7:00 in the time zone on Settings, General | Email reports are on, and Settings, Emails has a period and a recipient for traffic emails |
| `AhoyDashboard::SearchConsole::IngestJob` | Search Console, the last week | Daily at 4:00 Los Angeles time | Search Console is on, has a client ID and secret, a connected account and a property |
| `AhoyDashboard::SearchConsole::BackfillJob` | Search Console, the history | Every hour | Same as above |
| `AhoyDashboard::Backlinks::SyncJob` | Backlinks | Every day, 24 hours after the last start | Backlinks are on, the provider sells backlinks, and the provider isn't the sample one |
| `AhoyDashboard::Places::SyncJob` | Place list | Monthly on the 2nd at 3:00 in the time zone on Settings, General | The place list is on |
| `AhoyDashboard::AiVisibility::DispatchJob` | AI visibility | Every hour | AI visibility is on, an assistant has a key, and there's at least one prompt |
| `AhoyDashboard::Serp::DispatchJob` | Rank checks | Every hour | Rank tracking is on |

Every "Only when" also needs the feature installed and switched on under Settings, Features. A job whose feature isn't installed shows as Not installed on Settings, Jobs, with the commands that add its tables. See [Settings, Features](configuration.md#settings-features).

The cadences are fixed. A host can't change them, on purpose: a cadence set wrong is how you end up paying for a search result every ninety seconds.

Within the cadence registry, alerts are considered before rank-check dispatch, so an alert evaluation does not depend on checks enqueued by the same tick. Their hourly cadences are unchanged.

Search Console runs on Pacific time because that's how Google cuts its days.

Backlinks never run on the sample provider. A job writing imaginary referring domains into your database every night is worse than a stale backlinks page.

### Jobs outside the cadence registry

| Job | Queue | Started by |
|---|---|---|
| `AhoyDashboard::Serp::Keywords::CheckJob` | `low` | The rank check dispatcher and the "Check now" buttons, one per keyword per place |
| `AhoyDashboard::SearchConsole::FillJob` | `low` | "Fill these days" on Settings, Search Console |
| `AhoyDashboard::Keywords::FetchJob` | `low` | "Look up" on Keyword research |
| `AhoyDashboard::Assistant::ReplyJob` | `default` | Every question asked in Ask |
| `AhoyDashboard::AiVisibility::Prompts::RunJob` | `low` | The AI visibility dispatcher and "Run now", one per prompt per assistant |
| `AhoyDashboard::Dashboards::SnapshotRefreshJob` | `default` | The minute tick while Precompute default dashboard is enabled; saving Settings, General; eligible page requests when the snapshot is more than 30 seconds old |

On Settings, Jobs a fill job shows as "Search Console, filling gaps" with how many days are left.

The assistant and dashboard snapshot refresh use `default`; the other jobs listed above use `low`. If nothing processes `default`, assistant answers and snapshot refreshes remain queued.

### Precomputed dashboard refresh

Check **Precompute default dashboard** under Settings, General and save to queue the initial build. The setting starts off. The minute tick queues upkeep without waiting for a page visit. Eligible page requests can also queue a refresh when the snapshot is more than 30 seconds old. A worker reuses a snapshot that another worker or request has already made fresh. Turning the setting off takes effect on subsequent requests, and already queued jobs check that it is still enabled before building.

The job uses the same [configured engine cache](configuration.md#cache-store) as the web process, defaulting to `Rails.cache`. The host must already schedule the minute tick and have workers processing `low` (the tick) and `default` (snapshot builds); saving the setting does not start workers or install a recurring scheduler. PostgreSQL advisory locks serialize snapshot builds, and a one-minute enqueue lease prevents concurrent requests from immediately queuing duplicate refreshes. Workers verify the queued database, schema and definition fingerprint before building. Snapshot upkeep uses its existing cache lease rather than a cadence-registry row, so it does not appear among the jobs on Settings, Jobs. Hosts with tenant-specific database, schema or scoped-query contexts must establish that context for both their ticks and snapshot workers; the engine does not enumerate tenants.

An asynchronous summary or panel request with no usable snapshot queues a rebuild and runs only its own ordinary queries. It never waits for a full-dashboard build. The explicit complete response (`?loading=complete`), linked for browsers without JavaScript, retains its synchronous fallback. A healthy minute tick and worker keep an idle dashboard prepared. Cache eviction, midnight date changes, definition changes or delayed workers can still leave the next request without a usable snapshot. Jobs do not reschedule themselves, and there is no boot hook. Ordinary analytical query caches still have their 30-second window. Snapshots expire after 270 seconds, bounding numerical age to five minutes including that window. See [Configuration](configuration.md#precomputed-default-dashboard) for eligibility, cache-store behavior and tenant context requirements.

## Settings, Jobs

Settings, Jobs lists every job in the cadence registry, whether or not it has ever run. Something that's never run is the thing you most need to see there.

| Column | Shows |
|---|---|
| Job | The name, a "Due" badge when it's due, and what it does or why it's off, with a "Set it up" link |
| Runs | The cadence |
| State | Never run, Running, Ran, Failed, Off or Not installed |
| Last started | When the tick or the Run button last started it |
| Last finished | When it last finished |
| Run | Starts it now |

"Off" means one of its conditions isn't met, and the row says which one, with a "Set it up" link to the screen that fixes it. It isn't an error. "Not installed" means the feature's tables aren't in your database, and the row shows the install commands.

"Run" enqueues the job right away and tells you "Started Rank checks. Give it a minute, then reload." The next scheduled run counts from then. The button is disabled, with the reason beside it, while the job is off.

A failed run shows its error. Under the table, "Recent runs" keeps the last 100 runs of each job (up to 50 shown at once, newest first), with how long each took and the first lines of any error. A run still marked Running after 6 hours shows as "Did not finish", which usually means no worker picked up the `low` queue or the worker died.

"Nothing has run yet" at the top means the tick isn't scheduled.

## What "Ran" means

"Ran" means the job finished without raising. Several jobs catch their own failures and record them somewhere more useful, so "Ran" isn't always "worked":

- Search Console: a sync that hit Google's quota is "Ran" here. A refused token, a lost permission or Google not answering is "Failed". Either way, the message on Settings, Search Console says what to do.
- Backlinks: a sync that hit the provider's quota, or had its login refused, is "Ran" and only in the log. Any other failed request is "Failed".
- Rank checks: the dispatcher only enqueues checks, so it shows "Ran" even when every check fails. Failed checks show on Settings, Search provider as "Last error" for auth and quota problems, and in the log otherwise.
- Alert emails: a failed email makes the job fail, so it does show as "Failed".

The alert rules "A job failed" and "A job stopped running" watch these same runs. See [Alert rules](alerts.md#job-rules).

## Running a job by hand

Use the Run button on Settings, Jobs, or the feature screens' own buttons ("Sync now" on Search Console and Backlinks, "Check now" on Alerts, "Reach back a month" on Search Console). Both record a start the same way the tick does, so the tick won't start the same job again until it's next due.

Scheduling an individual job yourself alongside the tick is safe for the same reason: whichever one starts a job first is what the tick checks against.

Scheduled jobs claim a database lease before enqueueing, so repeated ticks or Run clicks do not start overlapping runs. An abandoned lease can be reclaimed after six hours. Retries follow your job backend's defaults; the dashboard sets no `retry_on`.

## Rake tasks

Each of these is a reference or a diagnostic. When a screen can do the same thing, use the screen.

| Task | Does | Spends money |
|---|---|---|
| `ahoy_dashboard:schedule` | Lists each scheduled job: cadence, on or off, last start, last result, whether it's due | No |
| `ahoy_dashboard:statistics` | Recreates the planner statistics on `ahoy_events`, then runs `ANALYZE`. See [Installation](installation.md#planner-statistics). | No |
| `ahoy_dashboard:search_console` | Reports the Search Console setup, connection, stored data and history | No |
| `ahoy_dashboard:search_console_pull` | Pulls the last week from Search Console now | No |
| `ahoy_dashboard:serp` | Reports the rank tracking setup, stored counts, this month's spend by kind, and what the rest of the month is scheduled to cost | No |
| `ahoy_dashboard:serp_backfill_results` | Writes ranking rows for old checks that predate them, from the stored pages | No |
| `ahoy_dashboard:serp_check[query,location]` | Checks one tracked keyword now. Respects the switch and the monthly cap and records the spend. | Yes |
| `ahoy_dashboard:serp_search[query,location,pages]` | Runs one search through the active provider and prints it. Stores nothing, but reserves and records spend like a real check, and stops at the monthly cap. | Yes, against the cap |
| `ahoy_dashboard:keywords[seed,refresh]` | Looks up keyword ideas for a phrase. Add `refresh` to buy the phrase again when it's already saved. | Yes |
| `ahoy_dashboard:backlinks` | Syncs backlinks | Yes |
| `ahoy_dashboard:alerts` | Runs the alert rules | No |
| `ahoy_dashboard:alert_rules` | Lists the alert rules and whether each is on | No |
| `ahoy_dashboard:assistant` | Reports the assistant setup: reader, model, key source, tools and the last error | No |

Rake splits arguments on commas. A city place like `city:us:Chicago,Illinois,United States` needs its commas escaped: `rails 'ahoy_dashboard:serp_check[my keyword,city:us:Chicago\,Illinois\,United States]'`.

`ahoy_dashboard:backlinks` refuses the sample provider too, the same as the schedule: run it against `:fake` and it aborts instead of writing invented referring domains into your real tables.

Related: [Installation](installation.md), [Configuration](configuration.md), [Troubleshooting](troubleshooting.md).
