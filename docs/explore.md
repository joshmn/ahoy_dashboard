# Explore

Explore answers one question at a time: one number, broken down by one dimension, over a date range, with whatever filters you want. You can save a question and pin up to three of them to the dashboard.

Open it from "Explore" in the header, from the command palette, or from "Open in Explore" in any card's details. It starts from the range and filters you were already looking at.

## Build a question

The question at the top of the page reads as a sentence, something like "Unique visitors by page where Country is US over Last 30 days", and every part of it is a menu.

| Part | Picks | URL key |
|---|---|---|
| Measure | The number to chart and lead the table with. One of the seven dashboard metrics. | `metric` |
| by | The dimension to break down by. Defaults to Page. | `dimension` |
| where | Filters. Same menu and chips as the dashboard. | `filters[]` |
| over | The date range | `period`, `from`, `to` |
| by | The chart's grouping. Only shown when the range allows more than one. | `interval` |
| compared to | No comparison, Previous period or Year over year | `comparison` |
| Options, Columns | Which numbers the table shows | `columns` |
| Options, Traffic | "Include crawlers" puts crawler traffic back in. "Include hidden traffic" puts back what your [exclusions](excluded-traffic.md) and internal addresses hide. | `crawlers=1`, `internal=1` |

Options sits under the sentence on the right. When crawlers or hidden traffic are included, a line next to it says so, with a link to leave them out again. On a custom range, the range's own date and time fields sit on the same row.

Every menu item is a plain link, so all of this works with JavaScript off, and any question can be bookmarked or pasted into a chat.

The "by" menu lists every dimension you can filter by, plus Goal, plus the custom properties you've turned on, plus any your app registered. Page group isn't in the menu, but `dimension=page_group` works. A bad value falls back to Page rather than failing.

## Columns

The columns you can pick depend on the dimension.

| Dimension | Columns | Default |
|---|---|---|
| Goal | Unique visitors, Total conversions, Conversion rate, Revenue, Average revenue | Unique visitors, Total conversions, Conversion rate |
| Page | Unique visitors, Total visits, Total pageviews, Total conversions, Bounce rate, Visit duration, Scroll depth, Time on page | Unique visitors, Total pageviews, Bounce rate |
| Page format, Crawler, Rails controller, custom properties | Unique visitors, Total visits, Total pageviews, Total conversions, Bounce rate, Visit duration | Unique visitors, Total pageviews, Bounce rate |
| Everything else | Unique visitors, Total visits, Total pageviews, Bounce rate, Visit duration, Scroll depth, Time on page | Unique visitors, Total visits, Bounce rate, Visit duration |

Exit page doesn't offer Scroll depth or Time on page.

- The measure you picked comes first, when the dimension can answer it, so the table and the chart agree.
- `columns` in the URL is comma-separated keys: `columns=visitors,pageviews,bounce_rate`. See [Metrics](metrics-and-dimensions.md#metrics) for the keys. A column the dimension can't answer is dropped without a word.
- You can't turn off the last column.

Outside a Goal breakdown, "Total conversions" is every event with that value, page views and engagement events included. See [Total conversions](metrics-and-dimensions.md#total-conversions).

## The answer

Under the question:

- A chart of the measure over the range, with the comparison and [annotations](dashboard.md#annotations). You can't drag to zoom here.
- A table titled after the question, like "Unique visitors by page". 50 rows a page, with full numbers rather than short ones, and a pager at the bottom.

Click a row to add it as a filter. You stay in Explore with the same breakdown and columns, which is how you dig down one level at a time.

### Find a row

The "Find a page" box (the label follows the dimension) narrows the table to rows containing what you type, ignoring case. The numbers on each row don't change, and neither does the chart. It's in the URL as `q`, up to 100 characters.

### Download CSV

"Download CSV" saves the whole list, every row with no limit, for the current question.

- It respects the find box.
- Numbers are raw: no commas, no percent signs, durations in seconds.
- The file is `ahoy-dashboard-explore-<dimension>-<YYYY-MM-DD>.csv`, dated in the dashboard's time zone.
- The address is `/explore.csv` with the same query string as the page.

Explore reads your [remembered view](dashboard.md#remembered-view) when you open it with a bare URL, and never changes it.

## Saved questions

A saved question is a question with a name. It stores the question, not the answer, so opening it runs it again on today's data.

### Save a question

Press "Save" on Explore. Give it a name and, if you want it on the dashboard, tick "Pin it to the dashboard". Then "Save question".

The find box isn't saved.

### Manage saved questions

Settings, Saved queries lists them.

| Column | Shows |
|---|---|
| Name | Opens the question in Explore |
| Question | A one-line summary of the metric, the dimension and the date range |
| Pinned | "Pinned" or "Not pinned" |

The summary names the measure, the breakdown (left off for Page, the default), any filters, and the range. It doesn't mention grouping, comparison, crawlers or columns.

The arrows change the order, which is also the order pinned questions appear on the dashboard. The gear edits the name and the pin. The x deletes the saved question and nothing else.

To change the question itself, edit it and press "Change the question in Explore". Explore opens it with a "Save changes" button in place of "Save", and the button stays through the rest of the session: changing the measure, the breakdown, a filter, the range or anything else on the page doesn't turn it back into "Save".

## Pinned questions

Pinned questions are cards between the chart and the report cards on the dashboard. Up to 3 show, in the order on Settings, Saved queries. You can pin a fourth; it won't show.

Each card has:

- the question's name and summary
- the measure's value
- the change against the previous period
- a small chart of the last 30 points

Click a card to open the question in Explore.

A card is the measure for the question's own range and filters, as a single total. The breakdown and columns aren't used, so "Total pageviews by country" pins as total pageviews. The dashboard's date range doesn't change the cards. Each keeps its own. The change is always against the previous period, whatever comparison the question was saved with.

A question whose measure isn't one of the seven dashboard metrics is skipped. So is one that fails to run, and the failure is logged.

With nothing pinned the section doesn't show at all. Its "Manage in Explore" link goes to Settings, Saved queries.

Related: [Dashboard](dashboard.md), [Metrics and dimensions](metrics-and-dimensions.md), [Filters and segments](filters-and-segments.md).
