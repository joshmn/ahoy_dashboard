# Custom properties

Custom properties are the extra keys your app puts on events, like `plan`, `author` or `locale`. Turn one on in Settings and you can filter by it and break traffic down by it.

```ruby
ahoy.track "Signed up", plan: "pro", source_page: "/pricing"
```

## Turning a property on

Settings, Custom properties is a list of the properties you want offered in the menus. It doesn't decide what gets recorded. Every event keeps every property your app sends, whether it's on the list or not, so adding a key to the list today works on last year's events too.

A property that's on the list and shown:

- appears in the filter dialog under Behaviour, and in the "Property" filter form
- appears in Explore's "Break down by" menu
- comes first in the goal form's property picker

A property marked "Not shown" drops out of those and keeps its row. Any property works in a URL either way, as `prop:<key>`, as long as the key is up to 255 characters, with no line breaks or tabs:

```
/explore?dimension=prop:plan
?filters[][dimension]=prop:plan&filters[][operator]=is&filters[][value]=pro
```

## Add a property

"Found in your data" lists up to 30 keys from events in the current range that aren't on your list yet, most used first. Press "Add" on one.

Or type one into "Add a property":

| Field | Notes |
|---|---|
| Key | Spelled exactly as on the event, capitals included. Up to 255 characters, with no line breaks or tabs. |
| Name | Optional. Defaults to a tidied-up version of the key, so `facility_id` becomes "Facility". |

The standard page view keys (`controller`, `action`, `path`, `format`, `crawler`) are never offered, because they're dimensions already. Engagement keys (`scroll_depth`, `engagement_time`, `depth`) and anything your app records on clicks will turn up in "Found in your data" if your app sends them. Leave those off the list unless you want them in the menus.

The key is saved exactly as typed, capitals and all. A property already on the list from before keys kept their capitals may still show a lowercased one, and there's no way to fix that automatically; delete it and add it again from "Found in your data" to get the real spelling.

## Show, hide, order and delete

Each row on Settings, Custom properties has:

- a toggle between "Shown" and "Not shown"
- arrows to change the order
- an x to delete it from the list, after a confirm

Deleting takes the key off the list. The events keep their properties.

The Name you give a property only shows on this screen. The filter dialog, the filter chips and Explore all show the raw key.

## Break down by a property

In [Explore](explore.md), pick the property under "Break down by". Each row is one value of that property.

| Column | Counts |
|---|---|
| Unique visitors | Visitors with any event carrying that value |
| Total visits | Visits with any event carrying that value |
| Total pageviews | `page_view` events carrying that value |
| Total conversions | Every event carrying that value |
| Bounce rate | Over the visits with an event carrying that value |
| Visit duration | Over the visits with an event carrying that value |

Scroll depth and Time on page aren't offered for properties.

Events without the key are skipped, so there's no "(not set)" row. Values are compared as text. A number `12` and a string `"12"` are the same row.

To show names instead of ids (a user id as the user's name, say), register a value label. See [Extending](extending.md#value-labels).

## Filter by a property

A property filter is event-level: it keeps the visits with at least one event carrying the value, and counts those whole visits. `prop:plan is pro` is every visit that recorded a pro event anywhere in it. See [How filters combine](filters-and-segments.md#how-filters-combine).

## Custom properties report

There's a report card for properties that isn't on the dashboard. Open `/reports/behaviours?tab=properties` to see it, with a picker for the property. It opens on the first property that's shown, in list order, which is the only thing the order on Settings affects. With nothing shown, it opens on whichever key shows up most in the range's events instead. With no custom properties in the range at all, the card says "No custom properties in this range" and links to Custom properties settings, and its CSV export comes back with only the header row. `/exports/behaviours?tab=properties&property=<key>` downloads it as a CSV.

Related: [Tracking](tracking.md), [Explore](explore.md), [Goals and funnels](goals-and-funnels.md#narrow-a-goal-by-a-property).
