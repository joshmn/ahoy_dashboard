# Email reports

A traffic email for yesterday, last week or last month: how many people came, where they came from, and what they read, sent to whoever you list. It covers the whole site, the way the dashboard does with no filters on.

Optional. It's off until you turn it on, and the rest of the dashboard works without it.

It's separate from the [alert emails](alerts.md#alert-emails). Those list what changed. This one is the numbers, whether anything changed or not.

## Turn it on

1. On Settings, Features, click "Turn on" beside Email reports. If the row says Not installed, it shows the commands that add the table. See [Settings, Features](configuration.md#settings-features).
2. On Settings, Emails, under Traffic emails, tick how often under "How often" and list the addresses under "Send to", one per line or separated by commas.

It also needs:

- The embedded scheduler enabled, or `AhoyDashboard::TickJob` scheduled. See [Schedule the tick](background-jobs.md#schedule-the-tick).
- A `host` in your mailer's `default_url_options`. Every link in the email is a full URL, so without a host every email fails.

| On Settings, Emails | Default | Does |
|---|---|---|
| How often | None | Which emails to send: any of daily, weekly and monthly. Pick none to send nothing. |
| Send to | Nobody | Who gets them |
| Send from | Blank | The From address. Blank uses the parent mailer's default. |

Two more settings stay in the initializer, because they name classes in your code:

| In the initializer | Default | Does |
|---|---|---|
| `reports[:mailer]` | `"AhoyDashboard::ReportMailer"` | The mailer class, as a string. Point it at a subclass to change the email. |
| `reports[:parent_mailer]` | `"ActionMailer::Base"` | What the email's mailer inherits from, as a string |

Every recipient is on one email, together in the To line. The list is the addresses typed on the screen. There's no way to work it out in code.

## What's in it

- A subject with the period and the visitor count: `Traffic for Sep 18: 1,204 visitors` for a day, `Traffic for Sep 8 to Sep 14: ...` for a week, `Traffic for August: ...` for a month.
- [Visitors](metrics-and-dimensions.md#unique-visitors), visits, pageviews and bounce rate for the period, each with its change against the period before it.
- The top 5 pages, the top 5 sources and the top 5 countries, by visitors.

Crawlers are left out, and no filter or segment applies. Every figure links to the dashboard on the same dates, so the numbers in the email are the ones you land on.

## When it's sent

| Email | Covers | Arrives |
|---|---|---|
| Daily | Yesterday | Every morning |
| Weekly | Monday to Sunday | Monday morning |
| Monthly | The calendar month | The morning of the 1st |

The first tick after 7:00 AM in the time zone on Settings, General sends it, and periods are cut in that zone too. A Monday that's also the 1st sends every one you've set up.

It's sent by `AhoyDashboard::Reports::DigestJob`, listed as "Traffic emails" on Settings, Jobs. See [Background jobs](background-jobs.md).

### Each email is sent once

Each period is sent once, however many times the job runs. If sending fails, "Traffic emails" shows as Failed on Settings, Jobs, and the email is tried again the next time the job runs while that period is still the latest one. For a weekly email that's all week. For a daily one it's only the rest of that day.

The "A job failed" [alert rule](alerts.md#job-rules) can tell you when that happens.

## The sender

"Send from" on Settings, Emails sets the From address. Leave it blank and the email uses the default of the mailer it inherits from, which is `ActionMailer::Base` unless you set `reports[:parent_mailer]` in the initializer. Point that at your own `ApplicationMailer` to pick up your From address and delivery settings:

```ruby
config.reports[:parent_mailer] = "ApplicationMailer"
```

## When no email arrives

| Check | Where |
|---|---|
| Email reports are installed and on | Settings, Features |
| At least one period is ticked under Traffic emails | Settings, Emails |
| At least one address is under "Send to" | Settings, Emails |
| Your mailer's `default_url_options` has a `host` | Your app's mail config |
| The tick is scheduled and "Traffic emails" is running | Settings, Jobs |
| The period has ended | A weekly email covers a finished Monday to Sunday, so the first one arrives the Monday after you turn it on |

Related: [Alerts](alerts.md), [Configuration](configuration.md#settings-emails), [Background jobs](background-jobs.md), [Metrics and dimensions](metrics-and-dimensions.md).
