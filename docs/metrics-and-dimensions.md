# Metrics and dimensions

This page is the reference for every number the dashboard prints and every dimension it breaks traffic down by, and for the rows of `ahoy_visits` and `ahoy_events` behind each one. When a number looks wrong, the answer is usually in here.

## What gets counted

Every number starts from the same set of visits and events.

- A visit is in the range when its `ahoy_visits.started_at` is. Its events count even when they happen after the range ends, so a visit that starts at 11:58 PM on the last day brings its whole session along.
- A visit with no counted events isn't counted at all. A visit ahoy recorded with no events behind it never shows up.
- Events with a `crawler` property are left out, and so is a visit with nothing else in it. `crawlers=1` puts them back. See [Dashboard](dashboard.md#crawlers).
- Filters narrow the set before anything is counted. A visit-level filter (country, source) picks visits. An event-level filter (page, property) picks the visits that contain a matching event. [Filters and segments](filters-and-segments.md) has the details.

A visitor is one ahoy `visitor_token`. With ahoy's defaults that's a cookie, so one person on a phone and a laptop is two visitors, and one person who clears their cookies is two visitors too.

## Metrics

| Metric | Key | Counts |
|---|---|---|
| Unique visitors | `visitors` | Distinct `visitor_token` values among the counted visits |
| Total visits | `visits` | Counted visits |
| Total pageviews | `pageviews` | `page_view` events in those visits |
| Views per visit | `views_per_visit` | Total pageviews divided by total visits |
| Bounce rate | `bounce_rate` | Visits with exactly one page view, as a share of visits with at least one |
| Visit duration | `visit_duration` | Average length of a visit |
| Scroll depth | `scroll_depth` | Average `scroll_depth` of `engagement` events |
| Total conversions | `events` | Events. On a goal breakdown, goal completions. |
| Conversion rate | `conversion_rate` | Visitors who completed a goal, as a share of all visitors |
| Time on page | `engagement_time` | Average `engagement_time` of `engagement` events |
| Revenue | `revenue_total` | Sum of the `revenue` property on a goal's events |
| Average revenue | `revenue_average` | Revenue divided by the goal's completions |

The first seven are the metric tiles, and any of them can be charted with `metric=`. The last five only show up as columns: on the goal conversions section, in details CSVs and in [Explore](explore.md). The key is what `metric=`, `columns=` and the CSVs use.

### Unique visitors

The number of distinct `visitor_token` values among the counted visits.

On the chart, each point counts the visitors whose visit started in it. Someone who comes back on Tuesday and Thursday is one visitor for the week and one on each of those two days, so the points add up to more than the tile.

### Total visits

The number of counted visits. A visit is whatever ahoy decided it was, which is a new visit after `Ahoy.visit_duration` of nothing (4 hours by default in ahoy).

### Total pageviews

The number of events named `page_view` in the counted visits. Ahoy's stock JavaScript records `$view`, which the dashboard doesn't read. [Tracking](tracking.md#page-views) explains what to send.

With a page filter on, it counts views of that page only. Every other metric counts the whole visits that saw it.

On the chart, a page view lands on the point for its own time. A page view after the end of the range, from a visit that started inside it, lands on the last point.

### Views per visit

Total pageviews divided by total visits, to 2 decimals. Zero when there are no visits. With a page filter on, it's views of that page per visit that saw it.

### Bounce rate

Visits with exactly one page view, divided by visits with at least one page view, times 100, to one decimal. The tile shows it as a whole percent, and CSVs keep the decimal.

- A visit with no page views is left out of both sides.
- Other events don't stop a bounce. A visit with one page view and a goal completion is still a bounce.
- On the chart, every point is its own ratio, never an average of averages.
- It's the one metric where down is good, and the change pills are colored that way.

### Visit duration

The average visit length in whole seconds. A visit's length is 0 when it has one counted event or none. Otherwise it's the time of its last counted event minus `ahoy_visits.started_at`.

Any event counts as the last event, including goals and the `engagement` event your app sends when someone leaves a page. That matters: with [engagement tracking](tracking.md#scroll-depth-and-time-on-page) on, a one-page visit has two events and a real length, where without it the same visit would be 0.

### Scroll depth

The average of the `scroll_depth` property on `engagement` events, as a whole percent on the tile and one decimal everywhere else.

- A value that isn't a plain number is skipped. Negative values count as 0 and anything over 100 counts as 100.
- With no `engagement` events, it reads 0% rather than blank. The dashboard can't tell "nobody scrolled" from "nothing was sent".
- With a Rails controller or Page format filter on, it reads 0 unless your `engagement` events carry `controller` and `format` too, because the filter has to match the event.
- On the chart, each point averages the engagement events sent during it.

The dashboard reads engagement events. It doesn't send them. See [Tracking](tracking.md#scroll-depth-and-time-on-page).

### Time on page

The average of the `engagement_time` property on `engagement` events, in whole seconds. Each engagement event is one page view, so this is time per page view. Values that aren't plain numbers are skipped, and there's no upper limit.

It isn't a tile and can't be charted. It's a column on the Top pages CSV and in Explore, for page and visit breakdowns.

### Total conversions

On a goal breakdown, the number of events that completed the goal. On any other breakdown in Explore, it's every event carrying that value, page views and engagement events included. The column is labeled "Total conversions" either way, so read it as "events" outside a goal breakdown.

### Conversion rate

Unique visitors who completed the goal, divided by all unique visitors in the range and filters, times 100, to one decimal. See [Goals and funnels](goals-and-funnels.md).

### Revenue and average revenue

Revenue is the sum of the `revenue` property on a goal's events, to 2 decimals. Average revenue is revenue divided by every completion, including completions with no `revenue` on them. Both only exist for goals with a currency set. See [Goals and funnels](goals-and-funnels.md#revenue).

## Number formats

| Kind | Looks like | Used by |
|---|---|---|
| Whole number | `12,345` | Visitors, visits, pageviews, conversions |
| Decimal | `1.75` | Views per visit |
| Percent | `33%` | Bounce rate, scroll depth |
| Rate | `12.5%`, `12%` | Conversion rate |
| Duration | `45s`, `3m 12s`, `1h 5m` | Visit duration, time on page |
| Currency | `$1,234.50` | Revenue, average revenue |

Tiles and cards shorten whole numbers: `999`, `1.0k`, `12.3k`, `150k`, `1.0M`. Hover a tile for the exact number. CSVs have raw numbers with no formatting at all.

## Numbers on cards

Each row on a card or in Explore counts the visits and events that carry that row's value.

- On a visit-level dimension (sources, locations, devices, entry and exit pages), a row's numbers are for the whole visits. On Entry pages and Exit pages, Total pageviews and Visit duration describe the whole visit, not that one page.
- On an event-level dimension (pages, properties, goals), Unique visitors counts visitors with any event carrying that value, and Total pageviews counts only the `page_view` events. So on Top pages, a visitor counts for a path when any of their events carries that `path` (a page view, an engagement event, a goal), while the pageviews column only counts page views.
- A number a row can't answer reads 0.
- Rows are ranked by the first column when it's a count (visitors, visits, pageviews, conversions), otherwise by visitors, with ties sorted by value.
- The percentage on a row is its first column out of all unique visitors in the range, whatever the first column is.

## Dimensions

A dimension is something traffic can be split by. The same list feeds the cards, the filters, the value search and Explore, so a filter runs the same SQL the card groups by.

| Dimension | Key | Level | Value |
|---|---|---|---|
| Page | `page` | Event | The event's `path` property |
| Page group | `page_group` | Event | The path, folded by your [page groups](filters-and-segments.md#page-groups) |
| Entry page | `entry_page` | Visit | The path of `landing_page`, without the scheme, host or query string |
| Entry URL | `entry_url` | Visit | `landing_page` as recorded |
| Entry hostname | `entry_host` | Visit | The host of `landing_page`, lowercased, without the port |
| Exit page | `exit_page` | Visit | The `path` of the visit's last `page_view` |
| Channel | `channel` | Visit | See [Channels](#channels) |
| Source | `source` | Visit | See [Source](#source) |
| Referrer URL | `referrer` | Visit | `referrer` without `http(s)://`, a leading `www.` or trailing slashes |
| UTM medium | `utm_medium` | Visit | `utm_medium` |
| UTM source | `utm_source` | Visit | `utm_source` |
| UTM campaign | `utm_campaign` | Visit | `utm_campaign` |
| UTM term | `utm_term` | Visit | `utm_term` |
| UTM content | `utm_content` | Visit | `utm_content` |
| Country | `country` | Visit | `country` |
| Region | `region` | Visit | `region` |
| City | `city` | Visit | `city` |
| Browser | `browser` | Visit | `browser` |
| OS | `os` | Visit | `os` |
| OS version | `os_version` | Visit | `os_version` |
| Device | `device` | Visit | `device_type` |
| Goal | `goal` | Event | The name of the first goal the event matches |
| Page format | `format` | Event | The event's `format` property |
| Crawler | `crawler` | Event | The event's `crawler` property |
| Rails controller | `controller` | Event | The event's `controller` property |
| A custom property | `prop:<key>` | Event | The event's `<key>` property |

Visit-level values are columns on `ahoy_visits`. Event-level values are keys in `ahoy_events.properties`.

- An empty or missing visit-level value shows as "(not set)". Event-level properties skip events without the key, so they never get a "(not set)" row.
- OS version, Page format and Crawler aren't on any card. They're filters and Explore breakdowns only.
- Crawler only has values with crawlers shown.
- Entry hostname is empty when `landing_page` was recorded without a scheme.
- Exit page is the last `page_view` by time, ignoring crawlers. A tie goes to the higher event id.
- The Referrer card hides referrers from your own site (the site host on Settings, General, and its subdomains).
- Page group can't be filtered from the menu and isn't in Explore. It's the "Grouped" breakdown on Top pages.
- Goal is described in [Goals and funnels](goals-and-funnels.md) and custom properties in [Custom properties](custom-properties.md).
- Your app can add dimensions of its own. See [Extending](extending.md#dimensions).

### Source

Source is the first of these that has a value:

1. `utm_source`, as recorded.
2. "Internal", when the referring domain is the site host or a subdomain of it.
3. `referring_domain`, as recorded.
4. "Direct / None".

Source isn't cleaned up. `www.google.com` and `google.com` are two rows, and so are `Newsletter` and `newsletter`. Channel is the cleaned-up version.

### Channels

Channel groups visits into eight buckets from `utm_medium` and the referring domain. The medium is lowercased, and the domain is lowercased with a leading `www.` dropped. The first rule that matches wins:

| Order | Channel | When |
|---|---|---|
| 1 | Paid Search | medium is `cpc`, `ppc`, `paid` or `paidsearch` |
| 2 | Email | medium is `email`, `e-mail` or `newsletter`, or the domain is a webmail domain (below) |
| 3 | Organic Social | medium is `social`, `social-network`, `sm` or `paid-social` |
| 4 | Organic Search | the domain is a search engine (below) |
| 5 | Organic Social | the domain is a social site (below) |
| 6 | AI Assistants | the domain is an AI assistant (below) |
| 7 | Internal | the domain is the site host or a subdomain of it |
| 8 | Referral | any other referring domain |
| 9 | Direct / None | no referring domain |

`paid-social` lands in Organic Social. `utm_source` plays no part.

Webmail: `mail.google.com`, `mail.yahoo.com`, `mail.aol.com`, `mail.proton.me`, `mail.zoho.com`, `outlook.live.com`, `outlook.office.com`, `outlook.office365.com`.

Search engines: `bing.com`, `duckduckgo.com`, `search.yahoo.com`, `ecosia.org`, `brave.com`, `search.brave.com`, `startpage.com`, `baidu.com`, and any domain starting with `google.` or `yandex.`. That catches `google.co.uk` and misses `news.google.com`.

Social: `facebook.com`, `m.facebook.com`, `l.facebook.com`, `instagram.com`, `t.co`, `x.com`, `twitter.com`, `reddit.com`, `out.reddit.com`, `linkedin.com`, `lnkd.in`, `youtube.com`, `pinterest.com`, `tiktok.com`, `news.ycombinator.com`.

AI assistants: `chatgpt.com`, `chat.openai.com`, `claude.ai`, `perplexity.ai`, `gemini.google.com`, `copilot.microsoft.com`.

The lists are fixed; there's no setting to add to them.

The site host is set on Settings, General, and a leading `www.` is ignored. The queries read it every time they run, so a change reclassifies your own pages on the next request, history included. While it's blank, your own pages referring to each other show up as Referral instead of Internal.

Related: [Dashboard](dashboard.md), [Tracking](tracking.md), [Filters and segments](filters-and-segments.md).
