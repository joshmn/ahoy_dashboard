# Tracking

The dashboard reads what ahoy_matey recorded. It ships no tracking script and records nothing itself, so every number on it comes down to what your app sends. On this page is which events, which properties, which columns.

## Page views

Pageviews, the page cards, entry and exit pages, bounce rate, the page journey, realtime and pageview goals all read events named `page_view` with a `path` property.

```ruby
class ApplicationController < ActionController::Base
  after_action :track_page_view, if: -> { request.get? && request.format.html? }

  private

  def track_page_view
    ahoy.track "page_view", path: request.path, controller: controller_name, action: action_name
  end
end
```

- The name has to be exactly `page_view`. ahoy.js's `ahoy.trackView()` records `$view`, which the dashboard doesn't read. An app that only sends `$view` sees zero pageviews and empty page cards.
- `path` is the path as you want it grouped: `/pricing`, not `https://example.com/pricing?ref=x`. Whatever you put there is what pages, goals, page groups and the journey match against. Leave query strings out unless you want every variation as its own page.
- Track from the server or the browser, as long as the event lands in `ahoy_events` with its visit.

Optional properties on page views:

| Property | Feeds |
|---|---|
| `controller` | The "Rails controller" breakdown on Top pages, and the Rails controller filter |
| `format` | The Page format filter and breakdown |
| `crawler` | Marks the event as a crawler. See [Crawlers](#crawlers). |
| Anything else | A [custom property](custom-properties.md) |

`action` is recorded by plenty of apps and is ignored.

## Custom events

Any other event name is a custom event. Custom events drive [goals](goals-and-funnels.md#custom-event-goals), and their properties are [custom properties](custom-properties.md).

```ruby
ahoy.track "Signed up", plan: "pro"
ahoy.track "Purchased", revenue: 49.99
```

- Goals match the name exactly, case included.
- Property keys can be up to 255 characters, with no line breaks or tabs. Capitals, dashes, dots and spaces all work.
- `revenue` is read by goals with a currency. It has to be a plain number: `49.99`, not `"$49.99"`. See [Revenue](goals-and-funnels.md#revenue).

## Scroll depth and time on page

Scroll depth and Time on page read two events your app has to send from the browser. The dashboard doesn't include a script for them. Without them, Scroll depth reads 0% and Time on page reads 0s everywhere.

These are specific to AhoyDashboard, and not shipped with the regular ahoy.js.

| Event | When | Properties |
|---|---|---|
| `engagement` | Once per page view, when the page is left | `path`, `scroll_depth` (0 to 100), `engagement_time` (whole seconds) |
| `scroll_milestone` | Once per page view each time 25%, 50%, 75% and 100% is first passed | `path`, `depth` (25, 50, 75 or 100) |

What the dashboard needs from them:

- At most one `engagement` event per page view. The averages count one event as one page view.
- `path` exactly equal to the `path` on that page's `page_view`, or per-page numbers won't line up.
- `scroll_depth` as a number from 0 to 100, the furthest the reader got. Values over 100 count as 100, and negatives as 0. A page too short to scroll should report 100.
- `engagement_time` as the seconds the page was visible, not the seconds it was open in a background tab.
- Send `engagement` when the page is hidden or left (`pagehide`, or before a Turbo visit), with `navigator.sendBeacon` or a `keepalive` fetch so it survives the page going away. A normal queued request is often lost at that moment.
- No `crawler` property, or the events are dropped with the crawlers.

`engagement` events count as the last event of a visit, so they give a one-page visit a real [Visit duration](metrics-and-dimensions.md#visit-duration) where it would otherwise be 0.

`scroll_milestone` events are counted, but no screen shows the breakdown of where people stop yet. Send them anyway if you want the history.

Keep these two out of your goals. They fire on every page view.

## Crawlers

Every event with a `crawler` property that isn't null is treated as a crawler: left out of every number by default, and shown with "Show crawlers" in the command palette. A visit with nothing but crawler events is dropped.

ahoy already skips known bots unless you set `Ahoy.track_bots = true`, so with ahoy's defaults you mostly don't need this. To hide visits by user agent without tagging anything, turn on [Hide known crawlers](excluded-traffic.md#known-crawlers). The `crawler` property is for apps that record bots on purpose and want them kept apart:

```ruby
ahoy.track "page_view", path: request.path, crawler: "Googlebot"
```

The value can be anything. It shows up in the Crawler dimension.

## Visits

These `ahoy_visits` columns are read. A visit without one of them shows "(not set)" for that dimension. A table missing the column breaks the cards that use it.

| Column | Feeds |
|---|---|
| `id`, `visitor_token`, `started_at` | Everything. A visitor is a `visitor_token`. |
| `landing_page` | Entry page, Entry URL, Entry hostname |
| `referrer`, `referring_domain` | Source, Referrer URL, Channel, site icons |
| `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`, `utm_content` | The UTM tabs, Source, Channel |
| `country`, `region`, `city` | Locations |
| `browser`, `os`, `os_version`, `device_type` | Devices |
| `user_agent` | [Hide known crawlers](excluded-traffic.md#known-crawlers), when it's on. Without the column that switch does nothing, and nothing else breaks. |

A `country` stored as a two-letter code (`US`) shows as a name with a flag. Anything else prints as stored, without a flag.

Never read: `visit_token`, `user_id`, `ip`, `user_agent`, `latitude`, `longitude`, `app_version` and `platform`. Your app can still add any of them as a dimension. See [Extending](extending.md#dimensions).

## Events

These `ahoy_events` columns are read: `id`, `visit_id`, `name`, `time` and `properties`.

- `properties` has to be `jsonb`. It is on Postgres with ahoy's generator.
- An event counts when its visit started in the date range, even if the event itself came later.
- The event model needs `belongs_to :visit`. ahoy's generator adds it.

## Property keys the dashboard reserves

`path`, `controller`, `format` and `crawler` have meaning to the dashboard, and so do `action` (ignored) and `revenue` (goals). `scroll_depth`, `engagement_time` and `depth` have meaning on the engagement events. Every other key on any event is a custom property.

Related: [Metrics and dimensions](metrics-and-dimensions.md), [Goals and funnels](goals-and-funnels.md), [Custom properties](custom-properties.md).
