# Rank tracking

Rank tracking checks where your site shows up on Google for the searches you pick, from the places you pick, on a schedule. It also records whether Google showed an AI overview and whether it cited you.

Optional. It's off until you turn it on, and the rest of the dashboard works without it. It needs an account with a search data provider, or runs on sample data.

Search Console tells you your average position across everybody who searched. Rank tracking tells you where you were on one real results page, from one place, on one day. They answer different questions, and you probably want both.

Results come from a paid search API. Each check is one or more requests to that provider, so this is the part of the dashboard that costs money. It starts on sample data that costs nothing until you pick a provider.

Tracking starts the day you add a keyword. Nobody can fetch where you ranked last month.

## Turn it on

Install its tables first if you left it out at install time:

```sh
bin/rails generate ahoy_dashboard:install --only serp
bin/rails db:migrate
```

Until then, Rankings and Settings, Rank tracking show "Not installed yet" with those two commands. See [Adding a feature later](installation.md#adding-a-feature-later).

Then click "Turn on" next to Rank tracking on [Settings, Features](configuration.md#settings-features). It shows as Needs setup there until a real provider with credentials is active, with a "Set it up" button that goes to Settings, Search provider.

With it off, nothing is checked and the check buttons explain why, but everything already recorded still shows.

## Providers

Pick one on Settings, Search provider. Only one is active at a time.

| Provider | Needs | Cost per place, per check | Countries | Also sells |
|---|---|---|---|---|
| Sample data | Nothing | Free | All | Invented keyword ideas and backlinks |
| SerpApi | API key | 1 per results page (1 to 5) | All | Nothing |
| SearchApi | API key | 1 per results page (1 to 5) | All | Nothing |
| DataForSEO | Login and password | 1, however deep | 26 | [Keyword ideas and backlinks](keyword-research-and-backlinks.md) |

A "unit" is one request to the provider. That's what the dashboard counts, and what the monthly cap limits. What a provider actually bills per request is between you and them.

To set one up:

1. Open Settings, Search provider and click Edit on the provider.
2. Paste the key (or DataForSEO's login and password).
3. Set a monthly cap. See [The monthly cap](#the-monthly-cap).
4. Switch on "Use this one".
5. Click "Save provider".

Keys are encrypted before they're stored and never shown again. A blank box on the form keeps what's stored. A "Remove" button next to a stored key, or next to DataForSEO's login and password, deletes it. It asks first and names what stops working, and the field then reads "Nothing stored."

This screen is the only place keys go. The initializer and environment variables aren't read for them. With no provider saved and marked "Use this one", the dashboard runs on sample data. The Credentials column reads Stored, Missing, or None needed for the sample provider.

Keys saved for a provider that isn't the active one aren't used for rank checks. Keyword research and backlinks can still use them if you point either one at that provider. See [Keyword research and backlinks](keyword-research-and-backlinks.md#turn-them-on).

### Sample data

The default. It invents results from the search itself, so the same search gets the same answer on the same day and drifts a little from day to day. Your site shows up in about three searches out of four. About a third have no AI overview.

It's there so you can see every screen before you pay anybody. Rankings says "These are sample results" at the top while it's active. Switch to a real provider and the sample readings stay in your history, with nothing marking them as fake.

### Positions differ between providers

SerpApi and SearchApi count organic results only: the first organic result is 1. DataForSEO counts everything above the result too, like the AI overview, ads and answer boxes. The same page can be 1 on SerpApi and 3 on DataForSEO.

So switching providers shifts every number, and the chart shows a jump that didn't happen. Pick one and stay on it.

### DataForSEO's countries

DataForSEO can only search from these 26: `us gb ca au ie nz de fr es it nl se no dk fi pl pt br mx ar in jp kr sg za ph`. With it active, the keyword forms only offer those. A keyword saved with another country before you switched fails on every check, and only the log says so.

## The monthly cap

Every saved provider has a monthly cap, in units. It starts at 500. 0 means no cap.

- The month is the calendar month in the time zone set on [Settings, General](configuration.md#settings-general), and the count starts over on the 1st.
- A check that doesn't fit in what's left of the cap isn't sent.
- Only checks that came back count. A failed check spends nothing on the dashboard's count.
- "Used this month" on Settings, Search provider shows where you are.
- [Keyword lookups and backlink syncs](keyword-research-and-backlinks.md) spend from a provider's cap the same way a check does. That's the rank tracking provider unless the keyword research or backlinks provider on Settings, Search provider says otherwise, so by default they share this cap with your rank checks.

Reserving a check's units and spending them back is one database update, so two checks racing for the last bit of room can't both get through.

## The spend card

Settings, Rank tracking opens with a card that says where the month stands. Three things, in order down the card.

**Used this month, against the cap.** The number and the bar under it come from the provider's own running total, which is the figure the cap is checked against. With no cap set it says so and shows no bar, because there's nothing to be a share of.

**A bar per day.** One bar for every day of the month so far, stacked by what the units went on: rank checks, keyword ideas and backlink syncs. All three spend from the same cap, so all three are on the same bars. Point at a day for its own numbers.

**What the rest of the month costs.** Every check already scheduled between now and the last day of the month, worked out one check at a time from each keyword's cadence, places and depth rather than divided out of a monthly average. A weekly keyword on the 27th has one check left, or none. Daily backlink syncs are in the number too when backlinks run through this same provider. The line ends with where the month lands: "ending the month at 340 of 500", or, if it would go past, what the cap stops it at.

Keyword lookups aren't in that number. Nothing schedules them; they happen when you ask for one.

### At 80%

Once the month passes 80% of the cap, the card warns, and the "Nearing the monthly cap" [alert](alerts.md#spending-rules) fires once. The alert lands on SEO, Alerts, goes to `alert_notifier` and turns up in the alert emails, like any other.

- It fires once a month, however often the rules run. Raise the cap and pass 80% of the bigger number, and it fires again, because raising it was a decision to spend more.
- Change the threshold on Settings, Alerts and the card warns at the new number too. The page and the email never disagree about where "nearly there" is.
- The alert is a warning, not the control. The cap is the control, and it still stops spending at 100%.
- It's off until you switch it on, like every rule.

### What the bars can't show

The daily rows start the day you upgrade to the version that added them. Rank checks before that are rebuilt from the searches already stored, so those bars are real. Keyword lookups and backlink syncs before the upgrade aren't recorded anywhere, so they're missing from the bars while still counted in the month's total. The two figures can disagree by that much, once, in the month you upgrade.

## Add your site

Checks look for sites in the results, so start with yours.

1. Open Settings, Rank tracking and switch to the Sites tab.
2. Click "Add site". The domain is filled in from the site host on Settings, General.
3. Click "Add site".

Enter just the host. `https://www.example.com/pricing` is saved as `example.com`, because matching is by host, never by URL. A leading `www.` always matches.

"Count subdomains as this site" makes `blog.example.com` count as `example.com`. Without it, only the exact host matches.

Adding a site switches on "Look for it on every tracked keyword" by default, so it's attached to everything you already track right away and its positions are read out of the searches already saved, for free. Turn the switch off on the form to tick it onto keywords one at a time instead.

The site whose domain matches the site host gets the "Us" badge. It's the one Rankings opens on, the one alerts watch, and the one other SEO reports call yours.

### Competitors

Add a competitor's domain here the same way, then tick it on the keywords you want to compare, or leave the switch above on to tick all of them at once. Every site on a keyword is read from the same search, so competitors cost nothing extra.

Deleting a site deletes every position recorded for it. Add it back later, with "Look for it on every tracked keyword" on, and they're read again from the same stored searches.

## Track a keyword

Settings, Rank tracking, "Track keyword". Or use "Track" next to any query on the SEO screens.

| Field | Default | Notes |
|---|---|---|
| Keyword | | Type it the way people search for it. Extra spaces are squeezed out, and case is kept. |
| Places to search from | United States | Up to 5. See [Places](#places). |
| Device | Desktop | Desktop, Mobile or Tablet |
| Language | `en` | A two-letter code. The dashboard doesn't check it, so a typo goes straight to the provider. |
| How often | Daily | Daily, Weekly, Every 2 weeks or Monthly. Weekly is plenty for most keywords and costs a seventh of daily. |
| How deep | Top 10 | Top 10 up to Top 50. A site past that depth reads as not found. |
| Sites to look for | Your site | Any sites you've added |
| Tags | None | Type one and press Enter. Existing tags are suggested. See [Tags](#tags). |

One keyword per phrase, device and language. To track the same phrase on mobile too, add it again with Mobile.

Above the form, up to 8 queries from Search Console that you get impressions for and don't track yet. Click one to fill in the Keyword box.

Nothing is checked when you save. The first check runs within the hour, or press "Check now".

### Places

A place is a country, or a city inside one. Leave the city blank for the whole country.

A city has to be Google's own name for it, like `Chicago,Illinois,United States`. The dashboard doesn't check city names, so a misspelled one fails at the provider on every check. A city with no country picked is quietly dropped.

Each place is a separate search every time the keyword is checked. Three places is three times the cost.

### What it costs

The box next to the form works it out before you save:

- Sample data: "Free".
- A paid provider: searches a month, from the provider's cost per check, the places, how deep, and how often. Daily, one place, top 10 on SerpApi is 30 a month. Daily, two places, top 20 is 120. Weekly, one place, top 10 is 5.
- With a cap, it says how much of this month's cap is left, and warns when this one keyword would go past it.

The keyword list shows the total for everything you track.

## Import a list

Settings, Rank tracking, "Import a list" adds many keywords at once, with the same places, device, language, cadence, depth, sites and [tags](#tags) for all of them.

- From Search Console: your top 50 queries from the last 90 days that you don't track yet, by impressions. Tick the ones you want.
- Or paste a list, one per line.

The same import can also be started from any Search Console query list with "Track these", which shows a cost line first. See [Track queries](search-console.md#track-queries).

It defaults to Weekly. Repeats are skipped, and so is anything already tracked. Only the first 200 are imported, without a warning past that. There's no cost estimate on this screen, so do the math before you import 200 keywords checked daily from 5 places.

## Tags

The keyword form has a "Tags" field: type a tag and press Enter, and it suggests tags already in use. [Import a list](#import-a-list) and "Track these" take a set of tags for the whole batch instead of one keyword at a time.

On Rankings, tick keywords and use "Add tag" or "Remove tag" to change tags on several at once.

A "Tag" menu lists All tags, then every tag in use. It appears on Rankings, the [Rankings distribution](#rankings-distribution) card, and on Visibility, Position changes, Keyword gap, Volatility, SERP features and [Landing pages](seo-reports.md#landing-pages) in [SEO reports](seo-reports.md). Picking one narrows the page to keywords carrying that tag.

A keyword can carry any number of tags. One with none only shows under All tags, and deleting the last keyword carrying a tag drops that tag from the menus.

## Edit, pause and delete

Editing changes the keyword in place for places, depth and cadence: its old readings stay with it, and a reading for a place you remove drops out of Rankings right away, tiles, distribution and AI overviews included, even though it's not deleted. Add the place back and it shows again.

Change the keyword's phrase, device or language and its history starts over instead: readings for the old search move to a paused copy that keeps the old settings, tags and sites, and it sits in the keyword list where you can delete it if you don't want it. The new keyword is checked again within the hour, like any new keyword. If the new search already exists as a keyword, the save is rejected instead of colliding with it.

Tick a new site on a keyword and the dashboard reads that site's positions out of every search already stored, for free. The notice says how many were read again.

Switch off "Keep checking this keyword" to pause. Past readings stay, and a paused keyword costs nothing.

Deleting a keyword deletes its whole history, and nobody can fetch it again.

## When checks run

A job looks for due keywords every hour and checks only those. Each place is its own check. See [Background jobs](background-jobs.md).

A keyword is due when its last good check is a full cadence old. Daily means 24 hours, weekly means 7 days. Because the job runs hourly, a daily keyword checked at 10:07 isn't picked up until the run after 10:07 the next day, so its time slides a little later each day.

A check that fails doesn't count as done. The keyword is tried again every hour, with no backing off, until it works.

### Check now

| Button | Where | Checks |
|---|---|---|
| Check now | Rankings | Every tracked keyword, from every place |
| Check all | Settings, Rank tracking | Every tracked keyword, from every place |
| Check | Each row on Settings, Rank tracking | That keyword, from every place |
| Check now | One keyword, and Edit keyword | That keyword, from every place |

These ignore the cadence, and the next scheduled check lands a full cadence after this one. Each asks first and says roughly how many units it'll spend.

Pressing twice within 2 minutes is refused, as long as your app's cache is shared across processes. With a per-process cache like `:memory_store` in development, it can send twice.

A button that can't run says why:

| Reason | Fix |
|---|---|
| "Rank tracking is off. Turn it on under Settings, Features." | Turn it on under Settings, Features |
| "SerpApi has no credentials yet." | Add the key on Settings, Search provider |
| "This month's search limit is used up." | Raise the cap, or wait for the 1st |
| "Track a keyword first." | Track one, or unpause one, or give one a site |
| "This keyword is paused." | Switch it back on |
| "Pick a site to look for first." | Tick a site on the keyword |
| "Sent for checking a moment ago." | Wait, then reload |

Checks run in the background. Reload after a minute to see them.

## How a position is worked out

- Only organic results count. Ads, answer boxes, maps, videos and the AI overview are never a position.
- A site's position is its best result. If it shows up twice, the second one is only in "Who else ranked".
- Positions count from the top of the results across every page checked. Result 3 on page 2 is 13.
- A site that isn't in the results is recorded as not found, which is a real reading. Rankings shows it as "Past 20" for a top 20 check.

## AI overviews

Each check records whether Google showed an AI overview for that search and, if so, whether it cited each site, and every source it cited.

Sometimes a provider hands back an overview that hasn't finished loading and has no sources yet. The dashboard doesn't go back for it, so it counts as shown without you, even if Google would have cited you. Expect citations to run a little low.

A citation isn't a click, so it never shows up in your visit numbers.

## Rankings

SEO, Rankings is where your site stands on every tracked search. It opens on your site. With more than one site, switch sites from the menu, and narrow to one [tag](#tags) from the Tag menu.

| Tile | Is |
|---|---|
| Searches | Keyword and place pairs with a reading in the range |
| Ranking | How many of those you're in the results for now |
| Top ten | How many you're 10 or better on now |
| Top three | How many you're 3 or better on now |
| Median position | The middle of your current positions, counting only searches you rank on |
| AI overviews | How many showed an overview on the latest check, and how many of those cite you |

"Now" means the latest reading in the range.

"Tracked searches" has one row for each keyword and place: the position now, the change since the reading before, your best in the range, AI overview ("Cited", "Shown" or a dash), and the page that ranked. A search that started ranking since the reading before shows "New" instead of a change, and one that dropped out of the results shows "Gone". The page links to the dashboard, filtered to that page.

"Who else is on page one" is the domains in the top 10 on the latest check of every search you're tracking for the site you picked, with how many of those searches each one appears in. A domain holding two results on the same page still counts once.

"AI overviews" says how often checks for the site you picked showed an overview, how often those cited you, and which domains get cited most.

See [Landing pages](seo-reports.md#landing-pages) for these same searches grouped by the page that ranks for them.

Every table on this page exports to CSV. See [CSV](seo-reports.md#csv) for the file details.

## Rankings distribution

A card on Rankings, counting your tracked searches by band: Top 3, 4 to 10, 11 to 20, Past 20 and Not found. "Past 20" only fills when a keyword checks deeper than 2 pages. "Not found" means the site didn't show up in the pages checked.

One stacked bar per day across the date range. Each day counts every search and place at its latest reading as of that day, so a day with no check still shows the full set, and a weekly keyword doesn't make the bars jump.

Click a band to filter the keyword list below to searches whose latest reading falls in it.

Follows the site menu and the [Tag menu](#tags). It costs nothing: the card only reads checks already stored.

## One keyword

Click a search on Rankings for its history from one place. Switch places from the menu, and switch device or language from its own menu when the same phrase is tracked on more than one.

- Tiles: position now and the change since the reading before, best and worst in the range, and how many readings had an AI overview.
- "Position over time": higher on the chart is better. A check where your site was not in the results leaves a gap in the line, and points sit at their real date, so a two-week gap between checks looks like two weeks.
- "Every reading": each check, newest first, with the date it ran. That's when the check happened, not when Google changed anything.
- "Who else ranked": the top 10 on the latest check.
- "The AI overview": what Google cited on the latest check, in order.

"See clicks" opens the same query in [Search Console](search-console.md#one-query).

This page's tables export to CSV too. See [CSV](seo-reports.md#csv).

## When checks fail

| What you see | Means |
|---|---|
| "Last error" on Settings, Search provider | The provider refused the key, or you're out of credits with them. Fix it there. |
| A keyword's "Last checked" doesn't move | Its checks keep failing. It's retried every hour. |
| "This keyword has not been checked yet. Checks start within the hour." and it never is | The keyword has no site, is paused, tracking is off, or every check fails |
| Your site reads "Past 10" but ranks on a subdomain | Turn on "Count subdomains as this site" |
| A competitor has no history | Checks only record sites ticked on the keyword at the time. Tick it and the stored searches are read again. |

Other failures, like a timeout, a provider outage or a bad city name, are only in the log (`serp check failed for ...`). Settings, Jobs shows the hourly job as "Ran" either way, because it only sends the checks.

If some pages of a deep check fail and others come back, the reading uses what came back, and nothing on screen says it was partial.

Related: [SEO reports](seo-reports.md), [Alerts](alerts.md), [Search Console](search-console.md), [Configuration](configuration.md#settings-search-provider).
