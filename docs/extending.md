# Extending

Your app can add its own dimensions, put readable names on raw values, and add report cards to the dashboard, all without touching the gem. It can also send alerts wherever it wants, change the alert email, and fill in settings from code.

Put every registration inside `to_prepare`, so it runs again after each code reload in development:

```ruby
# config/initializers/ahoy_dashboard_extensions.rb
Rails.application.config.to_prepare do
  AhoyDashboard::Dimension.register(...)
  AhoyDashboard::ValueLabels.register(...)
  AhoyDashboard::Report.register(...)
end
```

Registering the same key again replaces the old entry, which is what makes the reload safe.

## Dimensions

A dimension is anything you can break numbers down by and filter on. The built-in ones read the columns in [Tracking](tracking.md#visits). Register your own to read anything else in `ahoy_visits` or `ahoy_events`, including columns your app added.

```ruby
AhoyDashboard::Dimension.register(
  key: "app_version",
  label: "App version",
  group: "Device",
  scope: :visit,
  sql: Arel.sql("ahoy_visits.app_version")
)
```

| Argument | Required | Does |
|---|---|---|
| `key` | Yes | The name in URLs, filters, saved questions and exports. Can't be a built-in key, `goal`, or anything starting with `prop:`. |
| `label` | Yes | The name on cards, tabs and Explore |
| `group` | Yes | The heading it's listed under in the filter dialog. Use `Page`, `Source`, `Location`, `Device` or `Behaviour` to join a built-in group. Any other name adds a new heading after those. |
| `scope` | Yes | `:visit` when the SQL reads `ahoy_visits`, `:event` when it reads `ahoy_events` |
| `sql` | Yes | A SQL expression that returns text, as a string or `Arel.sql` |
| `filter_label` | No | The name on filter chips and in the filter form, if it should differ from `label` |
| `unknown_label` | No | What an empty value shows as. Defaults to `(not set)`. |

A key that's already built in raises `ArgumentError: dashboard dimension "country" is already built in`.

### The SQL has to return text

Breakdowns cast the value to text on their own, but filters compare your expression as written, against strings. On a number column, "is (not set)" and "contains" are Postgres errors. Cast it:

```ruby
sql: Arel.sql("ahoy_visits.user_id::text")
```

An event property works the same way:

```ruby
AhoyDashboard::Dimension.register(
  key: "experiment",
  label: "Experiment",
  group: "Behaviour",
  scope: :event,
  sql: Arel.sql("ahoy_events.properties ->> 'experiment'")
)
```

For a plain event property, a [custom property](custom-properties.md) gets you the same thing without code. Register a dimension when you want your own label, your own group, or an expression.

Pass a fixed string, `Arel.sql`, or a lambda returning a SQL expression. Value search caches plain values and counts for two minutes and reads labels from the current dimension definitions. Its cache key includes the resolved SQL and filtered source relations, so changing a dimension's expression takes effect immediately.

### What a dimension gets

Once registered, it shows up:

- in the filter dialog, under its group
- in value search, filters in the URL, and segments
- in Explore's "Break down by"
- in the assistant's breakdown tool
- as a tab on a report card you register (see [Report cards](#report-cards))

It doesn't get a tab on the built-in cards.

Every registered dimension can be filtered on. There's no way to register one that only groups.

## Value labels

Some values mean nothing on their own. A card ranking `412` above `118` doesn't tell you anything, so register a lookup that turns them into names:

```ruby
AhoyDashboard::ValueLabels.register("prop:team_id") do |ids|
  Team.where(id: ids.grep(/\A\d+\z/)).pluck(:id, :name)
end
```

- The block gets every value on the page at once, as an array of unique, non-blank strings. One page of rows is one call, so one query.
- Return `[value, label]` pairs or a hash. Keys are compared as strings, so integer IDs match.
- A value the block doesn't answer keeps its raw text, and so does a blank label.
- If the block raises, the error is logged as `dashboard value labels for prop:team_id failed: ...` and every row shows its raw value.
- Leaving out the block raises `ArgumentError`.

The `grep` in the example matters. Anything recorded under that property reaches the block, and comparing a value like `abc` to a bigint column raises in Postgres instead of matching nothing.

Works on any dimension key: built in (`country`), registered (`app_version`) or a custom property (`prop:team_id`).

### Where labels show

Labels show on report cards, the details view, Explore, CSV exports, and the assistant's answers. The CSV gets the label only, not the raw value.

Filters still use the raw value, so clicking "Acme Corp" adds the filter `team_id is 412`. Filter chips, the filter dialog, value search, segments, realtime and the page journey all show raw values.

## Report cards

A registered card sits on the dashboard after the built-in ones, with its own tabs, details view, "Show all" and CSV export.

```ruby
AhoyDashboard::Report.register(
  key: "app",
  title: "App",
  tabs: [
    AhoyDashboard::Report::Tab.new(
      key: "version",
      label: "Version",
      dimension_key: "app_version",
      metrics: %w[visitors],
      detail_metrics: %w[visitors visits pageviews bounce_rate visit_duration],
      label_column: "App version"
    ),
    AhoyDashboard::Report::Tab.new(
      key: "device",
      label: "Device",
      dimension_key: "device",
      metrics: %w[visitors],
      detail_metrics: %w[visitors visits pageviews],
      label_column: "Device"
    )
  ]
)
```

`Report.register` takes:

| Argument | Required | Does |
|---|---|---|
| `key` | Yes | Lowercase letters, numbers and underscores, starting with a letter. The card's URL is `/reports/<key>` and its export is `/exports/<key>`. |
| `title` | Yes | The card's heading |
| `tabs` | Yes | One or more `Report::Tab` |
| `default_tab` | No | The key of the tab it opens on. Defaults to the first. |
| `wide` | No | Accepted and ignored. Every card is half width. |

A key can't be a built-in card, `search_console`, `facet`, or start with `funnel_`.

Each `Report::Tab` takes:

| Argument | Required | Does |
|---|---|---|
| `key` | Yes | Unique within the card |
| `label` | Yes | The tab's name |
| `dimension_key` | Yes | Any dimension: built in, registered, or `prop:<name>` |
| `metrics` | Yes | The columns on the card. The first one ranks the rows. |
| `detail_metrics` | Yes | The columns in the details view |
| `label_column` | Yes | The heading over the values |
| `breakdowns` | No | Other dimensions the same tab can group by, as `Report::Breakdown` |

Metrics are any of the keys in [Metrics](metrics-and-dimensions.md#metrics): `visitors`, `visits`, `pageviews`, `views_per_visit`, `bounce_rate`, `visit_duration`, `scroll_depth`, `events`, `conversion_rate`, `engagement_time`, `revenue_total`, `revenue_average`.

Everything is checked when you register. A bad key, a missing label, an unknown metric or a dimension that doesn't exist raises `ArgumentError` and nothing is registered, so a mistake stops the boot instead of showing up as a broken card later.

### Breakdowns

A breakdown lets one tab regroup its rows, like the built-in Top pages tab grouping by page or by controller.

```ruby
AhoyDashboard::Report::Tab.new(
  key: "version",
  label: "Version",
  dimension_key: "app_version",
  metrics: %w[visitors],
  detail_metrics: %w[visitors visits],
  label_column: "App version",
  breakdowns: [
    AhoyDashboard::Report::Breakdown.new(key: "version", label: "Version", dimension_key: "app_version", label_column: "App version"),
    AhoyDashboard::Report::Breakdown.new(key: "os", label: "OS", dimension_key: "os", label_column: "OS")
  ]
)
```

The first breakdown is the one the tab opens on, so its `dimension_key` has to match the tab's. Each breakdown can set its own `detail_metrics`.

### When the first metric isn't visitors

The hover percentage on a row always divides by total unique visitors. Rank a card by `visits` and that percentage is visits over visitors, which can pass 100%. Put `visitors` first unless you really want another ranking.

## Where alerts go

`config.alert_notifier` is called once with each new alert, the moment it fires:

```ruby
config.alert_notifier = ->(event) do
  SlackClient.post(text: "[#{event.severity}] #{event.headline}. #{event.detail} (#{event.rule.name})")
end
```

The `event` is an `AhoyDashboard::AlertEvent`:

| Field | Holds |
|---|---|
| `headline` | "Overtaken on project management software" |
| `detail` | "competitor.com is 3, we are 5." |
| `subject` | What the alert is about. For a rank tracking rule, the search and place, like "project management software (us)". For a goal rule, the goal's name. For a job rule, the job's name. |
| `severity` | `"high"`, `"medium"` or `"low"` |
| `group` | The rule's group: `"Rank tracking"`, `"Search Console"`, `"Goals"`, `"Backlinks"`, `"Jobs"` or `"Traffic"` |
| `fired_at` | When it fired |
| `rule` | The rule, with `name` and `key` |
| `check`, `previous_check` | The two rank checks it compared, set only for a rank tracking rule. Either can be nil if the check was deleted. `nil` for every other group. |

- It's called inside the alerts job, after the run's alerts are saved, never for an alert that already fired.
- If it raises, the error is saved on the alert and shows as "Failed" in the Sent column on the Alerts screen. The run carries on.
- What it returns is ignored.
- It runs in the job, so a slow notifier slows every alert run. Enqueue a job from it if the call can hang.

It's separate from the alert emails. Both can be on. See [Alerts](alerts.md).

## Changing the alert email

Two settings, for two different jobs.

`alerts[:parent_mailer]` is what `AhoyDashboard::AlertMailer` inherits from. Point it at your `ApplicationMailer` to pick up your `default from:`, delivery settings and interceptors:

```ruby
config.alerts[:parent_mailer] = "ApplicationMailer"
```

It's read once, when the mailer class loads, so set it in the initializer. A class that doesn't exist raises `NameError` at that point, which is boot in production. `reports[:parent_mailer]` does the same for the traffic email.

`alerts[:mailer]` swaps in your own mailer. Subclass the dashboard's:

```ruby
class SiteAlertMailer < AhoyDashboard::AlertMailer
  def digest
    headers["X-Priority"] = "1"
    super
  end
end
```

```ruby
config.alerts[:mailer] = "SiteAlertMailer"
```

To change the email itself, add `app/views/site_alert_mailer/digest.html.erb` and `digest.text.erb`. A subclass looks there first and falls back to the dashboard's own templates. The layout stays the dashboard's, since `AlertMailer` sets it.

The dashboard calls your mailer as `mailer.with(digest:, recipients:).digest.deliver_now`, so any mailer with a `digest` action that reads those two params works, subclass or not.

`alerts[:mailer]` is looked up each time an email is sent. A class that doesn't exist doesn't stop the boot. The send fails with `NameError`, and the email shows as failed. `reports[:mailer]` works the same way for the traffic email, and the dashboard calls it with a `result:` param as well.

The email's links are full URLs, so your mailer's `default_url_options` needs a `host`. Without one, every send fails and shows as a failed email.

## Setting values from code

Everything outside the initializer is set on the settings screens and stored in the `ahoy_dashboard_settings` table. To fill those in without clicking, like on a fresh database or a staging copy, write them with `AhoyDashboard::Preferences.write`:

```ruby
# db/seeds.rb
AhoyDashboard::Preferences.write(:site, host: "example.com", time_zone: "America/Chicago")
AhoyDashboard::Preferences.write(:serp, enabled: true)
AhoyDashboard::Preferences.write(:alerts, enabled: true, digest: %w[daily weekly], recipients: ["you@example.com"])
```

The first argument is the scope: `:site`, or a feature name. The rest are the settings in it. A name it doesn't know raises `ArgumentError`, so a typo can't quietly do nothing. Passing `nil` clears a setting back to its default. [Setting values from code](configuration.md#setting-values-from-code) lists every scope and name.

A few things to know:

- It needs the `ahoy_dashboard_settings` table, so it has to run after the dashboard's migrations. A seed file or a migration of your own both work. Keep it out of the initializer, which runs on every boot, including the one before the table exists.
- It skips the checks the screens make. It won't turn `https://www.example.com/` into a bare host, won't refuse a time zone that doesn't exist (a bad one reads as UTC), and will switch on a feature whose tables aren't installed. Write a bare host, a real zone name, and only switch on what you've installed.
- It writes to the database, so whatever it sets shows up on the screens afterward and can be changed there like anything else.

## Reading the numbers from your own code

There's no API. A few screens answer as JSON, because the dashboard's own front end uses them:

| URL | Returns |
|---|---|
| `/dashboard.json` | The tiles and the chart series for the same query string as the page |
| `/reports/<key>.json` | One card's rows |
| `/realtime.json` | `{"visitors": 12}` |
| `/search_console.json` | The Search Console card's rows and totals |

They sit behind the same `authorize` check as every page, and your session cookie is the only way in. There are no API keys. Their shape isn't promised and can change in any version.

For numbers inside your app, read the ahoy tables yourself.

## Overriding views

It's a Rails engine, so a template at the same path in your app, like `app/views/ahoy_dashboard/dashboards/show.html.erb`, wins over the gem's. That's how Rails engines work, not something the dashboard supports. An overridden view breaks without warning when the gem changes the one it replaced. Inside one, reach your own routes through `main_app.`.

## A different front end

`config.assets_root` serves the dashboard's CSS, JavaScript and fonts from a directory of yours instead of the gem's. It needs `builds/ahoy_dashboard.css`, `builds/ahoy_dashboard.js`, `builds/ahoy_dashboard.js.map` and the `fonts/*.woff2` files. Nothing else is served. It's only useful if you've forked the front end.

Related: [Metrics and dimensions](metrics-and-dimensions.md), [Custom properties](custom-properties.md), [Alerts](alerts.md), [Configuration](configuration.md).
