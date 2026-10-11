# Keyword research and backlinks

Everything else on the SEO tab is built from data you already have. These two can't be. Nobody's database knows what people search for in general, or who links to you, so both are bought from a provider by the row.

Optional. Both are off until you turn them on, and both need a DataForSEO login.

Only DataForSEO sells either one, and each spends from its provider's monthly [cap](rank-tracking.md#the-monthly-cap) the same way a rank check does. The [spend card](rank-tracking.md#the-spend-card) on Settings, Rank tracking splits the month's units by which of the three went on what. That's the rank tracking provider by default, so when it's DataForSEO too, keyword research and backlinks share its cap with your rank checks. Pick another provider for either one on Settings, Search provider to give them their own.

## Turn them on

Install their tables first if you left them out at install time:

```sh
bin/rails generate ahoy_dashboard:install --only keywords,backlinks
bin/rails db:migrate
```

Until then, SEO, Keyword research and SEO, Backlinks show "Not installed yet" with the commands to run. See [Adding a feature later](installation.md#adding-a-feature-later).

Then click "Turn on" next to Keyword research and next to Backlinks on [Settings, Features](configuration.md#settings-features). Each shows as Needs setup there until it has a real provider that sells the data and has credentials, with a "Set it up" button that goes to Settings, Search provider.

Both use the rank tracking provider unless you pick another. The card "Keyword research, backlinks and places" on [Settings, Search provider](configuration.md#settings-search-provider) has a Provider menu for each one. "Same as rank tracking" is the default.

With SerpApi or SearchApi active and no override, both pages say your provider doesn't sell the data, and point you at Settings, Search provider. DataForSEO active with no login does the same: the Look up and Sync now buttons refuse with "DataForSEO has no credentials set." and a link to Settings, Search provider. DataForSEO's login and password come from the same place as for rank tracking. See [Providers](rank-tracking.md#providers).

With the sample provider, both pages work and invent everything. The page says "These are sample results" while the sample provider is active, and the invented rows are stored in your real tables alongside anything you buy later.

## Keyword research

SEO, Keyword research. Type a phrase, click "Look up", and a minute later you get up to 100 related searches with their monthly volume, difficulty, cost per click and intent, next to where you already stand for each.

### Looking up a phrase

"Look up" buys a phrase, place and language combination you haven't looked up before, and runs in the background, so reload after a minute. Looking up one you've already saved costs nothing: it takes you to the saved ideas with a notice that nothing was bought. Opening the page and switching between saved phrases is free too, so use "Saved phrases" to go back to one.

To pay for fresh numbers on a saved phrase, press "Look up again", which shows once its ideas are on screen and asks you to confirm it's a paid request. It updates the ideas that come back, drops ideas the provider no longer returns for that seed, and leaves everything else with its old numbers. The same guard covers `rails ahoy_dashboard:keywords[seed]`: it skips a phrase already saved unless you add a second argument, `rails 'ahoy_dashboard:keywords[federal prison,refresh]'`. See [Background jobs](background-jobs.md).

Every lookup is kept, with no expiry.

A lookup or a refresh is one or two requests to DataForSEO: one for the ideas, and one more for difficulty if some ideas came back without it.

### Place and language

The Look up form has Phrase, Place and Language. Place uses the same picker as a tracked keyword's place: a country, or a city like `city:us:Chicago,Illinois,United States`. Both start from "Search from" and "Language" under Keyword research on Settings, Search provider. Those default to the United States and `en`. "Search from" only takes a country; pick a city on the form itself. DataForSEO knows the 26 countries listed under [DataForSEO's countries](rank-tracking.md#dataforseos-countries).

Every stored idea records the place and language it was bought under, and the page only shows the ideas for the phrase, place and language picked. Saved phrases lists each phrase with its place and language, like "self-hosted analytics, United States, en". The same phrase under another place is a second saved set, listed separately under Saved phrases.

### The ideas table

| Column | Is |
|---|---|
| Search | The idea. "Easy win" marks low difficulty with real volume. |
| Volume | Average monthly searches, from the provider |
| KD | Keyword difficulty, 0 to 100, from the provider: Easy under 35, Medium to 59, Hard at 60 and up |
| CPC | What advertisers pay per click, in dollars |
| Intent | I informational, N navigational, C commercial, T transactional |
| Your position | Your latest tracked position, or "Shown" if Search Console has ever shown you for it, or a dash |
| Track | Adds it to [rank tracking](rank-tracking.md), or opens it if it's already there |

Difficulty is the provider's number. The dashboard doesn't measure it, and every provider scores it differently.

Tiles above the table:

| Tile | Is |
|---|---|
| Ideas | How many came back |
| Monthly searches | The total volume across all of them |
| Easy wins | Ideas you don't track yet, with difficulty under 35 and at least 100 searches a month, sorted by volume for their difficulty. Click it to show only those. |
| Ranking | Ideas with a tracked position |
| Never shown | Ideas you don't track and Search Console has never shown you for |
| Looked up | How long ago |

Below the table, Questions lists the ideas phrased as a question, like "how" or "can". Clusters groups the ideas by the first two words left after taking out your phrase, with their total volume. It's rough, and it's free, where real clustering would be a second bill.

A "CSV" button above the ideas exports the ones shown, for the phrase, place and language picked, and Easy wins exports the easy ones only. Questions and Clusters have their own. See [CSV exports](seo-reports.md#csv).

## Backlinks

SEO, Backlinks shows the sites that link to yours, which ones are new, and which ones stopped.

The domain looked up is the site host on [Settings, General](configuration.md#settings-general). Without one, Backlinks refuses with "Set your site's host under Settings, General so backlinks know which site to look up."

### Syncing

With backlinks on and a real provider, a sync runs once a day on its own. See [Background jobs](background-jobs.md).

"Sync now" on the page runs one right away, after asking. It refuses the same way the daily sync does when backlinks are off, there's no site host, the active provider is sample data, or the monthly cap is spent, and the button is disabled and says which. A sync is two requests to DataForSEO: the referring domains, and the anchor text. Daily is about 60 a month.

Each sync fetches your top 500 referring domains by the provider's authority score and compares them to what's stored:

- A domain that's new gets added, dated by when the provider first saw it.
- A domain that's still there gets its numbers updated.
- A domain that's missing is marked lost, on today's date, as long as this sync pulled your whole profile (500 domains or fewer). Past 500, a missing domain is only marked lost when its stored authority beats the lowest authority this sync returned, since anything under that would have missed the cut anyway; a domain right at the edge is left alone instead of flipping between live and lost. Nothing is ever deleted.
- A lost domain that comes back is live again.

Anchor text is replaced on every successful sync: text the provider stops returning is dropped, and what it does return is saved, capped at 255 characters and deduped. A sync that can't fetch anchor text at all leaves what's stored alone.

Losing enough domains in one sync can trip the "Referring domains lost" alert. See [Alert rules](alerts.md#backlink-rules).

"New" means the provider first saw the link inside the range. On the first sync that can be a lot of sites, and a site the provider found years ago never shows as new.

### The page

| Tile | Is |
|---|---|
| Referring domains | Sites that link to you, counted once each, and the change in the range |
| Links | Links across those sites |
| Followed | The share of sites with at least one followed link |
| New | Sites that started linking to you in the range |
| Lost | Sites that stopped in the range |
| Nofollow | Sites whose every link is nofollow |

| Section | Shows |
|---|---|
| Referring domains | The count by day, once there are two syncs in the range |
| Sites linking to you | Highest authority first, with links, when the provider first saw each one, and whether it's followed |
| Anchor text | The words people link to you with |
| New and lost | The sites that came and went in the range |
| Nofollow only | Sites that pass you no authority |

Authority is the provider's own score, and no two providers agree on it. Nofollow is a fact about the link. The dashboard doesn't try to score links as good or bad.

The tiles always count your whole profile. The lists below them stop at 40 sites for domains, 15 each for New and Lost, and 10 for Nofollow only, and each one's header says so when there's more, like "Highest authority first, top 40 of 63".

The range only changes the chart, New and Lost. Everything else is as of the last sync.

Sites linking to you, Anchor text, New and lost and Nofollow only each have a "CSV" button, and each exports what it is showing for the range and site. See [CSV exports](seo-reports.md#csv).

## When a lookup or sync fails

A lookup or sync refused before it's even sent (off, no credentials, sample data, no site host, or the monthly cap) says why right on the button. Once one is actually sent, neither reports a failure on screen: a failed lookup leaves "No keyword ideas yet", and a failed sync leaves the page as it was. Check the log:

| Log line | Means |
|---|---|
| `keyword ideas hit a quota: ...` | Out of credits, or the login was refused. Both are logged as a quota. |
| `keyword ideas failed: ...` | Anything else, like an unmapped country |
| `backlinks hit a quota: ...` | Out of credits, or the login was refused |
| `backlinks failed: ...` | Anything else |

Settings, Jobs shows a failed backlinks sync as "Ran". Keyword lookups aren't on it at all.

## Known bugs

- **Past 500 referring domains, live and lost are only exact for the top 500.** A sync reads the top 500 by authority. A stored domain missing from them is marked lost only when its stored authority is above the lowest one the sync returned. So a domain that still links but slipped out of the top 500 is marked lost, and stays lost until it's back in the top 500. A domain below the cutoff that stops linking stays live. Reading the whole profile would take a request per 1,000 domains on every sync.

Related: [Rank tracking](rank-tracking.md), [SEO reports](seo-reports.md), [Configuration](configuration.md#settings-search-provider).
