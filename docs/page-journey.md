# Page journey

The page journey shows where visitors went next, one page at a time. Pick a page and the next column lists the pages viewed right after it, plus how many visitors left the site there.

It's the "Page journey" section under the cards on the dashboard. It uses the dashboard's date range and filters. It's also its own page at `/journey`, which nothing links to.

## Read the journey

The journey is up to six columns wide.

1. The first column lists every page viewed in the range, most visitors first.
2. Click a page. The next column lists the pages viewed immediately after it, and "Exited site" for visitors who left from it.
3. Keep clicking, up to six columns. Click a picked row again to step back to it, or "Start over" to clear the whole path.

The first column is headed "Every page viewed": every page anyone viewed in the range, from any point in their visit.

Each row shows:

- the page, or "Exited site"
- a count of unique visitors, shortened (hover for the exact number)
- a percentage: the row's visitors out of the visitors who got to this column
- a bar, scaled against the biggest row in the column

One visitor can show up in more than one row. Someone who went from /pricing to /signup on Monday and left from /pricing on Friday is in both rows, so a column can add up to more than 100%.

The line above the columns shows the path you've picked (the last three pages, when there are more) and how many visitors got that far.

## Find a page in a column

Each column shows its top 9 rows, and says nothing when there are more. The "Find a page" box above a column narrows it to paths containing what you type, ignoring case. The percentages and the exit row don't change. Searching is the only way to reach a page outside a column's top 9.

The search boxes are plain forms and work without JavaScript.

## How the journey counts

- It reads `page_view` events and their `path`. Every other event is ignored, and none of them break the chain.
- A page viewed twice in a row counts once. A refresh or a back-and-forward isn't a step. Coming back to the page later is.
- A page you pick is followed from every place it shows up in a visit, not only from the start. Picking /pricing then /signup counts a visit that went /, /about, /pricing, /signup.
- "Exited site" counts visitors whose last page view in the visit was the page before it.
- Paths are compared exactly and case-sensitive. [Page groups](filters-and-segments.md#page-groups) don't apply.
- Filters pick which visits count, and then the whole visit is read.
- Crawlers are left out unless they're shown.
- Nothing is stored or cached. Each column is one query, so a path five pages deep costs six.

## Journey URL

The path you picked is in the URL, so a journey can be linked to:

```
/journey?period=30d&steps[]=/pricing&steps[]=/signup
```

| Key | Holds |
|---|---|
| `steps[]` | The picked pages, in order. Up to 5, each starting with `/`, up to 512 characters. `__exit__` is the "Exited site" row and ends the path. |
| `find[]` | Each column's search, in column order. Up to 6. |

The path stops at the first step that isn't a path, and anything after `__exit__` is dropped.

Related: [Dashboard](dashboard.md), [Goals and funnels](goals-and-funnels.md#funnels), [Metrics and dimensions](metrics-and-dimensions.md#dimensions).
