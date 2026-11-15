# Visitor journey

The visitor journey shows one person's history: every visit they made, in order, and every event inside each visit. It answers "how did this person find us, and what did they do before and after they signed in?"

The [page journey](page-journey.md) adds everyone up. This screen is one person at a time.

## Get to it

- "Visitors" in the dashboard's toolbar, or "Visitors" in the command palette. Both carry the dashboard's date range and filters.
- A link from your own app. See [Link from your app](#link-from-your-app).

## The visitor list

`/visitors` lists everyone with a visit in the date range, most recent visit first, 50 to a page.

Each row shows:

- the visitor: their name from your [user labels](#show-who-a-user-is) when one of their visits has a `user_id`, or the start of their `visitor_token`
- when their last visit in the range started
- how many visits they made in the range
- the source and entry page of their first visit in the range
- where their last visit came from

"Everyone" and "Signed in" switch between every visitor and only the ones with a `user_id` on at least one visit in the range. "Signed in" only shows when `ahoy_visits` has a `user_id` column.

The list follows the dashboard: its date range, its filters and [excluded traffic](excluded-traffic.md). A visitor shows up if any of their visits matches, and the counts, sources and entry pages only read the visits that match. The list is cached for 30 seconds, like the cards.

### Find one person

The box above the list takes a visit token, a visitor token or a user id, tried in that order, and opens what it finds. It ignores the date range. Nothing found sends you back to the list.

## One visitor

`/visitors/<visitor_token>` shows every visit with that `visitor_token`, oldest first, from any date. The date range and filters don't apply here.

At the top:

| Tile | Shows |
|---|---|
| Visits | Visits shown, across every page |
| Events | Events in those visits |
| First visit | When the first one started |
| Last visit | When the last one started |
| Identified | When a `user_id` first shows up. Click it to jump there. "Never" if none did. |

Under the tiles are the users this visitor signed in as, each linking to that user's journey.

Each visit is a card, headed with when it started and how long after the visit before it. Under the heading:

- Source: `referring_domain`, or "Direct" when there's neither a referring domain nor a `utm_source`
- Referrer: the full `referrer`
- Campaign: `utm_source`, `utm_medium`, `utm_campaign`, `utm_term` and `utm_content`, the ones that are set
- Landed on: the full `landing_page`
- Device: `browser`, `os`, `os_version` and `device_type`
- Platform: `platform`, when the column exists
- Location: `city`, `region` and `country`
- User: the visit's `user_id`, when it has one
- Visit token: the `visit_token`

Anything blank is left out.

Below that are the visit's events in time order. A page view shows its `path`. Any other event shows its name. The details column lists every property, except `path` on a page view. The "After" column is the time since the event before it, or since the visit started for the first one.

## One user

`/visitors/users/<user_id>` is the same screen for a user. It merges:

- every visit with that `user_id`
- every visit holding an event with that `user_id`
- every visit sharing a `visitor_token` with any of those

Visits from all of those are listed together, oldest first. So the anonymous visits on someone's laptop before they signed up are there, next to the visits from their phone after they signed in on it.

It only follows tokens one step. If a token was shared with somebody else, like a family computer, their visits come along too, and their own `user_id` shows on those visits. Their other tokens don't.

The user's tokens are listed under the tiles, each linking to that visitor on its own.

## Where they were identified

The identified point is the first event with the `user_id` on it. The event gets an "Identified" badge, and so does the tile at the top.

ahoy sets the visit's `user_id` when someone signs in, and later events in that visit carry it too. Events from before the sign in don't. When no event carries the `user_id`, the first visit with it gets the badge instead, on its heading.

On a visitor's page, it's the first `user_id` of any kind.

## Long histories

A page shows 20 visits. Older visits are on the first page, newer ones on the last. Use Previous and Next to move through them, or the Identified tile to jump to the page where they signed in.

A visit shows its first 200 events. A visit with more says how many it has, and the rest aren't shown.

A person's screen reads their first 10,000 visits, and a user's first 500 visitor tokens. Anything past that isn't shown or counted. You'll only hit it with a token that's shared by a lot of traffic, like a bot that sends the same cookie every time.

## Hidden traffic

The screen leaves out what the dashboard leaves out: visits matching an [exclusion](excluded-traffic.md), [internal addresses](excluded-traffic.md#internal-addresses), [known crawlers](excluded-traffic.md#known-crawlers) when that's on, and [crawler events](tracking.md#crawlers). A visit with nothing but crawler events is dropped.

When anything is left out, the screen says how many visits, with "Show them". That turns on hidden traffic and crawlers together. It's `crawlers=1&internal=1` in the URL, and "Hide hidden traffic" takes both off again. A view you've remembered on the dashboard with either one on carries over.

## Link from your app

The URLs are stable, so your app can link to them, like from an admin page about a user:

| URL | Opens |
|---|---|
| `/visitors/users/<user_id>` | Everything for that user |
| `/visitors/<visitor_token>` | One visitor |
| `/visitors/visits/<visit_token>` | The visitor that visit belongs to, on the page with that visit, scrolled to it |
| `/visitors` | The visitor list |

Each is under your mount path, so `/analytics-dashboard/visitors/users/42` with the default mount. Build them with the engine's route helpers:

```ruby
AhoyDashboard.routes.visitors_user_path(user.id)
AhoyDashboard.routes.visitor_path(visit.visitor_token)
AhoyDashboard.routes.visitors_visit_path(visit.visit_token)
AhoyDashboard.routes.visitors_path
```

From inside one of your own views, the engine's mount helper works too: `ahoy_dashboard.visitors_user_path(user.id)`. With a [site context](extending.md#site-contexts), call `AhoyDashboard.routes` inside `AhoyDashboard::Context.with`.

A visit token whose visit is hidden opens with hidden traffic shown, so the link always lands on it. An unknown token or user id is a 404, and so is anything the person clicking isn't [allowed to read](extending.md#hosting-the-dashboard-in-a-separate-app).

## Show who a user is

A `user_id` shows as "User 42" until you tell the dashboard who that is. Register a [value label](extending.md#value-labels) for the key `user_id`:

```ruby
Rails.application.config.to_prepare do
  AhoyDashboard::ValueLabels.register("user_id") do |ids|
    User.where(id: ids.grep(/\A\d+\z/)).pluck(:id, :email)
  end
end
```

It's called once per page with every user id on it, as strings, and works the same way as every other value label. The labels show on the visitor list, the user's title, each visit and the links between them. URLs always use the raw id.

The same label is used if you also register a `user_id` [dimension](extending.md#dimensions) for the cards.

## What it needs

- `visitor_token` and `started_at` on `ahoy_visits`, and the columns listed in [Tracking](tracking.md#visits). Anything missing is left out of the card.
- `user_id` on `ahoy_visits` for the user screen, the identified point and "Signed in". Without it, user links are 404s.
- `user_id` on `ahoy_events` to mark the identified event. Without it, the identified point is always a visit.
- `visit_token` on `ahoy_visits` for visit links.

ahoy's generator adds all of these, and an index on `ahoy_visits (visitor_token, started_at)`, `ahoy_visits (user_id)`, `ahoy_events (visit_id)` and `ahoy_events (user_id)`. Each screen reads through those indexes. If your tables were made some other way, add them, or each screen reads the whole table.

The visitor, user and visit screens aren't stored or cached. Each page is a handful of queries.

Related: [Page journey](page-journey.md), [Excluded traffic](excluded-traffic.md), [Tracking](tracking.md), [Extending](extending.md#value-labels).
