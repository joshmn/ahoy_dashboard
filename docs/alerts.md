# Alerts

Alerts watch your rank checks, what they're costing, Search Console, goals, backlinks, background jobs and your own traffic, and tell you when something changes that you'd want to know about, like a search falling off page one or a competitor passing you. Every alert lands on SEO, Alerts. It can also go to an email once a day, week or month, and to your own code the moment it fires.

Optional. It's off until you turn it on, and the rest of the dashboard works without it.

## What you need

- `AhoyDashboard::TickJob` scheduled. See [Background jobs](background-jobs.md).
- Alerts installed and switched on. Click "Turn on" beside Alerts on Settings, Features. If the row says Not installed, it shows the commands that add the tables. See [Settings, Features](configuration.md#settings-features).
- At least one rule switched on. They all start off.

Each rule only runs when its source is set up:

| Group | Needs |
|---|---|
| Rank tracking | Rank tracking running, with your own site added. Rank tracking rules only compare checks of the site whose domain matches the site host on Settings, General. |
| Spending | A search provider saved on Settings, Search provider, with a monthly cap on it. |
| Search Console | [Search Console](search-console.md) connected. |
| Goals | At least one [goal](goals-and-funnels.md#create-a-goal) set up. |
| Backlinks | [Backlinks](keyword-research-and-backlinks.md#backlinks) on. |
| Jobs | Nothing beyond the tick above. |
| Traffic | 28 days of visits stored. |

## The rules

Sixteen rules, in seven groups: rank tracking, spending, Search Console, goals, backlinks, jobs and your own traffic.

### Rank tracking rules

| Rule | Fires when | Severity | Threshold |
|---|---|---|---|
| Lost from the results | A search that was ranking drops out of the results checked | High | |
| Fell off page one | A search goes from the threshold or better to worse than it | High | 10 |
| Dropped several places | A search falls by the threshold or more between checks | Medium | 5 |
| Overtaken by a rival | A competitor moves above you on a search you were winning | Medium | |
| AI overview appeared | An AI overview shows where the check before had none | Medium | |
| Overview stopped citing us | The AI overview cited you on the check before, and doesn't now | Medium | |

Every rank tracking rule compares the two latest checks of each search from each place, and only if the newest is from the last two days. A weekly keyword is compared against the check a week before.

- "Overtaken by a rival" needs a competitor on the keyword. Both positions come from the same check, so it's one page read once, never two readings taken hours apart.
- A search that falls out of the results from inside the top 10 fires both "Lost from the results" and "Fell off page one".
- "Dropped several places" doesn't fire when a search drops out entirely. That's what "Lost from the results" is for.

### Spending rules

| Rule | Fires when | Severity | Threshold |
|---|---|---|---|
| Nearing the monthly cap | The month's search units reach the threshold share of the provider's monthly cap | Medium | 80% |

It fires once a month. Raise the cap and pass the threshold share of the bigger number, and it fires again, because raising it was a decision to spend more.

The alert says where the month stands and what the checks already scheduled will add, which is the same thing the [spend card](rank-tracking.md#the-spend-card) says on Settings, Rank tracking. The card warns at whatever threshold this rule is set to, so the two never disagree.

A provider with no cap can't fire this. There's nothing to be 80% of.

This is a warning, not the control. The cap is the control, and it still stops spending at 100%.

### Search Console rules

| Rule | Fires when | Severity | Threshold |
|---|---|---|---|
| Search clicks fell | Clicks over the last 7 finished days are down by the threshold or more against the 7 days before | Medium | 30% |
| Impressions fell | Same, for impressions | Low | 30% |

Both fire for the whole site, not per query or page. Each fires once the drop crosses the threshold, stays quiet while it's still down, and can fire again once clicks or impressions have recovered and fallen again.

Search Console only counts a day as finished 3 days after it ends, and these rules only read finished days. See [What gets pulled](search-console.md#what-gets-pulled).

### Goal rules

| Rule | Fires when | Severity | Threshold |
|---|---|---|---|
| Goal stopped converting | A goal that converted on each of the 7 days before has none in the last 24 hours | High | |
| Goal conversions fell | A goal's conversions over the last 7 days are down by the threshold or more against the 7 days before | Medium | 30% |

Both fire per goal, and the alert names the goal. "Goal conversions fell" works like the Search Console rules above: it fires once the drop crosses the threshold, stays quiet while conversions stay down, and fires again once they recover.

### Backlink rules

| Rule | Fires when | Severity | Threshold |
|---|---|---|---|
| Referring domains lost | The latest backlinks sync marked the threshold or more domains lost | Medium | 5 |

### Job rules

| Rule | Fires when | Severity | Threshold |
|---|---|---|---|
| A job failed | A scheduled job's latest run ended Failed or Did not finish | High | |
| A job stopped running | A job that's on hasn't started for twice its cadence | High | |

"Failed" and "Did not finish" are the same states shown on [Settings, Jobs](background-jobs.md#settings-jobs). "A job stopped running" means an hourly job that hasn't started in 2 hours, a daily one that hasn't started in 2 days, and so on.

These rules run on the tick, on the `low` queue, like everything else. If the tick stops, or nothing works `low`, they stop too and can't tell you. Watch for that from outside the app, with whatever checks your worker is alive.

### Traffic rules

| Rule | Fires when | Severity | Threshold | Floor |
|---|---|---|---|---|
| Traffic spike | Visitors in the last full hour reach the threshold times the usual for that hour and weekday, and at least the floor | Medium | 3x the usual | 20 visitors in the hour |
| Traffic drop | Visitors over the last 12 full hours are at or below the threshold share of the usual for those hours, and the usual is at least the floor | High | 50% of the usual | 100 visitors in the 12 hours |

"The usual" is the average of the same window, on the same weekday, in each of the 4 weeks before. For a spike that's the same hour. For a drop it's the same 12 hours. Visitors are counted the way the dashboard counts them: each visitor once per window, with crawlers left out. Weeks are stepped back in the time zone set on Settings, General, so a daylight saving change doesn't shift the hours being compared.

Neither rule fires until there are 28 days of visits, plus the 12 hours the drop rule reaches back past them. Until then Settings, Alerts says "Needs 28 days of visits" beside both.

Both fire at most once a day, with the day cut in the time zone set on Settings, General. Both also work like the Search Console and goal rules above: once the threshold's crossed they stay quiet until traffic recovers, then can fire again. A spike has recovered once the hour is back under halfway to the threshold, which is 2 times the usual at the default, or under the floor. A drop has recovered once the 12 hours are back over halfway between the threshold and the usual, which is 75% at the default.

The floor keeps a quiet site from tripping either rule on tiny numbers. Traffic spike needs the last full hour itself to have at least 20 visitors, on top of being 3 times the usual. Traffic drop needs the usual 12-hour figure to be at least 100 visitors, so a site that's normally quiet can't register a "drop" from an already-low baseline.

### Switch rules on

Settings, Alerts lists every rule with what it watches, when it fires, its severity, how often it's fired, and when it last did, grouped under the seven rule groups above.

Click Edit on a rule to change it:

| Field | Does |
|---|---|
| Status | On or Off |
| Severity | High, Medium or Low. The alert copies it when it fires. |
| Threshold | Only on the rules that have one, checked against an allowed range. Leave it blank for the default. |
| Floor | Only on the two traffic rules. Leave it blank for the default. |

Start strict, and loosen a rule if it stays quiet. A rule that sends a week of noise on day one gets its emails archived unread, which is why they all start off.

The rules themselves are code, so there's nothing to add or rewrite. A new version of the dashboard can add a rule, and it shows up switched off.

## How often they run

Rules run every hour, all seven groups on the same tick. Rank tracking rules run before that hour's rank checks, so they always read checks that have finished, and a rank tracking alert usually fires about an hour after the check behind it.

To run every rule now, click "Check now" on SEO, Alerts.

Each rule reports each change once, whichever group it's in: it fires once, stays quiet while the same thing is still true, and fires again only when a newer reading shows a new change. A search that falls off page one fires once and stays quiet while it stays down.

## SEO, Alerts

| Part | Shows |
|---|---|
| Tiles | How many rules there are and how many are on, alerts in the range, how many are high severity, rules that have never fired, where alerts are going, and how many failed to send |
| Recent alerts | Newest first, with the severity, what happened, the detail, and the rule. With a notifier set up, a Sent column says whether each one reached it. |
| Rules that are on | Each live rule, when it fires, and how often it has |

Recent alerts lists 40 at a time, newest first, with a "Pages of alerts" pager below the table once there are more than that.

A CSV button above Recent alerts exports the alerts shown, on the page's range and the page of them you are on. Rules that are on exports too. See [CSV](seo-reports.md#csv).

The notice at the top points out whatever's missing, in order: alerts switched off, nowhere for alerts to go, or no rule on.

When any alert in the range fired from sample rank checks, a warning banner says so, with a "Choose provider" button, and each affected row carries a "Sample" badge.

## Alert emails

One email per period, listing every alert from it. Set them up under Alert emails on Settings, Emails: tick how often under "How often" and list the addresses under "Send to", one per line or separated by commas. Pick no period and no alert emails go out. Alerts still show on SEO, Alerts either way.

| Email | Covers | Arrives |
|---|---|---|
| Daily | Yesterday | Every morning |
| Weekly | Monday to Sunday | Monday morning |
| Monthly | The calendar month | The morning of the 1st |

They're sent by the first tick after 7:00 AM in the time zone on Settings, General, and periods are cut in that zone too. A Monday that's also the 1st sends all three.

Every recipient is on one email, together in the To line. The list is the addresses typed on the screen. There's no way to work it out in code, like pulling every admin's address at send time.

What's in it:

- A subject like `Alerts for Sep 18: 3 alerts`.
- A count by severity.
- Up to 20 alerts, high severity first, one per rule and subject. Past 20, a link to the rest.
- A warning if any of them came from sample data.
- Buttons to open the alerts page and the rankings. Open alerts lands on the email's own period, not your default range, so every alert it lists, including the ones past 20, is on the page you land on.

### When nothing fired

By default the email goes out anyway, saying why it's empty: no rules are on, or the rules ran and nothing crossed a threshold. With rank tracking rules on, it also says how many searches were checked. A quiet email still tells you the whole thing is running.

To skip empty emails, untick "Send even when nothing fired" on Settings, Emails.

### The sender

"Send from" on Settings, Emails sets the From address, like `alerts@example.com` or `Alerts <alerts@example.com>`. Leave it blank and the email uses the default of the mailer it inherits from, which is `ActionMailer::Base` unless you set `alerts[:parent_mailer]` in the initializer. Point that at your own `ApplicationMailer` to pick up your From address and delivery settings:

```ruby
config.alerts[:parent_mailer] = "ApplicationMailer"
```

The links in the email are full URLs, so your mailer's `default_url_options` needs a `host`. Without one, every email fails.

To change the email itself, see [Extending](extending.md#changing-the-alert-email).

### Each email is sent once

Each period is sent once, however many times the job runs. If sending fails, the job shows as "Failed" on Settings, Jobs, the Failed to send tile counts it, and it's tried again the next time the job runs while that period is still the latest one. For a weekly email that's all week. For a daily one it's the rest of that day, so a daily email that fails in the morning and isn't retried by midnight is gone.

## Sending alerts to your own code

`config.alert_notifier` is called with each alert the moment it fires, for chat, a pager, or anything else:

```ruby
config.alert_notifier = ->(event) { ChatNotifier.post(event.headline) }
```

Every alert is on the page whether or not anything's set up to send it, and whether or not sending worked. See [Where alerts go](extending.md#where-alerts-go) for the fields on `event` and what happens when the notifier raises.

The notifier and the emails are separate. Use either, or both.

## When nothing fires

| Check | Rules | Where |
|---|---|---|
| Alerts are installed and on | All | Settings, Features, and the notice on SEO, Alerts |
| A rule is on | All | Settings, Alerts |
| The tick is scheduled, and the Alert rules job is running | All | Settings, Jobs |
| Your site is added, and its domain matches the site host on Settings, General | Rank tracking | Settings, Rank tracking, Sites. Without it, no rank tracking rule can fire. |
| A provider is saved with a monthly cap | Spending | Settings, Search provider. Without a cap there's nothing to be 80% of. |
| Rank checks are succeeding, and at least one ran in the last two days | Rank tracking | [Rank tracking](rank-tracking.md#when-checks-fail) |
| The search has two checks | Rank tracking | A search checked once has nothing to compare against |
| Search Console is connected and syncing | Search Console | [Search Console](search-console.md#when-it-stops-syncing) |
| At least one goal is set up | Goals | [Goals and funnels](goals-and-funnels.md#create-a-goal) |
| Backlinks are on | Backlinks | [Keyword research and backlinks](keyword-research-and-backlinks.md#turn-them-on) |
| 28 days of visits are stored | Traffic | Settings, Alerts says "Needs 28 days of visits" beside the traffic rules |

Related: [Rank tracking](rank-tracking.md), [Search Console](search-console.md), [Goals and funnels](goals-and-funnels.md), [Keyword research and backlinks](keyword-research-and-backlinks.md), [Configuration](configuration.md#settings-emails), [Extending](extending.md#where-alerts-go), [Background jobs](background-jobs.md).
