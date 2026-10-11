# Excluded traffic

An exclusion is a set of filters for traffic you never want counted: a data center that hits the site all day, a scanner poking at `/wp-login.php`, your own office. Any visit that matches an exclusion is left out of every number the dashboard reads, until you ask to see it.

A filter answers a question you're asking right now and goes away when you clear it. An exclusion stays on until you turn it off.

## Make one

Settings, Excluded traffic, "New exclusion":

| Field | Notes |
|---|---|
| Name | So you can tell your exclusions apart. Must be unique. |
| Filters | One or more sets of filters. Each filter is one row, built and edited the same way as a segment's (see [Create a segment](filters-and-segments.md#create-a-segment)), so a list of networks or IP addresses can be pasted in whole. "Add a filter" inside a set adds a row to that set. "Add another set" under the last set starts a new one. "Remove set" takes a set away with everything in it. |
| On | Switch it off to keep the rule without hiding anything. |

"Check what this hides" counts the visits the filters match over the last 30 days, before you save anything.

The quicker way in is from the dashboard. Filter down to the traffic you want gone, open "Filter" and pick "Hide traffic like this...". The new exclusion form opens with your filters already in it.

## Which visits it hides

A visit is hidden when it matches any exclusion that's switched on. Inside one exclusion, it's hidden when it matches every filter in any one set. Inside one filter, more than one value works the way it does on a segment: "is" means any of them, "is not" means none of them.

Say "Scanners" has two sets:

- Entry page is `/wp-login.php` or `/xmlrpc.php`, and Country is not US
- Network contains AMAZON

That hides a visit that landed on either page from outside the US, and every visit from an Amazon network. A US visit to `/wp-login.php` from a home connection stays in. Two exclusions, one for each set, would hide exactly the same traffic. Use sets when the rules belong under one name.

Exclusions saved before sets existed are one set, and hide exactly what they did before.

- A visit-level filter, like Country or Browser, hides the visits that match it. A visit with nothing recorded for that dimension is never hidden by a positive filter on it. `Country contains X` never hides a visit with no country.
- An event-level filter, like Page or a custom property, hides every visit with at least one matching event. Crawler events count here, so a scanner is hidden whether or not your app tagged it as a crawler.
- Exit page and page group can't be used. A visit's exit page is worked out from the traffic that's left after exclusions, so excluding on it would go in a circle.

## What it reaches

Everything the dashboard reads out of your visits and events:

- the chart, the stat strip and every card, including their details and CSV exports
- Explore, saved questions and pinned questions
- funnels, the page journey and goal conversions
- the values in the filter dialog and the value search
- the weekly and monthly [traffic email](email-reports.md)
- traffic and goal [alerts](alerts.md)
- the realtime count
- the search to conversion [SEO report](seo-reports.md)
- [Ask](assistant.md), which is told which exclusions are on

Search Console numbers come from Google and aren't touched. The segment and exclusion forms list values from all your traffic, hidden visits included, so you can build a rule for traffic that's already hidden.

## Seeing it anyway

When anything is hidden, the toolbar says how many visits in the range, with "Show them" and "Manage". "Show them" turns hidden traffic back on for the view you're looking at. The command palette has the same switch as "Show hidden traffic". It's `internal=1` in the URL and it's remembered with the rest of your view.

Realtime ignores the switch and always leaves hidden traffic out.

## Internal addresses

Visits from your own network are hidden the same way, from the Internal addresses box on Settings, General. The default is the private and loopback ranges: `127.0.0.0/8`, `::1/128`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` and `fc00::/7`.

Add your office's public range to that list, one per line, or empty the box to count everything. "Use the defaults" under the form puts the list back. An entry that isn't an address or a range is refused when you save. The same "Show them" switch covers these and your exclusions together.

## Manage exclusions

Settings, Excluded traffic lists every exclusion with its rule, how many visits it hid in the last 30 days, and a button to switch it on or off. Edit with the gear, delete with the x. Deleting puts the visits it hid back into every number, history included, because nothing was ever removed. Exclusions are applied when the numbers are read, never when a visit is recorded.

An exclusion that names a dimension the dashboard doesn't have any more shows as "Not being applied" and hides nothing. Edit its filters and save to fix it, or delete it.

## Example: data center networks

If your app records each visit's network, register it as a dimension (see [Extending](extending.md)). Then open the Network card, find the hosting companies, and make one exclusion:

`Network contains AMAZON or GOOGLE or DIGITALOCEAN`

The network is usually recorded as the organization's name, not its number, and one company can show up under several names (`AMAZON-02`, `AMAZON-AES`). "Contains" catches all of them where "is" would need each spelled out.

Related: [Filters and segments](filters-and-segments.md), [Configuration](configuration.md), [Security and privacy](security-and-privacy.md).
