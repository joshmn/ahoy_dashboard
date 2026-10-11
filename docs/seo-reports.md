# SEO reports

The SEO tab turns what [Search Console](search-console.md) and [rank tracking](rank-tracking.md) have already stored into reports that answer one question each. Opening a report never costs anything, because nothing here calls a provider.

Six reports read rank checks and need rank tracking set up. Four read Search Console and need it connected. One of those also reads your ahoy visits and goals.

Optional. These reports read what [Search Console](search-console.md) and [rank tracking](rank-tracking.md) store, and both are off until you turn them on.

| Report | Answers | Reads |
|---|---|---|
| [Visibility](#visibility) | How visible am I across all my tracked searches, as one number? | Rank checks |
| [Position changes](#position-changes) | What moved up, down, in or out? | Rank checks |
| [Landing pages](#landing-pages) | Which pages are carrying my rankings? | Rank checks |
| [Keyword gap](#keyword-gap) | Where do competitors beat me? | Rank checks |
| [Volatility](#volatility) | How much are my results pages changing? | Rank checks |
| [SERP features](#serp-features) | What else is on my results pages, and who holds it? | Rank checks |
| [Opportunities](#opportunities) | Which searches would bring the most extra clicks from a better position? | Search Console |
| [Cannibalization](#cannibalization) | Where do my own pages compete for the same search? | Search Console |
| [Brand vs. non-brand](#brand-vs-non-brand) | How am I doing with people who don't already know my name? | Search Console |
| [Search to conversion](#search-to-conversion) | Which pages turn search clicks into goals? | Search Console, visits, goals |

## The SEO tab

SEO in the header opens the overview. The rail on the left lists everything under it:

| Group | Pages |
|---|---|
| Search Console | Performance, Opportunities, Cannibalization, Brand vs. non-brand, Search to conversion |
| Rank tracking | Rankings, Visibility, Position changes, Landing pages, Keyword gap, Volatility, SERP features |
| Research | [Keyword research](keyword-research-and-backlinks.md#keyword-research), [Backlinks](keyword-research-and-backlinks.md#backlinks) |
| Monitoring | [Alerts](alerts.md), [AI visibility](ai-visibility.md) |

A dimmed page in the rail has no data at all yet. It still opens, and says what it needs.

A page whose feature isn't installed in your app carries a "Not installed" badge in the rail. It still opens, and shows "Not installed yet" with the exact commands to install it, like `bin/rails generate ahoy_dashboard:install --only serp` and `bin/rails db:migrate`. See [Adding a feature later](installation.md#adding-a-feature-later).

### The overview

| Card | Shows |
|---|---|
| Google search | Clicks, impressions, CTR and average position for the range, with a daily clicks chart |
| Top queries | Your top 5 queries by clicks |
| Best opportunities | The 3 searches with the most to gain. See [Opportunities](#opportunities). |
| Rank tracking | Searches tracked, how many rank, top ten, top three and median position. It says "Sample data" while the sample provider is active. |

Until everything's done, a Set up card lists what's left:

| Step | Done when |
|---|---|
| Connect Search Console | Google is connected and a property is picked |
| Add your site | A site is added on Settings, Rank tracking |
| Track keywords | At least one keyword is tracked |
| Choose a search provider | A real provider with keys is active on Settings, Search provider, and rank tracking is on under Settings, Features |
| Turn on alerts | Alerts are on under Settings, Features and at least one rule is on |

A step whose feature isn't installed shows a "Not installed" badge and the commands to install it instead of a button.

## What every report shares

The date range menu has the dashboard's periods except Realtime, Today and Yesterday, which are too short for search data. It opens on the last 28 days, or on the last range you picked on an SEO page if that range covered 28 days or more. "Custom range" has no date picker here. Without dates it falls back to the last 30 days. Put them in the URL instead: `?period=custom&from=2026-06-01&to=2026-08-31`.

"All time" starts at your first ahoy visit, so Search Console history from before that is only reachable with a custom range.

The site menu shows on Visibility, Position changes, Landing pages, Keyword gap and SERP features, once you have more than one site. It opens on your site. Changing it changes whose positions you're reading, not which searches.

A Tag menu shows on the same six rank reports: Visibility, Position changes, Landing pages, Keyword gap, Volatility and SERP features. Picking one narrows the report to keywords carrying that tag. See [Tags](rank-tracking.md#tags).

Filters don't apply. Search Console rows and rank checks have no visitor attached, so there's nothing for a filter to narrow.

Opportunities, Cannibalization, Brand vs. non-brand and Search to conversion get a Device menu (All devices, Desktop, Mobile, Tablet) and a Country menu (All countries, then every country with rows in the range). On Search to conversion, picking one also narrows the visits side to that same device and country. Rows pulled before the dashboard started pulling device and country have neither. They count under "All" and read as "Unknown". The six rank reports don't take these menus, since a tracked keyword's device is already part of the keyword. See [Device and country](search-console.md#device-and-country).

Opportunities, Cannibalization and Brand vs. non-brand let you tick searches and click "Track these" to add several to rank tracking in one go. A query already tracked shows "Tracked" instead of a checkbox. Opportunities has three tables and each one tracks on its own, so ticking in one doesn't carry to the next. Cannibalization gives every search its own card rather than a table, so its "Select every search" box sits by the button instead of in a table head. See [Track queries](search-console.md#track-queries).

The six rank reports say "These are sample results" while the sample provider is active. The warning follows whichever provider is active now, not the one that wrote the readings. Switch to a real provider and old sample readings keep feeding these reports with no warning.

In every report, a tracked search opens its [rank history](rank-tracking.md#one-keyword). A Search Console query opens [its history](search-console.md#one-query). A page opens the dashboard filtered to that page. "Track" adds a search to rank tracking, and "Tracked" means it already is.

Trend lines are scaled to the highest and lowest points in the range, with no zero line, so a small move fills the whole height. A line needs at least two points to draw.

### CSV

A "CSV" button sits above every table on every report, and downloads that table. What you get is the rows the page is showing, in the order it shows them, for the report's date range, site, tag, device, country and brand terms. Where the page caps a table, like Opportunities' top 30, or pages it, like the alert feed, the file holds the same rows and no more. Where the page hides the rest behind "Show more", that is the same table continued, so the file holds all of it.

The file is `ahoy-dashboard-seo-<report>-<YYYY-MM-DD>.csv`, dated today in the time zone set on [Settings, General](configuration.md#settings-general). `<report>` is `visibility`, `position-changes`, `landing-pages`, `keyword-gap`, `volatility`, `serp-features`, `opportunities`, `cannibalization`, `brand-split`, `search-to-conversion`, `performance`, `rankings`, `rank-keyword`, `keyword-research`, `backlinks`, `alerts` or `ai-visibility`.

A report with more than one table names the table after the report, so Anchor text on Backlinks downloads as `ahoy-dashboard-seo-backlinks-anchors-2026-08-20.csv` and Queries on Performance as `ahoy-dashboard-seo-performance-queries-2026-08-20.csv`. Volatility and Cannibalization have one table each and are named after the report alone.

The first row is the headings the table shows. Numbers are raw: positions to one decimal, rates as percentages to one decimal, clicks and counts as integers. A number the dashboard does not have is an empty cell, not a dash. Where the page shows a badge, the file holds the word on it. Where the page says "5 days ago", the file holds the timestamp.

Same formula risk as any export. See [CSV exports](security-and-privacy.md#csv-exports).

## The click-rate curve

Visibility, Landing pages and Opportunities all need to know how many clicks a position is worth. They use one fixed curve of typical organic click rates:

| Position | Click rate | Position | Click rate |
|---|---|---|---|
| 1 | 39.5% | 6 | 4.1% |
| 2 | 18.7% | 7 | 3.3% |
| 3 | 10.1% | 8 | 2.8% |
| 4 | 7.0% | 9 | 2.4% |
| 5 | 5.2% | 10 | 2.1% |

From 11 to 20 it slides from 1.9% to 0.9%. Past 20 it's 0, because a result on page three gets no clicks worth counting.

A fractional Search Console position is rounded down before it's looked up, so 7.4 reads as 7.

These are pooled figures from across the web, not your site's own, and the same curve applies to mobile. It's good for ranking one search against another. It isn't a forecast.

## Visibility

Visibility is one score for all your tracked searches, from 0 to 100: the share of the clicks your searches could get if every one of them ranked first.

Reads your rank checks for the selected site.

Each search earns its position's click rate from the curve. The score adds those up and divides by what you'd earn at 1st on every search. So:

| Every search at | Scores |
|---|---|
| 1st | 100 |
| 2nd | 47.3 |
| 3rd | 25.6 |
| 10th | 5.3 |
| 20th | 2.3 |
| Past 20th, or not found | 0 |

A set spread evenly across 1st to 3rd scores about 57. Watch which way it moves rather than chasing 100.

The Weighting switch at the top decides how much each search counts. It only shows once there's data.

| Weighting | Counts |
|---|---|
| Even | Every search the same |
| By impressions | Each search by its Search Console impressions in the range, so a search thousands of people run counts for more than one a handful do |

By impressions matches the tracked keyword to the Search Console query exactly, case included. A tracked "Acme Pricing" gets nothing from Google's "acme pricing". If no search matches, it falls back to even and the Weighting tile says so. Changing the date range or the site puts the weighting back to Even.

Searches that dropped out of the results still count toward the total. Losing a search always lowers the score, where a report that only counted what ranks would call it an improvement.

On the page:

- Tiles: the score now and its change over the range, how many searches rank now, the best and worst days, the weighting, and how many days had a check.
- "Visibility over time", one point per day.
- "Top contributors": each ranking search, its position, its click rate, its points, and its share of the score.
- "Not ranking": the searches earning nothing.

Change over the range is the last day against the first day, not against an earlier period.

**Mixed cadences make the line jump.** A day's score only counts the searches checked that day, while the total counts every search in the range. With weekly keywords among daily ones, the line dips on days they weren't checked and jumps on days they were. Keep every keyword on one cadence if you watch this line. The headline tiles are the last day's, so they can be short too.

## Position changes

Position changes shows what moved between the first and last reading of each search in the range. It isn't day over day: on searches checked weekly, a daily diff would mostly be a list of searches nobody looked at.

Reads your rank checks for the selected site.

| Group | First reading | Last reading |
|---|---|---|
| Gone from the results | Ranked | Not found |
| Fell | Ranked | Ranked lower |
| Arrived | Not found | Ranked |
| Climbed | Ranked | Ranked higher |
| Did not move | Ranked | Same position |
| Not ranking | Not found | Not found |

"Not found" means not in the pages the keyword is set to check.

The bar at the top shows how many searches are in each group, and each count jumps to its list. Under it, how many crossed onto page one and how many fell off. A search that arrived straight onto page one, or vanished off it, isn't counted as a crossing.

Each row shows where it was and is, the change, and the page that ranks now. If searches were read on different days, a column says when each one was read.

A search read only once in the range shows as "Did not move", since the first and last reading are the same one. If the range has no search with two readings, the page says "Only one reading in this range".

"Did not move" only compares the two ends. A search can go from 4 to 20 and back to 4 inside the range.

## Landing pages

Landing pages groups your tracked searches by the URL that ranks for them. It's Rankings turned around, so each row is a page instead of a search.

Reads your rank checks for the selected site.

One row per URL that ranked for at least one tracked search in the range. Columns:

| Column | Is |
|---|---|
| URL | The ranking page, as the provider returns it |
| Searches held | Searches and places whose latest reading in the range ranks this URL |
| Best position | The best position among the searches it holds |
| Median position | The median position among the searches it holds |
| Share of visibility | The page's points from the [click-rate curve](#the-click-rate-curve), as a percentage of the site's total |

A row opens to the searches it holds.

"Lost every search" lists pages that held at least one search earlier in the range and hold none on the latest reading, with those searches listed as gone.

Follows the site menu and the [Tag menu](rank-tracking.md#tags). URLs are compared as the provider returns them.

## Keyword gap

Keyword gap puts your position next to every competitor's, search by search. It costs nothing extra: each search is fetched once and every site on it is scored from the same page.

Reads the latest rank check of each site on each search. The site in the menu is "you", and every other site is a competitor. You need at least one competitor, ticked on the keywords you want compared.

| Group | Means |
|---|---|
| Missing | A competitor ranks and you don't |
| Behind | You both rank and one of them is ahead of you. Ties count as behind. |
| Ahead | You rank above every competitor on the page |
| Uncontested | You rank and none of them do |
| Nobody ranks | Neither you nor any competitor turns up |

"Behind" sorts by how far behind. The Gap column is the best competitor's position minus yours.

"How often each competitor shows up" is the share of your searches each one ranks on. A domain that turns up on 2 of your 80 searches isn't much of a competitor.

Your latest check and a competitor's can come from different days if they were ticked on the keyword at different times.

## Volatility

Volatility measures how much your results pages are changing: the top 10 for each search you track, from one check to the next. It measures the part of Google your site lives in, not the web at large.

Reads the stored top 10 of every check, for every keyword. It isn't per site, so there's no site menu. It needs at least two checks of the same search from the same place in the range.

Each pair of back-to-back checks gets a score:

| Part | Is |
|---|---|
| Turnover | The share of the top 10 that's new. Links are compared as full URLs, so a site swapping one of its pages for another counts as turnover. |
| Shuffle | How far the results that stayed moved, on average |
| Score | 60% turnover and 40% movement, times 100. A link that stayed counts how far it moved; a link that left counts as the full move. |

A day's score is the average of that day's pairs. The overall score is the average of the days.

| Score | Reads |
|---|---|
| Under 12 | Still |
| 12 to 25 | Normal |
| 25 to 45 | Choppy |
| 45 to 65 | Rough |
| 65 and up | Storm |

On the page: the overall score and its level, the latest day, the peak day, how many pairs were compared, and "Most changed searches", with the new domains on each page.

The first check of a search in the range has nothing to compare against, and adds nothing to the score rather than a zero.

## SERP features

SERP features shows what's on your results pages besides the ten blue links, and who holds each spot. It reads the results pages already stored from each rank check, so it costs nothing.

It uses the latest check of each search and place in the range, across every keyword. The site menu only decides whose spots count as "yours".

| Feature | Shows as |
|---|---|
| Featured snippet | Snippet |
| AI overview | AI |
| Knowledge panel | Panel |
| People also ask | Asked |
| Local pack | Local |
| Top stories | News |
| Video | Video |
| Images | Images |
| Forums and discussions | Forums |
| Related searches | Related |

On the page:

- Tiles: searches read, featured snippets (and how many are yours), knowledge panels, questions asked (and how many you answer), local packs.
- "Features on your results pages": how often each feature shows, how many you hold, and who holds it most.
- "Search by search": which features showed on each search, and whether your site is in them.
- "People also ask": every question Google asked across your searches, which site answers it most, and a Track link for each.
- "Related searches": what Google suggests next. Click one to track it.

If nothing in the range saved a results page, the page shows "No results pages saved in this range" instead of the tiles and tables, with a count of the checks that ran and a link back to Rankings.

## Opportunities

Opportunities ranks your searches by the extra clicks a better position would bring. It works from the impressions Google actually recorded for your site, not a bought search volume.

Reads Search Console queries. Rank tracking isn't needed. Only searches with at least 30 impressions in the range count, since below that the position is noise.

For each search:

| Figure | Is |
|---|---|
| Upside | The extra clicks you'd get at 3rd place, from the [click-rate curve](#the-click-rate-curve), minus the clicks you already get. Third rather than first, because first isn't on the table for most searches. A search already in the top three has no upside. |
| Expected | The clicks a search at your position usually gets |
| Below expected | Fewer than 60% of expected. That's usually the title and snippet, not the rank. |
| Band | Holding (top 3), Page one (4 to 10), Striking distance (11 to 20), or Deep |

The main table keeps the 60 searches with the most upside. The tiles and the two lists below it cover every qualifying search, not just those 60.

- "Worth the most": the top 30 of that 60, with each search's landing page.
- "Striking distance": positions 11 to 20, by upside.
- "Below expected clicks": the biggest shortfalls.

Upside is for sorting the list, not a forecast. The curve is typical rates, not yours.

## Cannibalization

Cannibalization lists the searches where two or more of your pages show up, split into the harmless kind, where one page clearly wins, and the kind that costs clicks.

Reads Search Console queries by page. A search counts when more than one of your pages showed for it and it had at least 30 impressions in the range.

| Standing | Means |
|---|---|
| Split and swapping | The second page gets 20% or more of the clicks, and the top two pages' average positions are 3 or fewer places apart |
| Worth a look | One of those two |
| One page wins | Neither |

One card per search, with every page that showed: its clicks, impressions, position, how many days it showed, and whether it's the top page, second, or also shown. The line under each card says what's going on in plain words.

Google leaves out the most data at the query-and-page level, so small overlaps don't show here, and a quiet page isn't proof there's no problem.

## Brand vs. non-brand

Brand vs. non-brand keeps searches for your name apart from everything else. Pooled together, a good week of people searching for you by name can hide a bad month of everybody else.

Reads Search Console queries.

A search counts as brand when it contains any brand term and no exclusion, each matched ignoring case, spaces and hyphens, so a term like `acmewidgets` matches "acme widgets" and "Acme-Widgets reviews".

On the page: clicks, click-through rate and average position for each side, and a card for each with a daily clicks chart and its top 15 searches.

Hidden queries aren't in Search Console's query list at all, so this only splits the clicks Google tied to a query.

### Brand terms

Set your list in the "Brand terms" and "Exclude" boxes, one term per line, and click "Save and split". Both lists are saved on the server, so everyone who opens the report sees the same split and changing the date range keeps it.

With nothing saved, the brand terms default to the first part of the site host on Settings, General: `example.com` gives `example`. Nothing is excluded by default.

Saving re-splits the stored rows. It doesn't ask Google for anything new.

[AI visibility](ai-visibility.md) reads the same brand terms.

## Search to conversion

Search to conversion shows what visits from search went on to do, page by page. Google's clicks and your own visits and goals are in the same database, so this is a join rather than an integration.

It's organized by landing page, with each page's top search alongside, since Google can't say which search a visit came from.

Reads Search Console queries by page, your ahoy visits from the Organic Search [channel](metrics-and-dimensions.md#channels), and your [goals](goals-and-funnels.md). Without a goal, clicks and visits still show, the conversion columns are left off, and a notice says to set up a goal.

For each page, the 40 with the most clicks:

| Column | Is |
|---|---|
| Page | The landing page |
| Top search | The search with the most clicks to this page, with the page's average position under it |
| Clicks | Clicks Google counted to this page |
| Visits | Organic search visits that started on this page |
| Converting visits | Search visits that completed a goal. A visit counts once, even if it completes more than one goal. Only shown once you have a goal. |
| Rate | Converting visits divided by visits. Only shown once you have a goal. |

"Search traffic with no conversions" lists the pages with 20 or more clicks and nothing converting. Those rank and get the click, and then lose people.

Google counts clicks on its results. Your site counts visits that ran your tracking. The two never match, so only a big gap between Clicks and Visits means something. And Visits includes every search engine, while Clicks is only Google, so on a site with a lot of Bing traffic, visits can pass clicks.

Related: [Search Console](search-console.md), [Rank tracking](rank-tracking.md), [Keyword research and backlinks](keyword-research-and-backlinks.md), [Alerts](alerts.md).
