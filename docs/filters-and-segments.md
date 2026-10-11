# Filters and segments

A filter narrows every number on the dashboard to the traffic that matches it: `Country is US`, `Page contains /blog`, `Goal is Signed up`. Filters can be alternatives too: `Country is US or CA`. A segment is a named set of filters you can put on in one click. A page group folds many paths into one row on the Top pages card.

To keep traffic out of every number all the time, like a data center or your own office, use [Excluded traffic](excluded-traffic.md) instead of a filter.

## Add a filter

Every way in ends with the filter in the URL.

- Click a row on any card. It filters by that row's value.
- Press "Filter" in the toolbar, or `/` anywhere on the dashboard or Explore outside a text box. See [The filter dialog](#the-filter-dialog).
- Type a value into the command palette (Cmd+K or Ctrl+K). Matching values from your traffic show under the commands, and picking one filters by it.

Each filter shows in the toolbar as a chip, like "Country is US". The x removes it and "Clear filters" removes all of them. Clicking the value on a chip opens a form to change it.

Clicking a card row or a palette value on a dimension that already has an "is" filter replaces it. `Country is US` then clicking CA leaves you with `Country is CA`, because a visit can't be from both. To get both, pick them together in the filter dialog, or use the + after the chip.

Filters apply to the chart, the tiles, every card, the funnels, the page journey and goal conversions, and to the comparison period too. They aren't remembered between visits. See [Remembered view](dashboard.md#remembered-view).

### The filter dialog

"Filter" opens a dialog with a search box across the top, every dimension down the left, and results on the right. Nothing changes on the dashboard until you press "Apply filters", so you can build the whole question first.

The filters you already have sit in the search box as chips. Take one off with its x, or with Backspace in an empty box. Click the name on a chip to open its dimension again.

There are two ways to find a value:

- **Pick a dimension on the left.** You get its top 50 values in the range, most visitors first, each with its visitor count. Typing narrows the list. Tick as many as you like. You can also type the dimension's name and a colon, like `country:`, to get to the same place without the mouse.
- **Just type.** With no dimension picked, typing 2 or more characters searches every dimension at once and shows up to 5 matches from each, so you can find a page, a city or a referrer without knowing where it lives. "All" next to a dimension's results opens its full list.

Values you pick in one dimension go together as one "or" filter. Tick US and CA under Country and you get `Country is US or CA`. The left side counts how many values you've picked in each dimension.

Once you've picked a dimension, its match sits next to its name in the search box. It starts on "is", and you can switch it to "is not", "contains" or "does not contain" before you pick. With "is not" and "does not contain", each value is its own filter and they all have to hold, so `Browser is not Chrome` and `Browser is not Safari` leaves out both. When what you typed isn't one of the listed values, the top row offers to use it as typed. That's how you add a "contains" filter on part of a path.

"Add another filter" takes you back to the list of dimensions with everything you've picked still in the box. "Apply filters" (or Cmd+Enter, Ctrl+Enter) puts it all on the dashboard at once. "Clear all" empties the box. "Cancel" and Esc leave the dashboard as it was. Esc clears what you typed first, then backs out of the dimension, then closes.

The value list reads the traffic in the range under every filter in the box except the ones on that dimension. With `Country is US` in the box, the Country list still shows every country, so you can add CA to it. The search across every dimension reads every filter in the box.

Above the dimensions are your [segments](#segments), and, when filters are on, what you can do with them: "Save as a segment", "Hide traffic like this..." (see [Excluded traffic](excluded-traffic.md)), and "Open with these", which saves them as your default segment so the dashboard opens with them. When the filters on are that default, it reads "Stop opening with these" instead.

### Add to a filter with +

An "is" or "contains" filter on one dimension has a small + after its chips. It opens the filter dialog on that dimension, and whatever you tick joins the filter as another "or" value. `Country is US`, then + and CA, gives you `Country is US or CA`. Filters that can't take another value, like "is not" ones or a group that mixes dimensions, don't get a +.

Removing one chip from a group leaves the rest. Once a group is down to one filter, it's an ordinary filter again.

### Change a filter

Click the value on a chip. A form opens with that filter's operator and value filled in. Change either and press "Apply filter" to replace it.

The value box suggests up to 20 values as you type, but you can type anything. The suggestions come from the traffic you're filtered to, minus the filter you're changing, so changing `Country is US` suggests every country the rest of your filters leave.

Changing a filter that's part of an "or" group keeps it in the group.

To take a filter off, use the x on its chip.

## Operators

| Operator | URL key | Matches |
|---|---|---|
| is | `is` | Exactly the value. Case-sensitive. |
| is not | `is_not` | Anything but the value, including no value at all |
| contains | `contains` | The value anywhere in it, ignoring case |
| does not contain | `not_contains` | Anything without the value in it, including no value at all |

- In "contains" and "does not contain", `%` and `_` are plain characters, not wildcards.
- `Country is not US` includes visits with no country.
- The value "(not set)" means empty with "is" and "is not". `Country is (not set)` is visits with no country. With "contains" it's the literal text. You get it by clicking a card's "(not set)" row, or by typing it.
- There are no regex, starts-with, number or date operators.
- Values aren't trimmed. `US ` with a trailing space is a different value from `US`.

## How filters combine

Filters come in groups. A group holds if any one of its filters is true, and every group has to hold. So `(Country is US or CA) and Page is /pricing` is visits from either country that saw /pricing. A filter you added on its own is a group of one, which is why a set with no "or" in it reads the way it always has: every filter true at once.

There's one level of grouping. You can't put a group inside a group.

Two "is" filters on the same dimension in separate groups ask for a visit in both places at once, so the second one replaces the first. Inside a group, they're alternatives and both stay. Any other pair of filters on one dimension both apply, so `Page does not contain /admin` and `Page does not contain /api` together drop both.

Watch for "or" with a negative. `Country is not US or Country is not CA` is true of every visit, because a visit from the US isn't from Canada. The toolbar says so under a group like that. You nearly always want those two as separate groups, which ands them.

What a filter narrows depends on its dimension's [level](metrics-and-dimensions.md#dimensions).

- A visit-level filter (entry page, source, channel, UTM tags, location, browser, OS, device) keeps the visits that match.
- An event-level filter (page, page format, Rails controller, crawler, custom properties) keeps the visits that contain a matching event. Visitors, visits, bounce rate and visit duration count those whole visits. Total pageviews counts only the matching page views. `Page is /pricing` reads as "visits that saw /pricing" everywhere except pageviews, where it reads as "views of /pricing".
- A goal filter keeps the visits that completed the goal, and every page view in them still counts. `Goal is Signed up` plus `Page is /pricing` is visits that signed up and saw /pricing, in either order.
- An Exit page filter compares against each visit's real last page view. A visit with no page views has no exit page and drops out of any Exit page filter, "is not" included.

A group can mix levels. `Country is DE or Page is /pricing` keeps visits from Germany and visits that saw /pricing, and its pageview count is views from those German visits plus views of /pricing.

Event-level groups that aren't goals all have to be true of the same single event. That's intuitive for `Page is /a` plus `Rails controller is posts`: one page view that's both. It's less intuitive for negatives:

- `Page is not /pricing` doesn't mean "never saw /pricing". It means "had at least one event whose path isn't /pricing", and an event with no path at all counts. That's nearly every visit.
- `Goal is not Signed up` works the same way, so it's nearly every visit too.
- `Page contains blog` plus `Page contains 2026` needs one path with both in it. Put them in one group, `Page contains blog or 2026`, and it's any path with either.

To find visits that never did something, there isn't a filter for it. Compare the unfiltered number with the "is" number instead.

## Filters in the URL

Filters are an array in the query string:

```
?period=30d&filters[][dimension]=country&filters[][operator]=is&filters[][value]=US&filters[][dimension]=page&filters[][operator]=contains&filters[][value]=/blog
```

- Keep each filter's keys together in `dimension`, `operator`, `value` order. Rails starts a new filter every time a key repeats.
- Filters that share a `group` number are one "or" group. Put `group` last in the filter:

  ```
  filters[][dimension]=country&filters[][operator]=is&filters[][value]=US&filters[][group]=0&filters[][dimension]=country&filters[][operator]=is&filters[][value]=CA&filters[][group]=0
  ```

  A filter with no `group` is a group of its own. The number only has to match the other filters in the same group. The dashboard writes groups of one with no number and numbers the rest by position, so every link made before groups existed still works and means the same thing. A `group` that isn't a whole number is ignored and the filter stands alone.
- A missing operator is `is`. An operator that isn't one of the four becomes `is`.
- A filter with an unknown dimension or a blank value is dropped.
- A custom property works as `prop:<key>`, whether or not it's turned on in settings, as long as the key is up to 255 characters, with no line breaks or tabs.
- Anything malformed is ignored rather than raising. The worst a bad link does is show everything.

## Value search

Typing in the filter dialog with no dimension picked, or typing in the command palette, searches every dimension at once. Type at least 2 characters.

- It matches anywhere in the value, ignoring case.
- It searches every dimension except Goal, Crawler, Page group and Browsed.
- It shows up to 5 values per dimension, most visitors first, and says when there are more.
- It only searches the range and filters you're looking at. In the dialog, that's the filters in its search box.
- Results are cached for 2 minutes.

In the dialog, picking a value adds it to the box as an "is" filter. In the palette, picking one applies it straight away.

## Crawlers as a filter

The Crawler dimension only has values when crawlers are shown. With crawlers hidden (the default), a Crawler filter matches nothing. Turn on "Show crawlers" in the command palette first.

## Segments

A segment is a saved set of filters with a name, like "Organic blog readers". Picking one applies its filters. Nothing is stored per visitor and nothing is worked out ahead of time, so a segment made today covers your whole history, same as filtering by hand.

### Use a segment

Open "Filter". Your segments are listed at the top of the left side. Picking one replaces every filter you have on with the segment's filters and keeps the date range, metric, grouping and comparison. The segment that matches the current filters exactly is highlighted.

Once picked, a segment is just filters in the URL. Changing or deleting the segment later doesn't touch links and bookmarks made from it.

### Create a segment

With filters on, open "Filter" and pick "Save as a segment". The new segment form opens with them filled in.

Or go to Settings, Segments, "New segment":

| Field | Notes |
|---|---|
| Name | Shown in the filter dialog. Must be unique. |
| Filters | One row per filter: its dimension, how it matches, and its values. "Add a filter" adds a row. A row shows its first three values and how many more there are. Hover over them for the whole list. The x at the far right removes the row. |

A visit has to match every row. Inside a row, more than one value works the way you'd say it out loud:

- `Country is US or CA` matches a visit from either country.
- `Network contains AMAZON or GOOGLE` matches a network name with either word in it.
- `Browser is not Chrome or Safari` leaves out both browsers. It's saved as two filters that both have to hold.
- `Page does not contain /wp- or /xmlrpc` leaves out every page with either one in it.

Changing a row's match from "is" to "is not" changes what its values mean along with it. You need at least one filter. A segment with none would be every visit on the site.

Click a row's values to edit them. They open in a text box under the row, one value per line, so a list from a spreadsheet or a log goes in with one paste. Long paths show in full there. "Done" drops blank lines and repeats and folds the row back up. "Cancel" puts back what was there. Emptying the box and pressing "Done" removes the row. The box is a normal form field, so typing, pasting and "Done" work with JavaScript off.

"Pick from your traffic", next to the box, opens the filter dialog on that row's dimension. Values already in the row are ticked. Tick more, untick the ones you don't want, and press "Add to the form" to write them into the row. Typing narrows the list, and typing a value that isn't listed offers to use it as typed. You can change the match there too. Untick everything and the row goes away.

"Add a filter" opens the same dialog with every dimension to pick from. Each value you pick lands in the row for its dimension and match, or starts one if there isn't one yet.

Either way, the dialog lists values from all your traffic, whatever the page you opened the form from was filtered to.

A group built on the dashboard that mixes dimensions, like `Country is US or Page is /pricing`, shows as one row you can remove but not edit. It saves exactly as it was.

### Manage segments

Settings, Segments lists them in order, with their filters, state and dates. The arrows change the order they appear in the filter dialog, and nothing else. Edit with the gear, delete with the x. Deleting only removes the saved filters.

### Segments that stop working

A segment stops working when one of its filters names a dimension the dashboard doesn't have any more, like one your app used to register and doesn't now. It stays in the filter dialog, greyed out, as "Not being applied". Settings shows it as "Not being applied" too. Edit its filters and save to fix it, or delete it.

A segment isn't checked for filters that match nothing. One filtering on a goal you renamed, or a page group you deleted, keeps working and matches nothing. A custom property you turned off keeps working fine.

## Page groups

A page group folds a set of paths into one row on the Top pages card: every `/blog/*` post as "Blog", every product page as "Products". Paths are never rewritten when they're recorded. The grouping happens when the card is read, so a rule you write today covers your whole history, and deleting it puts the paths back exactly as they were.

### Where page groups show

Only on the Top pages card: open Top pages, then "Break down by", then "Grouped". The same breakdown is in its details and its CSV. The default breakdown, Path, doesn't change.

A visitor who read three blog posts counts once for Blog.

Page groups don't apply to the filter dialog, the value search, Explore or the [page journey](page-journey.md). Clicking a Grouped row does add a `Page group is Blog` filter, which works, but its chip can't be edited. Remove it with the x.

The breakdown you pick isn't in the URL, so reloading puts the card back on Path.

### Create a page group

Settings, Page groups, "New group":

| Field | Notes |
|---|---|
| Group name | The row's label, like "Blog". Must be unique. |
| Path pattern | One or more patterns separated by commas, like `/blog/*, /changelog/*` |

As you type, "Pages it groups" checks the patterns against the 100 most visited paths of the last 30 days and lists up to 8 matches. It tests this one rule on its own, so it won't tell you when an earlier rule would get to a path first.

### Pattern syntax

- A pattern ending in `*` matches every path that starts with the rest. `/blog/*` matches `/blog/`, `/blog/a` and `/blog/a/b`, and doesn't match `/blog`.
- Any other pattern matches that exact path.
- A `*` anywhere else is a literal star. It isn't a glob.
- A bare `*` matches nothing.
- `%`, `_` and `\` are literal.
- Matching is case-sensitive, against the `path` your app recorded. Trailing slashes and query strings aren't cleaned up.
- Up to 20 patterns per group. Past 20, the rest are dropped without a warning.

To catch `/blog` and everything under it, use `/blog, /blog/*`.

### Order

Groups are tried top to bottom and the first match wins. Use the arrows on Settings, Page groups to change the order. A path that matches nothing shows as itself. There's no "Other" row.

Goal paths use the same `*` idea with different rules. See [Goals and funnels](goals-and-funnels.md#pageview-goals).

## Without JavaScript

With JavaScript off you can still remove chips, clear filters, change a filter from its chip (the form opens as a page) and follow any filtered link. "Filter" opens the filter dialog as a page of its own, with the same dimensions, segments and search. Picking a value there applies it straight away as an "is" filter, one value per trip. Segments, page groups and annotations can all be created and edited in Settings, but adding a filter to a segment needs the filter dialog, which needs JavaScript there.

Related: [Excluded traffic](excluded-traffic.md), [Metrics and dimensions](metrics-and-dimensions.md), [Dashboard](dashboard.md), [Explore](explore.md).
