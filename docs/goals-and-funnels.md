# Goals and funnels

A goal counts a conversion: a custom event your app records, like `Signed up`, or a view of a page, like `/thanks`. A funnel puts goals in order and shows how many visitors got through each step in one visit.

Goals and funnels are definitions, not recordings. Nothing is stored per goal. A new goal reads every matching event already in the data the moment you save it, and editing one changes its whole history.

The [goal alert rules](alerts.md#goal-rules) can tell you when a goal stops converting or its conversions fall.

## Create a goal

Settings, Goals, "New goal":

| Field | Notes |
|---|---|
| What counts | "Custom event" (the default) or "Pageview" |
| Event name | Custom event goals. The event's name, exactly as your app records it. |
| Path | Pageview goals. Starts with `/`. `*` is a wildcard. |
| Property | Optional. Only count events carrying this property... |
| Value | ...with exactly this value |
| Display name | Optional. Defaults to the event name or path. |
| Revenue | "No revenue", or a currency to total the `revenue` property. See [Revenue](#revenue). |

The search buttons next to Event name, Path and Property open a picker of what's actually in your data: event names your app sends (most common first, `page_view` left out), paths, and property keys.

### Custom event goals

A custom event goal counts events whose `name` is exactly the event name. The match is case-sensitive, so `Signed up` and `signed up` are two different goals. Record the event from your app:

```ruby
ahoy.track "Signed up", plan: "pro"
```

Avoid a goal on `engagement` or `scroll_milestone`. Those fire on every page view, so the goal would count page views.

### Pageview goals

A pageview goal counts `page_view` events whose `path` property matches the pattern.

- `*` matches anything, anywhere in the pattern: `/blog/*`, `/docs/*/install`.
- Everything else matches exactly. `%`, `_` and `\` are plain characters.
- The pattern matches the whole path, case-sensitive. `/pricing` matches `/pricing` and not `/pricing/` or `/Pricing`. Use `/pricing*` for anything that starts with it.
- The path is whatever your app put in the `path` property. If it includes query strings, so does the match.

This is a different syntax from [page groups](filters-and-segments.md#pattern-syntax), where `*` only works at the end.

### Narrow a goal by a property

Set Property and Value to only count events where that property has that value: `Signed up` where `plan` is `pro`. It's an exact text match. A JSON number `12` matches the value `12`.

Unnamed, that goal is called `Signed up (plan: pro)`.

### Goal names

Every goal has a name: its display name, or the event name, or the path. Names are unique, because filters, Explore and saved questions find goals by name.

That has a cost. Rename a goal and any link, segment or saved question filtering on the old name matches nothing.

Two goals can't count exactly the same thing. Saving a duplicate gets "A goal already counts exactly this. Give that one a different name instead of adding a second copy, or the same conversion gets counted twice."

### Goal order

Each event counts for the first goal in the list that matches it. That only matters when goals overlap, and when they do, it matters a lot.

Say `Signed up` is first and `Signed up (plan: pro)` is second. Every pro signup matches `Signed up` first, so the pro goal reads 0 in goal conversions, and a filter on it matches nothing. Put the narrow goal above the broad one: pro signups count as pro, and the rest count as `Signed up`.

Change the order with the arrows on Settings, Goals. The order doesn't change how goal conversions are sorted. [Funnels](#funnels) don't use this rule.

### Delete a goal

The x on Settings, Goals deletes it after asking. The events stay in `ahoy_events`, but the goal's numbers disappear from every report until you make the goal again.

A goal that's a step in a funnel can't be deleted. Take it out of the funnel first.

## Goal conversions

The Goal conversions section, at the bottom of the dashboard, lists goals for the range and filters.

| Column | Counts |
|---|---|
| Goal | The goal's name, with its revenue beside it when it has a currency |
| Visitors | Unique visitors who completed it |
| Conversions | Events that completed it. One visitor converting twice is 2. |
| Rate | Visitors divided by all unique visitors in the range and filters, times 100, to one decimal |

- Every goal gets a row, even at zero. A goal that never fires is worth knowing about.
- It shows the top 9 by visitors, then conversions, then name. Your list order doesn't sort it. To see the rest, use Explore broken down by Goal, the "Behaviours as CSV" export in the command palette, or Settings, Goals.
- The bar is a share of the busiest goal.
- Click a goal to filter the dashboard by it. Click it again to take the filter off.
- With no goals, it says "Add a goal to get started".

Settings, Goals shows the same numbers for every goal. Its Conversions column is the unique visitor count, the one the dashboard calls Visitors.

With `Goal is Signed up` on, only that goal's events are left, so it reads 100% and every other goal reads 0. That's the filter doing its job.

A page filter works the other way round: `Page is /pricing` shows the goals completed by visits that saw /pricing, whatever page they converted on.

## Revenue

Pick a currency under Revenue, and the goal totals the `revenue` property on its events. USD is the only currency, and it only switches revenue on. It doesn't convert anything.

```ruby
ahoy.track "Purchased", revenue: 49.99
```

- `revenue` has to be a plain number: `12`, `12.50`, `-3`. Strings like `"$12"`, `"1,200"`, `".5"` or `"1e3"` are skipped without an error.
- Revenue is the sum, to 2 decimals.
- Average revenue is revenue divided by every completion, including completions with no `revenue` on them. Leave `revenue` off some events and the average drops.

Revenue shows as dollars in Explore when you break down by Goal ("Revenue" and "Average revenue"), in the goals CSV, and beside the goal's name in goal conversions.

## Funnels

A funnel is two or more goals in order: land on pricing, start a trial, sign up. Its card shows how many visitors reached each step and where the rest dropped off.

### Create a funnel

You need at least two goals first. Settings, Funnels, "New funnel":

| Field | Notes |
|---|---|
| Name | Shown on the card. Must be unique. |
| Steps | One goal per step, in order. "Add a step" adds a slot, and the delete button beside a step removes it. |

A funnel needs at least 2 steps and can't use the same goal twice. It reports on everything already collected as soon as you save it.

The dashboard previews the first four funnels. When more are configured, **View all funnels** opens the complete list, four cards per page, keeping your selected date range and filters. The same link is available in Settings, Funnels. The arrows on Settings, Funnels change the card order. On a funnel's edit page, the arrows next to its steps change the step order, and they save immediately. Step order changes what's counted, so that one isn't cosmetic.

Deleting a funnel leaves its goals alone.

### How a funnel counts

A funnel is counted one visit at a time.

1. Step 1 is reached the first time the visit completes the first goal.
2. Step 2 is reached the first time the visit completes the second goal at or after step 1.
3. And so on. Miss a step and the steps after it can't be reached in that visit.

A visitor counts at a step when any one of their visits reached it. Visits are never joined together, so someone who starts a trial today and signs up tomorrow stops at the trial step. How long a visit lasts is up to ahoy (`Ahoy.visit_duration`). There's no conversion window setting and no time-between-steps number.

- Other events in between don't matter. Only the order of the goals does.
- "At or after" includes the same moment. If one event matches two steps, it completes both.
- An event can count for more than one step. Funnels ignore the first-match rule that goal conversions use, so a funnel can show conversions for a goal that reads 0 in goal conversions.
- Filters pick which visits count. They don't hide events inside those visits.

### Funnel numbers

| Card column | Details | Counts |
|---|---|---|
| Visitors | Visitors | Unique visitors who reached the step |
| Share of step one | Share of step one | The step's visitors divided by step 1's, to one decimal |
| Lost since the step before | Lost since the step before | The previous step's visitors minus this step's |
| | Share lost since the step before | Lost divided by the previous step's visitors, to one decimal |

Step 1 is always 100% and has no loss. The bars are scaled against step 1, so the top bar is always full.

"Details" on the card opens the whole funnel: each step's bar, the share that continued and dropped off between steps, and a last line like "10 of 40 went the whole way, 25.0%."

With 7, 3 and 1 visitors at three steps, the shares of step one are 100.0%, 42.9% and 14.3%, the losses are 4 and 2, and the loss shares are 57.1% and 66.7%.

A funnel nobody entered says "Nobody reached the first step".

`/funnels/<id>.json` returns the same numbers, formatted as strings.

Related: [Tracking](tracking.md), [Explore](explore.md), [Filters and segments](filters-and-segments.md), [Custom properties](custom-properties.md).
