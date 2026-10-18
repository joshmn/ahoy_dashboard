# Search Console

Google stopped passing search terms to the sites people land on years ago, so ahoy sees a visit from google.com and nothing about what was searched. Search Console has that part. Connect it and the dashboard pulls your queries, pages, clicks, impressions, click-through rate and average position every night, and stores them in your database.

Optional. It's off until you turn it on, and the rest of the dashboard works without it. It needs a Google account with access to the property and a Google Cloud OAuth client.

Stored means they're yours. Google only keeps 16 months, and the dashboard keeps everything it has pulled, including after you disconnect.

## Before you start

- The site is verified in Search Console, under a Google account you can sign in with.
- The site host is set to your real domain on [Settings, General](configuration.md#settings-general), or a redirect URL override is saved on Settings, Search Console. Without either, the settings screen still loads, but there's no redirect URI to register with Google yet, and "Connect Google account" stays disabled until you set one.
- `AhoyDashboard::TickJob` is scheduled. See [Background jobs](background-jobs.md).

## Turn it on

Install its tables first if you left it out at install time:

```sh
bin/rails generate ahoy_dashboard:install --only search_console
bin/rails db:migrate
```

Until then, Settings, Search Console and the Search Console pages under SEO show "Not installed yet" with those two commands. See [Adding a feature later](installation.md#adding-a-feature-later).

Then click "Turn on" next to Search Console on [Settings, Features](configuration.md#settings-features). Until the client ID, the secret, a Google account and a property are all in place, it shows as Needs setup there, with the first missing piece and a "Set it up" button that goes to it.

The Google OAuth client ID and secret are only entered on Settings, Search Console. The initializer and environment variables aren't read for them.

## Create the Google OAuth client

This is a one-time job in Google Cloud, in the Google account that owns the Search Console property. Settings, Search Console has the same steps under "Setting it up in Google Cloud", with your exact redirect URI filled in.

1. At [console.cloud.google.com](https://console.cloud.google.com), create a project and turn on the Google Search Console API.
2. Set up the OAuth consent screen. Choose External, then set the publishing status to In production. Leave it on Testing and Google ends the connection every 7 days. An app with under 100 users needs no review, and you'll click past one unverified-app warning when you connect.
3. Create an OAuth client. Choose Web application and add your redirect URI under Authorized redirect URIs.
4. Copy the client ID and secret into the OAuth client card on Settings, Search Console and click "Save credentials".

A "Remove" button sits beside the client ID and beside the client secret. It asks first and names what stops working: syncing, when Google is connected, or connecting, when it isn't. Removing clears the stored value and the field then reads "Nothing stored." The Google connection stays until you disconnect.

### The redirect URI

It's the first of these that's set:

1. The Redirect URL override on Settings, Search Console, as is
2. `https://<canonical host><mount path>/settings/google_callback`, with the canonical host from Settings, General
3. `https://<site host><mount path>/settings/google_callback`, with the site host from Settings, General

So with the site host set to `example.com` and the default mount, it's `https://example.com/analytics-dashboard/settings/google_callback`. The Redirect URL card says which one is in use, for example "from the host under Settings, General".

Google compares it character for character: scheme, host, path and any trailing slash. A mismatch is the most common way this setup fails, and Google's `redirect_uri_mismatch` page is all you'll see. If the address you're browsing from differs from the one the dashboard sends, the settings screen says so above the steps.

The built URIs are always `https`. For local development, where there's no TLS, type it into Redirect URL override yourself and click "Save redirect URL". Google only allows plain `http` on `localhost`:

```
http://localhost:3000/analytics-dashboard/settings/google_callback
```

The override has to be a full web address with a host. Empty the box and save to go back to building it from the host.

Then connect from `http://localhost:3000`, not another hostname that points at the same app. The callback has to land in the browser session that started it.

If the site answers on more than one name, set the canonical host on Settings, General to the one registered with Google.

## Connect

1. Open Settings, Search Console.
2. Click "Connect Google account" and sign in with the account that owns the property. The only permission asked for is `https://www.googleapis.com/auth/webmasters.readonly`, which is read only.
3. Back on the dashboard, pick a property.

The first sync starts on the next tick. The nightly job brings back the last week, and the history job starts walking back through the rest within the hour. See [What gets pulled](#what-gets-pulled).

If connecting fails, the settings screen says why:

| Message | Means |
|---|---|
| "You turned the request down, so nothing changed." | Cancel or Deny was clicked on Google's screen |
| "That did not come back from a sign-in this browser started." | The callback landed in a different browser, a different hostname, or a signed-out session. Start again from the same address you'll finish on. |
| "Google turned the sign-in down." followed by `google returned no refresh token` | Google didn't hand back the token the nightly job needs. Try again. |
| "Google turned the sign-in down." followed by `invalid_grant` | The code expired or was already used. Try again. |
| "Google did not finish the sign-in." | A timeout or network error talking to Google |
| "Add the OAuth client ID and secret first." | No client ID or secret is saved on Settings, Search Console. |
| "Search Console is off. Turn it on under Settings, Features." | The client is saved but Search Console is switched off. |

## Pick a property

The list comes from Google, live, with every property the account can read except unverified ones. Domain properties come first and show as `example.com (domain)`.

A domain property covers every subdomain and both `http` and `https`. A URL-prefix property covers only what starts with that URL. Pick the one that matches how the site is verified.

The picker doesn't check that the property matches the site host, so it's on you to pick the right one. Switching to a different property deletes every row already stored for the old one and starts history over for the new one; the form warns first, naming how many days that would remove.

## What gets pulled

Google's days run on Pacific time, so every date here is a Pacific date.

Every night at 4:00 AM Pacific, the dashboard reads the last 7 finished days. A day counts as finished 3 days after it ends, because Google keeps changing the numbers until then. It reads all 7 every night, even the ones it already has, because Google keeps revising them.

Every hour, a second job reaches 30 days further back, until it has all 16 months Google keeps. A fresh connection has its full history in under a day. After that the hourly job has nothing to do.

Each day is pulled three ways, stored in three tables, with device and country riding along on each. See [Device and country](#device-and-country).

| Pulled by | Stored in | Answers |
|---|---|---|
| Nothing (the whole day) | `ahoy_dashboard_search_console_totals` | The day's real total clicks, impressions, CTR and position |
| Query | `ahoy_dashboard_search_console_keywords` | How one query did over time |
| Query and page | `ahoy_dashboard_search_console_rows` | Which pages each query landed on |

The three don't add up to each other, and they're not supposed to. See [Why the numbers don't add up](#why-the-numbers-dont-add-up).

Only web search is pulled. Image, video, News and Discover aren't, and there's no search appearance breakdown.

A query and page longer than 2,500 bytes combined is dropped, with a line in the log. Postgres can't index a key that long, and cutting it short would file real clicks under a query nobody searched.

## Device and country

The nightly sync pulls device (Desktop, Mobile, Tablet) and country alongside query and page, and stores them at all three grains: totals, keywords and rows.

A "Device" menu (All devices, Desktop, Mobile, Tablet) and a "Country" menu (All countries, then every country with rows in the range) sit on Performance and One query, and on four [SEO reports](seo-reports.md): Opportunities, Cannibalization, Brand vs. non-brand and Search to conversion.

Rows pulled before the dashboard started pulling device and country have neither. They count under "All" and read as "Unknown", and picking a device or a country leaves them out.

Google hides more queries the finer you cut, so a query's clicks split by device and country can add up to less than its total.

The Google search card on the dashboard stays whole-site. There's no device or country menu there.

## Where it shows

### The Google search card

On the dashboard, under the other cards. Queries and Pages tabs, 9 rows each, ranked by clicks. "Show all queries" opens up to 100.

The card reads stored Search Console data from the background sync. Loading the dashboard never requests data from Google. It shows the latest stored date when the selected range extends beyond the available data.

Dashboard filters don't apply. Search Console data can't be tied to a visit, so a filter has nothing to narrow, and the card says "Filters do not reach search data, so this is the whole site." Comparison doesn't apply either.

Click a query to open its history. Page rows aren't links.

The nine rows here have no checkboxes. Open "Show all queries" to tick some and [track them](#track-queries).

### SEO, Performance

The full report. Four tiles (Clicks, Impressions, CTR, Avg position), a daily chart of whichever one you pick, and a table of queries or pages below it.

- Each tile compares against the same number of days just before the range.
- The Queries tab has a 28-day trend line of clicks for each query. Click one for its landing pages.
- The Pages tab links each page to the dashboard, filtered to that path.
- A "Device" menu and a "Country" menu narrow the tiles, the chart and both tables. See [Device and country](#device-and-country).
- "Filter the rows" matches any part of a query or page, across the whole range, not only the rows showing.
- "Sync now" pulls the last week again.
- A "CSV" button above each table exports what's showing, as `ahoy-dashboard-seo-performance-queries-<date>.csv` or `ahoy-dashboard-seo-performance-pages-<date>.csv`. See [SEO reports](seo-reports.md#csv) for what an export contains.

It only reads stored days, so it always ends 3 days ago.

### One query

`/search_console_keyword?q=<query>` shows one query over time: clicks, impressions, CTR and position by day, every day Google reported it, and the pages it landed on. Get there from a query on the card, on stored rows, or on a tracked keyword's "See clicks". On Performance, a query opens a short version of it in a dialog. "Track keyword" adds the query to [rank tracking](rank-tracking.md).

A "Device" menu and a "Country" menu narrow the chart and the tables to one device or one country. See [Device and country](#device-and-country).

The chart only covers days the dashboard has pulled at the query level, and says so when that's shorter than the range you asked for. A day Google didn't mention the query shows as a gap, since Google leaves out queries with too few impressions to report.

Changes here are in the units that make sense: a percent for clicks and impressions, points for CTR, places for position. The comparison only shows when the whole earlier period was pulled.

### Stored rows

Settings, Search Console, "View rows" lists every row pulled, one query on one page per day, 100 to a page. Sort by clicks, impressions, date or position, and search by any part of a query or URL.

Every row has a checkbox, so you can [track](#track-queries) a search straight off this screen. A query shows up once for every day and page it landed on, and ticking it more than once still tracks it once.

The "By day" table above it is the useful part: each day's clicks from named rows next to Google's real total for that day, and the share that got a name.

### Elsewhere

- The [SEO reports](seo-reports.md) build on these rows, like page 2 opportunities and search to conversion.
- The [assistant](assistant.md) can read queries and one query's history.

## Track queries

Tick the searches you want, click "Track these", and they all go into [rank tracking](rank-tracking.md) in one go.

Six screens carry the checkboxes: the Queries tab on Performance, "Show all queries" off the Google search card, "View rows" in settings, and three [SEO reports](seo-reports.md), Opportunities, Cannibalization and Brand vs. non-brand. Every one of them has a box that ticks the whole list at once.

The nine rows on the card itself don't have them. That card is a glance, and the button under it opens the same queries with the boxes on.

"Track these" opens the same form as [Import a list](rank-tracking.md#import-a-list): places, device, language, how often, how deep, sites and [tags](rank-tracking.md#tags), set once for the whole batch, with a line "About N units a month" above the "Track N searches" button. Saving lands you back on the screen you started from.

A query you already track can't be picked again. In a table it reads "Tracked". In the list behind the card it's a tick, since a word there would be wider than the numbers beside it. Either one opens the keyword.

Pages tabs have no checkboxes. Only a search can be tracked, and the anonymized row is not a search.

## Why the numbers don't add up

Search Console numbers never line up perfectly, even inside Google's own interface. Here's why:

- **Google hides some queries.** Rare ones, and anything that looks personal. Their clicks count in the day's total and belong to no query. Open "Show all queries" on the card to see what share of clicks got a name.
- **Google cuts the list off.** It serves at most 50,000 rows a day, ranked by clicks, and drops the rest. The dashboard asks for one day at a time so the cap bites as little as possible. On a big site it still bites.
- **Query and page hides more than query alone.** So a query's clicks by page add up to less than its clicks.
- **The card and the Performance page can cover different days.** Both rank queries from the query table and pages from query-and-page rows. The card adds unfinished days and Performance stops at finished days, so the same query can show different numbers on each.
- **Search Console isn't ahoy.** Google counts clicks from its results. ahoy counts visits that ran your tracking. They measure different things, and the dashboard never joins them row by row.

The totals are right. The lists underneath them are always short.

## Metrics

| Metric | Is |
|---|---|
| Clicks | Clicks from Google's results to your site |
| Impressions | Times your site showed in the results |
| CTR | Clicks divided by impressions, worked out again for every total rather than averaged |
| Position | Average position, weighted by impressions. Lower is better. |

Position is an average of where you showed up, not a rank. A page at 1 for one search and 20 for another averages 10.5, and was never 10.5 anywhere. For a real rank on a real search, use [rank tracking](rank-tracking.md).

Every change in position is shown the right way around: a fall is good, and is green.

## Sync now and history

Everything runs on its own once the tick is scheduled. To start something sooner:

- "Sync now", on Settings, Search Console or SEO, Performance, reads the last week again.
- "Reach back a month", in the More menu on Settings, Search Console, pulls 30 more days of history.

Both are disabled with the reason when Search Console is off, has no credentials, isn't connected, or has no property picked yet.

The footer of the Stored data card says how far back the history goes: complete, a number of days short, or not started.

`bin/rails ahoy_dashboard:search_console` prints the whole setup, connection and history from the command line. See [Background jobs](background-jobs.md#rake-tasks).

## Fill missing days

Settings, Search Console has a "Missing days" section listing the gaps in the stored history, like "Jun 3 to Jun 19, 17 days".

"Fill these days" enqueues `AhoyDashboard::SearchConsole::FillJob` on `low`. It pulls each missing day the same way the nightly job does, one day at a time, oldest first, staying inside Google's quota. Settings, Jobs shows it as "Search Console, filling gaps" with how many days are left.

Days older than 16 months are listed as "Gone". Google no longer serves them, and nothing can fill them. The newest 3 days aren't listed either, because they haven't finished yet.

## Disconnect

More, then "Disconnect", on Settings, Search Console. The dashboard asks Google to revoke the token and forgets it, even when Google doesn't answer.

Kept: every row already pulled, and the OAuth client ID and secret.

Lost: the token, the property, and how far the history got. Reconnect and you pick the property again, and the history picks up from the oldest day stored.

## When it stops syncing

A failed sync puts a message on Settings, Search Console under "Last sync failed", a "not syncing" note on the Google search card, and a banner on the SEO pages.

| Message | Fix |
|---|---|
| "Google refused the saved refresh token. Connect the account again. If this comes back every week, the Cloud project is still in testing." | Reconnect. If it happens every 7 days, set the consent screen to In production. |
| "Google would not hand back an access token. Connect the account again." | Reconnect |
| "Google's Search Console quota is used up. The next run picks up where this one left off." | Nothing. It catches up. |
| "Search Console did not answer. Nothing was lost; the next run covers the same days." | Usually nothing. It's a passing network or server error talking to Google. |
| "This Google account can no longer read example.com in Search Console. Give it access again there, or pick another property." | Give the account access to the property again in Search Console, or pick a different property. |
| "Some days came back with rows the database would not store, and those days were skipped. Everything else in the window was saved." | Check the log for the database error |

Settings, Jobs shows a run that hit the quota as "Ran" and every other one here as "Failed", so the "A job failed" alert rule hears about them. The message on Settings, Search Console is the one that says what to do.

A gap that runs past a week doesn't close on its own: the nightly job only rereads the last 7 finished days. Use [Fill missing days](#fill-missing-days) on Settings, Search Console to pull it back in.

Related: [SEO reports](seo-reports.md), [Rank tracking](rank-tracking.md), [Configuration](configuration.md#settings-search-console), [Background jobs](background-jobs.md).
