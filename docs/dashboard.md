# Dashboard

The dashboard is the page at the engine's mount point. It shows one site's traffic over a date range: seven headline numbers, a chart of whichever one you pick, and a grid of cards that break the traffic down by source, page, location and device.

Paths on this page are relative to the mount point. If you mounted the engine at `/analytics-dashboard`, the realtime page is `/analytics-dashboard/realtime`.

Everything on the page lives in the URL. Copy the address bar and you've copied the view, filters and all.

Headline numbers, charts, pinned-question readings, breakdowns, page journeys, goal conversions and filter options reuse numerical query results for up to 30 seconds through the host application's Rails cache. Changing a range, filter, metric, time zone or site host reads a separate result. Labels and settings are read on each request. Unbounded report and goal exports read current data. The realtime count keeps its own refresh schedule.

Comparisons for a named range still in progress advance their matching cutoff every 30 seconds. Completed periods and explicit custom ranges keep their exact boundaries.

Under Settings, General, check **Precompute default dashboard** and save to queue the first [dashboard snapshot](configuration.md#precomputed-default-dashboard). This starts off and applies to Last 30 days with Visitors, daily grouping, no filters and no comparison. The page then shows "Snapshot updated" with its preparation time in the dashboard's time zone. The host's minute tick keeps an enabled snapshot prepared while idle. After 30 seconds, a visit can also queue a refresh while using the existing snapshot; numerical results can be up to five minutes old. Realtime activity remains separate. Changing the range, metric or filters uses ordinary queries. With no usable snapshot, each requested panel runs its own ordinary query and queues a background rebuild; the initial page never waits for that rebuild. Cold panels can still take longer after cache eviction, date or definition changes, or delayed workers. Uncheck the setting and save to return to ordinary queries.

## Header

The header is the same on every page.

- The site name goes back to the dashboard with nothing in the URL, which lands on your [remembered view](#remembered-view). The name is the site host from Settings, General, or the request's host when that isn't set.
- "Dashboard", "Explore" and "SEO" carry the current date range and filters with them.
- "Search" opens the [command palette](#command-palette).
- "N live" is the [realtime](#realtime) count. It refreshes every 15 seconds.
- The date range menu shows on the dashboard only.
- "Ask" opens the [assistant](assistant.md).
- The gear opens Settings, starting on Goals.

## Date range

Pick the range from the calendar menu in the header. Ranges are worked out in the time zone on Settings, General (UTC unless you pick another), and every rolling range runs to the end of today, so "Last 7 days" includes the part of today that hasn't happened yet.

| Menu label | `period=` | Covers | Default grouping | Allowed groupings |
|---|---|---|---|---|
| Realtime | `realtime` | The last 30 minutes | Minute | Minute |
| Today | `day` | Today | Hour | Hour |
| Yesterday | `yesterday` | Yesterday | Hour | Hour |
| Last 7 days | `7d` | Today and the 6 days before it | Day | Hour, Day |
| Last 30 days | `30d` | Today and the 29 days before it | Day | Day, Week |
| Month to date | `month` | The 1st of this month through today | Day | Day, Week |
| Last month | `last_month` | The whole previous calendar month | Day | Day, Week |
| Last 6 months | `6mo` | This month so far and the 5 whole months before it | Month | Week, Month |
| Last 12 months | `12mo` | This month so far and the 11 whole months before it | Month | Week, Month |
| Year to date | `year` | January 1 through today | Month | Week, Month |
| All time | `all` | The day of the first recorded visit through today | Month | Day, Week, Month |
| Custom range | `custom` | `from` through `to` | The finest that fits | See [Custom range](#custom-range) |

"Last 30 days" is the default, and an unknown `period` gets you the default.

The "Realtime" range is the dashboard over the last 30 minutes in one-minute points. It is a different thing from the [realtime page](#realtime), which looks at the last 5 minutes.

### Custom range

Pick "Custom range" and a From and To card opens under the toolbar. Each end has a date and a time. The time is optional: leave From's time blank to start at midnight, and leave To's blank to run to the end of that day. Apply it to reload the dashboard. The x on the card goes back to the last 30 days.

In the URL, `from` and `to` each take a date (`2026-08-01`) or a local time (`2026-08-01T09:30`), and you can mix the two. A date covers the whole day. A time on `to` is exclusive: `to=2026-08-01T17:00` stops at 16:59:59. Times are read in the time zone on Settings, General. The card sends the time separately as `from_time` and `to_time` (`09:30`), and the dashboard folds each one into its date, so the address you end up on only has `from` and `to`. A time that isn't `HH:MM` is ignored and that end covers the whole day.

A range that doesn't parse, or that runs backwards, shows the last 30 days while the menu still says "Custom range". Nothing tells you it fell back, so if the numbers look like the default range, check the dates.

### Grouping

The chart draws one point per minute, 5 minutes, 15 minutes, hour, day, week or month. Change it from "Group by" in the [command palette](#command-palette), or with `interval=` in the URL: `minute`, `five_minutes`, `fifteen_minutes`, `hour`, `day`, `week` or `month`. There's no button for it in the toolbar.

- A grouping the range doesn't allow falls back to the range's default.
- On a custom range, a grouping is allowed when it's no longer than the range and the range needs 400 points or fewer. The default is the finest one allowed. One custom day allows 5 minutes, 15 minutes, Hour and Day, and defaults to 5 minutes.
- The 400-point cap only applies to custom ranges. "All time" grouped by day over three years draws over a thousand points.
- Weeks start on Sunday.
- Points follow the calendar, so a daylight saving day is 23 or 25 hours long and still one point.

## Comparison

The "Previous period" switch at the right of the metric tiles compares the range with the one before it:

| `comparison=` | Compares with |
|---|---|
| `previous_period` | The same length of time immediately before the range |
| `year_over_year` | The same dates one year earlier |

The switch only turns on `previous_period`. Year over year is in the command palette under "Compare to", or in the URL.

Previous period shifts the whole range back by its own length. Today compares with all of yesterday. Last 30 days compares with the 30 days before it. Month to date on September 19 compares September 1 to 19 with August 13 to 31, the 19 days right before it, and not with August 1 to 19.

Since rolling ranges run to the end of today, the part of today that has happened is compared with a whole day. The tiles read low until the day is over, which looks like a bad morning every morning.

The comparison uses the same filters and crawler setting as the range. Realtime has no comparison; the switch shows but nothing is compared.

## Metric tiles

The row of seven tiles above the chart holds the headline numbers for the range: Unique visitors, Total visits, Total pageviews, Views per visit, Bounce rate, Visit duration and Scroll depth. [Metrics and dimensions](metrics-and-dimensions.md) says how each one is counted.

- Click a tile to chart it. With JavaScript on, the chart redraws in place and the URL updates. The URL key is `metric=`, and the default is `visitors`.
- Tiles show short numbers (`12.3k`). Hover for the exact one.
- With a comparison on, each tile gets a change pill: the change as a whole percent, or "New" when the previous period was zero. No pill when both periods are zero.
- Green means better. That's up for everything except Bounce rate, where down is green.

The change is `(current - previous) / previous * 100`, rounded to a whole number.

## Chart

The chart plots the chosen metric with one point for every step of the grouping, and a step with no traffic is a zero rather than a gap.

- The y axis starts at 0. Bounce rate and Scroll depth always top out at 100.
- When the range includes right now, the last point is drawn as an open line and its tooltip says "Unique visitors so far" (or whichever metric it is), because that bucket isn't finished.
- Grouped by day, Saturdays and Sundays get a lighter band.
- With a comparison on, the previous period is a dashed line behind the main one. It's lined up by position, not by date: the first point of the previous period sits under the first point of this one. When the two periods have a different number of points, the dashed line isn't drawn, and the tiles still show the change.
- Hover a point for its date, value, and with a comparison on, the previous value and the change.
- The download icon saves the chart as a CSV. See [Exports](#exports).

The chart is drawn in the browser. With JavaScript off, the space is empty.

### Drag to zoom

Drag across the chart to zoom into that stretch. Let go and the dashboard reloads on a custom range covering the points you selected. The grouping goes back to the default for the new span; the metric, comparison, filters and crawler setting stay.

- Day, week and month points give a range of dates. A week runs to its Saturday and a month to its last day, clipped to the range you were looking at.
- Hour and finer points give a range of times.
- Press Esc to cancel. Selecting the whole chart does nothing.
- It works on every range longer than a minute, Today and Realtime included.
- It needs a mouse or other pointer, and it's on the dashboard chart only.

### Annotations

An annotation is a flag on the chart for something that happened at a moment: a deploy, a campaign, a note. They change no numbers. They're there so that three weeks from now you know why Tuesday looks weird.

Add them under Settings, Annotations, "New annotation":

| Field | Notes |
|---|---|
| What happened | Required. Up to 120 characters. |
| When | A date and time in the dashboard's time zone. Defaults to now. |
| Type | Deploy, Campaign or Note. Anything else saves as Note. |

On the chart:

- Only annotations inside the range show. Filters don't hide them.
- A flag sits on the point that holds its moment, so a Tuesday deploy on a weekly chart sits on that week.
- Deploy flags are blue, Campaign green, Note grey. Hover or tab to a flag to read its type, label and time.
- At most 2 flags per point, whatever the chart's grouped by: 2 a day on a daily chart, 2 a week on a weekly chart, 2 a month on a monthly chart, and so on down to the finest grouping. The earliest two stay and the rest aren't drawn.
- Explore's chart shows them too.

The settings list is newest first, and each row has edit and delete.

## Report cards

The cards under the chart break the range down one dimension at a time.

| Card | Tabs | Break down by |
|---|---|---|
| Top sources | Channels, Sources, UTM medium, UTM source, UTM campaign, UTM term, UTM content, Referrers | |
| Top pages | Top pages, Entry pages, Exit pages | Top pages: Path, Grouped, Rails controller. Entry pages: Path, URL, Hostname. |
| Locations | Countries, Regions, Cities | |
| Devices | Browser, OS, Size | |

A card with more than four tabs shows the first two and puts the rest under "More", which is why Top sources shows Channels and Sources.

Each card lists the top 9 rows by unique visitors, and that's the only number on a card. [Metrics and dimensions](metrics-and-dimensions.md) says where every tab's values come from.

- The bar behind a row is its share of the top row, so the top row is always full.
- Hover a row for its percentage: the row's unique visitors out of all unique visitors in the range. On Top pages the percentages add up to more than 100%, because one visitor sees more than one page.
- Click a row to filter the whole dashboard by it (`Country is US`). It replaces any "is" filter already on that dimension. See [Filters and segments](filters-and-segments.md).
- Some cards move to the next tab after you drill in. Filter by a country and Locations opens on Regions; by a region and it opens on Cities. Filter by a channel and Top sources opens on Sources; by a source and it opens on Referrers.
- Empty values show as "(not set)". Clicking that row filters on the empty value.
- Countries show by name with a flag. Source and Referrer rows get the site's icon (see [Site icons](#site-icons)).
- The Size tab is ahoy's `device_type`, read from the user agent. Nobody measured a screen.
- The tab and breakdown you pick belong to that card and aren't in the URL. Reloading puts every card back on its first tab.

Also on the page, each with its own doc:

- Pinned questions, between the chart and the cards: [Explore](explore.md#pinned-questions).
- The Google search card: [Search Console](search-console.md).
- Cards for the first four configured funnels, with **View all funnels** opening the complete list: [Goals and funnels](goals-and-funnels.md#funnels).
- Page journey, under the cards: [Page journey](page-journey.md).
- Goal conversions, at the bottom: [Goals and funnels](goals-and-funnels.md#goal-conversions).

## Details

"Show all" at the bottom of a card opens its details: the full list for that tab, 100 rows at a time.

- Every tab is along the top, including the ones under "More", along with the breakdown picker.
- Each row shows its percentage and the tab's first number. The rest of the tab's columns (bounce rate, visit duration, scroll depth, time on page) are in the CSV and in Explore, not on this list.
- Type in the search box and press Enter to find rows. It's a case-insensitive substring match over the whole range, not only the rows on screen. `%` and `_` are plain characters.
- The footer says where you are ("Top 100", "Rows 101 to 200", "36 values") and has "Previous", "Next", "Open in Explore" and "CSV".
- "Open in Explore" opens the same range and filters in [Explore](explore.md), broken down by this tab with all of its columns.
- "CSV" downloads this tab and breakdown for the range. It ignores the search box.

Keyboard: `/` jumps to the search box, the arrow keys move a highlight through the rows, Enter filters by the highlighted row, and Esc closes.

## Realtime

The "N live" count in the header is the number of unique visitors with any event in the last 5 minutes. It ignores the date range, the filters and the crawler setting, and it never counts crawlers.

Click it for `/realtime`, which shows the same count as "N visitors in the last 5 minutes" and two lists:

- Pages: where each of those visitors is now, by their latest page view.
- Sources: where each of them came from.

Each list shows the top 8 and is not clickable. The page reloads itself every 15 seconds, and with JavaScript on there's a "Pause refreshing" button.

The lists only count people with a page view in the window, while the count takes any event. So the lists can add up to fewer people than the count, and you can see "No one is on the site right now" under a count of 2.

The window is 5 minutes and isn't configurable.

## Remembered view

The dashboard remembers how you last looked at it. Leave it on "Last 7 days, Total pageviews" and that's what you get next time you open it with a bare URL.

It's a cookie called `dash_view`, and it holds the date range, grouping, metric, comparison, crawler setting and custom dates. It never holds filters, because a filter left on quietly changes every number on the page.

- Only a full load of the dashboard page writes it. Explore, Settings and the SEO pages read it and never write it.
- It lasts 90 days from the last write.
- A URL with any of `period`, `interval`, `metric`, `comparison`, `crawlers`, `from`, `to` or `filters` ignores the cookie completely. The two aren't merged.
- A view back at the defaults deletes the cookie instead of saving it. So following a link that names only a filter shows the last 30 days and forgets what you had.
- The Realtime range isn't remembered. The view before it stays.
- Clicking a metric tile with JavaScript on doesn't save until the next full page load.
- When you're looking at a remembered view, "Reset view" shows in the toolbar. It deletes the cookie and goes back to the last 30 days with no filters.

The cookie is plain text, `HttpOnly`, `SameSite=Lax`, and read as untrusted input. A mangled one gets you the defaults.

## Crawlers

Events that carry a `crawler` property are left out of every number by default, and so is any visit that has no other events. Turn them back on with "Show crawlers" in the command palette, or `crawlers=1` in the URL.

The dashboard doesn't detect bots. Your app decides what's a crawler when it records the event. See [Tracking](tracking.md#crawlers).

## Exports

### Report CSV

The "CSV" button in a card's details downloads that tab for the range, with the current filters. The command palette's Export group has "Top sources as CSV" and the rest, one per card. Those always export the card's first tab.

The address is `/exports/<key>` with the same query string as the dashboard, plus `tab`, `breakdown` and `property`:

| Key | Tabs (`tab=`) | Breakdowns (`breakdown=`) |
|---|---|---|
| `sources` | `channels`, `sources`, `utm_medium`, `utm_source`, `utm_campaign`, `utm_term`, `utm_content`, `referrers` | |
| `pages` | `pages`, `entry_pages`, `exit_pages` | `pages`: `path`, `grouped`, `controller`. `entry_pages`: `path`, `url`, `host`. |
| `locations` | `countries`, `regions`, `cities` | |
| `devices` | `browser`, `os`, `size` | |
| `behaviours` | `goals`, `properties` | |

A bad tab or breakdown falls back to the default rather than failing.

- The file is `ahoy-dashboard-<key>-<YYYY-MM-DD>.csv`, dated today in the dashboard's time zone.
- The first row is the headings: the tab's label column, then its columns, like `Page url,Unique visitors,Total pageviews,Bounce rate,Scroll depth,Time on page`.
- Every row in the range, with no limit, streamed as it's read.
- Labels are what the card shows: country names, "(not set)", any [value labels](extending.md#value-labels) you registered.
- Numbers are raw. Counts are integers, bounce rate and conversion rate are percentages to one decimal, visit duration and time on page are whole seconds, scroll depth has one decimal, and revenue has two.

The values come straight from your visitors. A path or UTM tag that starts with `=`, `+`, `-` or `@` goes into the file as is, and a spreadsheet may run it as a formula.

### Chart CSV

The download icon next to the comparison switch saves the chart as it's drawn. It's built in the browser, so it needs JavaScript.

- The file is `ahoy-dashboard-<metric>-<grouping>.csv`, like `ahoy-dashboard-unique-visitors-day.csv`.
- Columns are `date` and the metric (`unique_visitors`), plus `previous` when a comparison is drawn.
- `date` is the bucket's start as an ISO timestamp with the dashboard's UTC offset. Values are rounded to 2 decimals.

## Command palette

Cmd+K or Ctrl+K opens the command palette on any page, and so does "Search" in the header. Type to narrow the list, use the arrow keys, and press Enter.

The command list loads when you first open the palette. With JavaScript off, or when opening Search in a new tab, the link opens a page containing the same commands.

| Group | What's in it |
|---|---|
| Go to | Dashboard, Realtime, Explore, SEO, Ask |
| Settings | Every settings screen |
| Metrics | The seven metrics |
| Date range | Every range except Custom range |
| SEO | Every SEO page |
| Group by | The groupings the range allows (dashboard only) |
| Compare to | No comparison, Previous period, Year over year (dashboard only) |
| Export | One "as CSV" entry per card |
| Actions | Clear all filters, Compare to the previous period or Stop comparing, Show crawlers or Hide crawlers |

It's the only control for grouping, year over year and crawlers. Searching the command list needs JavaScript; the standalone page's links work without it. Metric, date range and action entries always land on the dashboard, even when you open the palette from Explore.

Type 2 or more characters and it also searches the values in your traffic, up to 5 per dimension, under "Filter by" headings. Picking one filters the dashboard by it. See [Value search](filters-and-segments.md#value-search).

## Keyboard shortcuts

| Keys | Where | Does |
|---|---|---|
| Cmd+K, Ctrl+K | Anywhere | Opens or closes the command palette, even while typing |
| `/` | Dashboard and Explore, outside a text box | Opens the filter dialog |
| `/` | Inside a dialog | Jumps to the dialog's search box |
| Up, Down | Menus, dialogs, the palette | Moves the highlight |
| Home, End | Menus and card tabs | First or last item |
| Left, Right | Card tabs | Previous or next tab |
| Enter | Dialogs, the palette | Opens the highlighted row, or ticks it in the filter dialog |
| Cmd+Enter, Ctrl+Enter | The filter dialog | Applies the filters |
| Backspace | The filter dialog, in an empty search box | Takes off the last value or filter |
| Esc | Anywhere | Closes the menu or dialog, or cancels a chart drag |

## Site icons

Source and Referrer rows show each site's icon. A background job fetches it from DuckDuckGo's icon service and serves it from `/favicons/<domain>`, so the browser looking at the dashboard never talks to anybody else. Until the icon is cached, the row keeps its letter and the request returns immediately.

- Only domains that have referred a visit get an icon. Anything else is a 404 and fetches nothing.
- An icon is cached for 30 days, a domain with no icon for a day, and a failed fetch for 10 minutes.
- A brand new referring domain waits up to an hour for its icon, because the list of known domains is cached that long.
- A site with more than 2,000 referring domains gets icons for 2,000 of them, picked in no particular order.
- Rows without an icon show the domain's first letter.
- Warming requires a cache and a background queue. With no cache or an inline job adapter, rows keep their letters without making external requests.

It's on by default. To turn it off, click Turn off next to Site icons under Settings, Features.

[Security and privacy](security-and-privacy.md#site-icons) covers what DuckDuckGo learns.

## Without JavaScript

The initial page contains navigation, filters, date controls and fixed-size placeholders. Headline statistics and the chart load first. Visible panels then load independently, with at most two automatic frame requests at once; offscreen panels wait until they approach the viewport. Related headline statistics share one request, and page reports and journey counts share their analytical cache. A failed panel offers its own retry without discarding the rest of the page.

With JavaScript off, follow **Load the complete dashboard** to request `?loading=complete`. That response includes report cards, Google search data, funnels, pinned questions, page journey and goal conversions. Its complete rendering can take longer; it uses the existing synchronous snapshot fallback when necessary.

Unopened search and filter dialogs load their contents when opened. The Search and Filter links also open standalone pages without JavaScript. Settings forms keep their filter dialog ready so unsaved filter selections stay in the form.

Works: the date range menu, the custom range card, removing filters and "Clear filters", "Reset view", clicking a metric tile, and the comparison switch.

The chart and its CSV, drag to zoom, detail dialogs, command search, independent card updates and realtime refresh need JavaScript.

Related: [Metrics and dimensions](metrics-and-dimensions.md), [Filters and segments](filters-and-segments.md), [Explore](explore.md), [Email reports](email-reports.md).
