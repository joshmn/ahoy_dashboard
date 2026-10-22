# Installation

ahoy_dashboard is a Rails engine that reads your ahoy_matey tables and draws a dashboard over them. Installing it takes a Gemfile line, one generator, a migration, and one lambda that says who's allowed in. Everything else is set in the dashboard once it's running.

## Requirements

| Needs | Version | Why |
|---|---|---|
| Ruby | 2.5 or newer | Use the Ruby version required by your Rails release. |
| Rails | 6.0 or newer | Engine migrations use the Rails 6.0 migration API. |
| PostgreSQL | 14 or newer. | The SQL is Postgres only. 14 is needed for the planner statistics. Expression indexes enforce goal definition and effective-name uniqueness on every supported version. |
| ahoy_matey | Any version that writes `ahoy_visits` and `ahoy_events` | ahoy isn't a dependency. The dashboard only needs the two tables and a model over each. |
| A job backend | Processing the `low` and `default` queues | Only for the optional parts that run in the background: precomputed dashboards, Search Console, rank tracking, keyword research, backlinks, the place list, AI visibility, alerts, email reports and the assistant. The ordinary analytics dashboard runs without one. |

On Ruby 3.4 and newer, `csv` is no longer a default gem. The gemspec declares it as a dependency, so `bundle install` pulls it in with the rest.

Your app also has to record the right events, `page_view` with a `path` in particular. [Tracking](tracking.md) covers what the dashboard reads.

## Compatibility matrix

The [CI workflow](../.github/workflows/test.yml) is configured for these combinations:

| Rails | Ruby |
|---|---|
| 6.0 | 2.5.9 |
| 6.1 | 2.5.9 |
| 7.0 | 2.7.8 |
| 7.1 | 2.7.8 |
| 7.2 | 3.1 |
| 8.0 | 3.2 |
| 8.1 | 3.2 |

Each lane uses its matching Gemfile in `gemfiles/`, starts PostgreSQL directly, migrates the dummy application and runs the full RSpec suite.

The gem includes compiled CSS, JavaScript and fonts. Installing it requires no Node build, host asset-pipeline configuration, Hotwire, Redis or Action Cable. The engine uses the host's configured Rails cache and Active Job adapter; a null cache store computes analytics directly.

## Install

It isn't on RubyGems. Vendor it into your app and point Bundler at the directory:

```ruby
gem "ahoy_dashboard", path: "vendor/gems/ahoy_dashboard"
```

Then:

```sh
bundle install
bin/rails generate ahoy_dashboard:install
bin/rails db:migrate
```

Check `config.authorize` in `config/initializers/ahoy_dashboard.rb` (see [Who's allowed in](#whos-allowed-in)), restart, and open `/analytics-dashboard`. Then:

1. On Settings, General, check the site host and pick a time zone. The host box is filled in from the address you're on, and nothing is saved until you click Save.
2. On Settings, Features, turn on what you want. Everything is off except site icons.
3. Follow any "Needs setup" note on that screen to the place that fixes it.

[Configuration](configuration.md) has every screen and what's on it.

### The generator

`bin/rails generate ahoy_dashboard:install` does three things:

1. Writes `config/initializers/ahoy_dashboard.rb`, unless you already have one.
2. Adds `mount AhoyDashboard::Engine, at: "/analytics-dashboard"` to `config/routes.rb`, unless something in that file already mentions `AhoyDashboard::Engine`.
3. Copies the migrations for the features you want into `db/migrate`, skipping any you already have.

| Option | Default | Does |
|---|---|---|
| `--at` | `/analytics-dashboard` | Where to mount it. Letters, numbers, `-`, `_` and `/` only. |
| `--only` | Every feature | Install only these features, comma separated, plus the core tables |
| `--skip` | Nothing | Install every feature except these, comma separated |
| `--skip-routes` | off | Leaves `config/routes.rb` alone |
| `--skip-migrations` | off | Doesn't copy any migrations |

`bin/rails generate ahoy_dashboard:install --help` prints the same list along with the feature names:

| Name | Feature |
|---|---|
| `search_console` | Search Console |
| `serp` | Rank tracking |
| `keywords` | Keyword research |
| `backlinks` | Backlinks |
| `places` | The place list |
| `assistant` | The assistant |
| `ai_visibility` | AI visibility |
| `alerts` | Alerts |
| `reports` | Email reports |

The core tables are always installed. They hold goals, custom properties, funnels, segments, saved queries, page groups, annotations, exclusions, settings, stored keys and the job log, and they add the indexes and planner statistics on the ahoy tables. Site icons need nothing past core.

So for analytics plus rank tracking and alerts:

```sh
bin/rails generate ahoy_dashboard:install --only serp,alerts
```

Or for everything except the two that DataForSEO sells by the row:

```sh
bin/rails generate ahoy_dashboard:install --skip keywords,backlinks
```

Separate names with commas. `--only serp alerts` is refused with `separate features with commas, not spaces: --only serp,alerts`. A name that isn't on the list is refused with the list, and so is passing both `--only` and `--skip`. All of that is checked before anything is written.

The default mount isn't `/analytics` because that path is on the blocklists browser extensions ship, and it isn't `/dashboard` because that's the first thing anybody guesses. Pick your own if you like.

The generated initializer has one live line:

```ruby
config.authorize = ->(controller) { controller.current_user&.admin? }
```

It assumes a `current_user` with an `admin?` method. Without both, every dashboard request raises instead of refusing politely. Everything else in the file is commented out, and none of it is needed to get going. See [What's left in the initializer](configuration.md#whats-left-in-the-initializer).

The generator ends by listing what's installed and what isn't:

```
installed: core, serp, alerts
not installed: search_console, keywords, backlinks, places, assistant, ai_visibility, reports. add one with bin/rails generate ahoy_dashboard:install --only <feature>
next: bin/rails db:migrate
```

### Migrations

The migrations create the dashboard's own tables, all named `ahoy_dashboard_*`. Core also indexes `ahoy_visits` and `ahoy_events` (see [Indexes](#indexes)) and adds planner statistics to `ahoy_events` (see [Planner statistics](#planner-statistics)). These migrations need the ahoy tables to exist, so install ahoy first.

The engine's migration files carry no version numbers. The generator stamps each one with a fresh timestamp as it copies it, after the newest migration your app already has, and names it `<timestamp>_<name>.ahoy_dashboard.rb`. Each copied file starts with `# This migration comes from ahoy_dashboard`.

There's no `bin/rails ahoy_dashboard:install:migrations`. That's the task Rails gives every engine by default, and it copies every migration with no way to leave a feature out. The generator is the one way in.

### Adding a feature later

Run the generator again with the feature you want, then migrate:

```sh
bin/rails generate ahoy_dashboard:install --only search_console
bin/rails db:migrate
```

It keeps your initializer and your route as they are, and copies only the migrations your app doesn't have. Then switch the feature on under Settings, Features.

You don't have to remember the commands. A feature that isn't installed shows them on Settings, Features, and so does every screen and report that belongs to it.

`--skip` on a later run means every feature except those, so it can add features you left out the first time.

### Upgrading

After you update the gem, run the generator with no options and migrate:

```sh
bin/rails generate ahoy_dashboard:install
bin/rails db:migrate
```

With no `--only` or `--skip`, a second run works on the features you already have. It copies any new migrations they need and leaves the rest alone. When there's nothing new it says every migration is already here, and you can skip the migrate.

#### An older install with missing migrations

Older versions shipped one migration per table. The generator knows those names and counts them as installed, so an app that ran them doesn't get the tables created twice.

An old migration whose file is gone still counts when the database already has what it made: its tables, or the columns it added. That covers an app that deleted old migration files, or one that renamed tables it created under another name. The generator checks the database your app is configured to use, so run it where that database is reachable.

If an app ran some of the old per-table migrations for a feature but not all of them, and the database doesn't have what the missing ones made either, the generator stops and lists them:

```
this app ran an older ahoy_dashboard but is missing some of its migrations: create_ahoy_dashboard_serp_runs, create_ahoy_dashboard_serp_checks. copy those from the version you had, run them, then try again
```

Copy those files from the gem version you had before, run `bin/rails db:migrate`, and run the generator again.

If the generator can't reach the database, it goes by `db/migrate` alone, and the message ends with `(the database could not be reached, so this is going by db/migrate alone)`. Start the database and run the generator again before you copy anything.

## Who's allowed in

Every dashboard request runs `config.authorize` with the controller. Return something truthy to let the request in.

```ruby
config.authorize = ->(controller) { controller.current_user&.admin? }
```

There's no default. With `authorize` unset, the dashboard refuses every request, admins included. A default that let anybody in would leak your analytics the first time somebody forgot the file existed.

What a refused request gets depends on `config.signed_in`:

| `signed_in` returns | Refused request gets |
|---|---|
| truthy (the default) | A 404, the same answer as if nothing were mounted |
| falsy | A redirect to `config.sign_in_path` |

The 404 is on purpose: the dashboard never confirms it exists to somebody who can't open it. The catch is that a missing `authorize` also looks like a missing route. If every dashboard URL is a 404, check `authorize` first.

To send signed-out people to your sign-in page and keep the 404 for signed-in people who aren't admins, set all three. With Devise:

```ruby
config.signed_in = ->(controller) { controller.user_signed_in? }
config.authorize = ->(controller) { controller.current_user&.admin? }
config.sign_in_path = ->(_controller) { Rails.application.routes.url_helpers.new_user_session_path }
```

`sign_in_path` takes a string or a lambda. The engine only knows its own routes, which is why the example goes through `Rails.application.routes.url_helpers`. It's a plain redirect, so it has to be a path or a URL on the same host.

### Using your ApplicationController

By default, the dashboard's controllers inherit from `ActionController::Base`. Set `config.parent_controller = "DashboardController"` to inherit a host controller's authentication callbacks and helpers. See [Hosting the dashboard](extending.md#hosting-the-dashboard-in-a-separate-app). With the default parent, callbacks in your `ApplicationController` do not run. Devise works because it adds its helpers to `ActionController::Base`.

With the Rails 8 authentication generator, `Current.session` is set by a `before_action` in your `ApplicationController`, so it's empty on the dashboard. Look the session up in the lambda instead:

```ruby
config.authorize = ->(controller) do
  session_id = controller.request.cookie_jar.signed[:session_id]
  Session.find_by(id: session_id)&.user&.admin?
end
```

## Mount path

The generator writes the mount into `config/routes.rb`. Move it by editing that line:

```ruby
mount AhoyDashboard::Engine, at: "/stats-for-me"
```

Keep the default route name. Don't pass `as:`. The assistant finds the dashboard through the `ahoy_dashboard_path` helper, and under another name it quietly falls back to `/`.

The mount can sit inside any routing constraint, like a subdomain or an internal host.

## Keep the dashboard out of your own numbers

Ahoy's controller hooks run on every controller in your app, the dashboard's included. The dashboard records no events of its own, but if ahoy records visits on the server (`Ahoy.server_side_visits = true`), looking at the dashboard creates visits. Exclude the mount path:

```ruby
Ahoy.exclude_method = lambda do |_controller, request|
  request.path.start_with?("/analytics-dashboard")
end
```

If you already have an `exclude_method`, add the path check to it.

## Indexes

Every dashboard query filters on `ahoy_visits.started_at` and `ahoy_events.time`, and ahoy's generator doesn't index either one. The first migration adds both, so you don't have to.

It builds them with `CREATE INDEX CONCURRENTLY`, so your app keeps writing visits and events while it runs. On a big events table that takes a while.

If you already have a matching valid index on either column, the migration leaves it alone, whatever it's named. An invalid index from a failed concurrent build is rebuilt only when it has the dashboard's own name and matching definition. Invalid indexes with other names stay untouched, and the migration adds a working dashboard index. A dashboard-owned name with a different definition stops the migration with an error.

Rolling the time-index migration back doesn't remove the indexes. Existing installations may have shared them with the host application.

Keep ahoy's own `ahoy_events(name, time)` index. Goal counts lean on it.

Another core migration, `AddAhoyDashboardQueryIndexes`, adds `(time, visit_id)` on `ahoy_events` where `properties ->> 'crawler' IS NULL`. Counts of human events over a date range and joins to visits use it. When the alert tables are already there, it also indexes the non-null `check_id` and `previous_check_id` on alert events. Installing alerts later builds those two itself. The builds are concurrent. They cost storage and some write time, and they sit alongside the event time, name/time and visit indexes rather than replacing them.

If you already have a matching index under another name, it uses yours. If one of its own names holds an invalid index from a failed build, it drops and rebuilds it. If one of its names holds an index with a different definition, it stops with an error and leaves that index alone. Rolling it back removes only matching indexes with its own names, so yours stay.

## Planner statistics

Postgres keeps no statistics on expressions like `properties ->> 'crawler'`, so it guesses how many rows match, and on a real database it guessed 156 rows against 30,264. Wrong guesses make it pick slow plans. One of the migrations adds `CREATE STATISTICS` objects on the property expressions the dashboard filters by, then runs `ANALYZE ahoy_events`. On one goal-filtered dashboard load that took 466ms down to 68ms. Statistics cost nothing on insert, which is why they're statistics rather than indexes on your busiest table.

`db/schema.rb` can't hold `CREATE STATISTICS`. A database built with `bin/rails db:schema:load` records the migration as run without the statistics it made. Create them with:

```sh
bin/rails ahoy_dashboard:statistics
```

Run this task after schema loading in your application's database preparation and CI setup. It creates missing statistics in the events table's schema and analyzes the table only when it creates an object. Healthy objects keep their planner data. A conflicting name or definition stops with an error; statistics on other tables or under legacy names stay untouched. The engine does not change your application's schema format or run this maintenance during requests.

## Background jobs

Anything that runs on a schedule (Search Console syncs, rank checks, backlinks, the place list, AI visibility runs, alerts, alert emails and email reports) is started by one job, `AhoyDashboard::TickJob`. Enable the opt-in embedded scheduler with `config.embedded_scheduler = true`, or schedule the job every minute. The embedded loop starts on each web worker's first request and still needs Active Job workers for the resulting work. Other jobs retain their own cadences; the minute tick also maintains an enabled precomputed default dashboard while idle. [Background jobs](background-jobs.md) covers the embedded loop, Puma/Unicorn/Passenger worker behavior, and alternatives using Sidekiq, Solid Queue and cron. The ordinary analytics dashboard needs no jobs.

Related: [Configuration](configuration.md), [Tracking](tracking.md), [Background jobs](background-jobs.md), [Security and privacy](security-and-privacy.md).
