# Configuration

Almost everything is set in the dashboard, under Settings. The initializer, `config/initializers/ahoy_dashboard.rb`, only holds the parts that have to be code: who's allowed in, your own ahoy models, your own mailers, the cache store, the optional embedded scheduler, and where an alert goes the moment it fires.

```ruby
AhoyDashboard.configure do |config|
  config.authorize = ->(controller) { controller.current_user&.admin? }
end
```

That's a complete initializer. Open the dashboard, go to Settings, General, check the site host and pick a time zone. Then switch on what you want under Settings, Features.

The dashboard reads no environment variables and no Rails credentials. Keys and passwords are typed into the screen that uses them and stored encrypted in your database. See [Stored secrets](security-and-privacy.md#stored-secrets).

## What's left in the initializer

| Setting | Default | Does |
|---|---|---|
| `parent_controller` | `"ActionController::Base"` | Host controller class name. Set before engine controllers load. |
| `authorize_action` | `nil` | Optional lambda receiving the controller and `:read`, `:manage`, or `:assistant`. |
| `navigation_partial` | `nil` | Host partial rendered beside the site name in the header. |
| `context` | `nil` | Host class name providing `current` and `with(identifier)`. |
| `url_options` | `nil` | Lambda returning URL defaults, including dynamic mount parameters. |
| `authorize` | `nil` | A lambda called with the controller on every request. Truthy lets the request in. With no lambda, every request is refused. |
| `signed_in` | `->(_controller) { true }` | Whether anybody is signed in. Decides what a refused request gets: a 404 when truthy, a redirect to `sign_in_path` when not. |
| `sign_in_path` | `"/"` | Where a refused, signed-out request is sent. A string, or a lambda called with the controller. |
| `visit_model` | `"Ahoy::Visit"` | The model over your visits table |
| `event_model` | `"Ahoy::Event"` | The model over your events table. It needs a `visit` association. |
| `cache_store` | `nil` (uses `Rails.cache`) | A cache-store instance or Rails cache-store configuration for this engine. Leaves the host cache unchanged. |
| `embedded_scheduler` | `false` | Run the minute tick in each web worker after its first request. Restart to apply changes. Active Job still handles the resulting work. See [Background jobs](background-jobs.md#embedded-scheduler). |
| `alerts[:mailer]` | `"AhoyDashboard::AlertMailer"` | The alert email's mailer class, as a string. Point it at a subclass to change the email. |
| `alerts[:parent_mailer]` | `"ActionMailer::Base"` | What `AhoyDashboard::AlertMailer` inherits from, as a string. Point it at `"ApplicationMailer"` to pick up your defaults. |
| `reports[:mailer]` | `"AhoyDashboard::ReportMailer"` | The traffic email's mailer class, as a string |
| `reports[:parent_mailer]` | `"ActionMailer::Base"` | What `AhoyDashboard::ReportMailer` inherits from, as a string |
| `alert_notifier` | `nil` | A lambda called with each alert the moment it fires, for chat or anything else |
| `assets_root` | `nil` | A directory to serve the dashboard's CSS, JavaScript and fonts from instead of the gem's own |
| `error_screens` | `nil` | Whether an unexpected error shows the dashboard's error screen or raises. `nil` raises wherever Rails shows full errors (development, usually) and shows the screen everywhere else. `true` always shows the screen, `false` always raises. |

Here's the generated file with everything filled in:

```ruby
AhoyDashboard.configure do |config|
  config.authorize = ->(controller) { controller.current_user&.admin? }
  config.signed_in = ->(controller) { controller.user_signed_in? }
  config.sign_in_path = ->(_controller) { Rails.application.routes.url_helpers.new_user_session_path }

  config.visit_model = "Ahoy::Visit"
  config.event_model = "Ahoy::Event"
  config.alerts[:parent_mailer] = "ApplicationMailer"
  config.alerts[:mailer] = "AhoyDashboard::AlertMailer"
  config.reports[:parent_mailer] = "ApplicationMailer"
  config.reports[:mailer] = "AhoyDashboard::ReportMailer"
  config.alert_notifier = ->(event) { ChatNotifier.post(event.headline) }
end
```

[Installation](installation.md#whos-allowed-in) has examples of `authorize` for Devise and the Rails 8 authentication generator.

Renaming the models doesn't rename the tables. The SQL reads `ahoy_visits` and `ahoy_events` by name, whatever the models are called.

`parent_mailer` is read once, when the mailer class loads, so it has to be in the initializer. A parent class that doesn't exist raises `NameError` at that point. `mailer` is read each time an email is sent. [Extending](extending.md) covers subclassing the emails and writing an `alert_notifier`.

A replacement `assets_root` needs `builds/ahoy_dashboard.css`, `builds/ahoy_dashboard.js`, `builds/ahoy_dashboard.js.map` and the `fonts/*.woff2` files. Leave it alone unless you've forked the front end.

## Cache store

By default, the dashboard uses the host application's `Rails.cache`. To give the engine its own store, set `cache_store` in `config/initializers/ahoy_dashboard.rb`:

```ruby
AhoyDashboard.configure do |config|
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch("AHOY_DASHBOARD_CACHE_URL"),
    namespace: "ahoy_dashboard"
  }
end
```

The host supplies the adapter dependencies and connection settings, as for its normal Rails cache. You can also supply an existing `ActiveSupport::Cache::Store` instance. Store configurations are resolved once when assigned; `nil` restores the default use of `Rails.cache`.

This setting covers analytical results, discovery and facet queries, Search Console results, snapshots and their refresh leases, report and funnel HTML fragments, favicon results and fetch coordination, and rank-check queue markers. It does not replace `Rails.cache` or change the host's controller cache store. HTML fragments still respect the host's `perform_caching` setting.

Configure web processes and background workers to use the same shared backend and namespace. A memory store remains local to its process; a null store retains nothing. Separate deployments should use separate namespaces. Cache selection is independent of the **Precompute default dashboard** checkbox, which remains off by default.

## Analytical cache

The dashboard uses the configured engine cache. Numerical analytical query results expire after 30 seconds. Keys include the database connection identity, schema search path, configured site host and exact scoped query, including filter values, metric and time zone where relevant. Cached entries contain counts and chart rows, not Active Record models or user-specific labels.

A shared cache lets application workers reuse those readings. A memory store keeps a separate cache in each worker; `:null_store` computes each reading directly. New traffic can take up to 30 seconds to appear in cached analytics. Realtime uses its separate refresh behavior. Rolling exclusion previews align their default 30-day start to a 30-second boundary; explicitly supplied boundaries stay exact.

Comparisons for ongoing named periods use the same 30-second boundary so their moving cutoff can share cached readings. Completed periods and explicit custom ranges retain exact comparison boundaries.

### Precomputed default dashboard

Open Settings, General, check **Precompute default dashboard**, and save. It starts off. Saving with the checkbox enabled queues the first snapshot build; no initializer or console change is needed. Unchecking it and saving returns subsequent requests to the ordinary query path, and queued refresh jobs check the setting before building.

The default dashboard summary and its initial panels use a snapshot for Last 30 days, Visitors, daily grouping, no comparison and no filters. A configured default segment, included crawlers or included internal traffic uses the ordinary query path. Remembered views are resolved before eligibility is checked. Other ranges, metrics, filters, chart refreshes, report details and exports continue to run their existing queries.

Snapshots use the [configured engine cache](#cache-store), defaulting to `Rails.cache`. Background refresh across processes needs a shared store accessible to both web and Active Job workers. The host enables the embedded scheduler or schedules `AhoyDashboard::TickJob` every minute, with workers processing `low` and `default` for the resulting work. These are host infrastructure requirements; saving the checkbox does not start workers. A memory store is local to each process, and `:null_store` cannot reuse snapshots and skips background snapshot enqueueing. An inline job adapter skips background refresh; asynchronous panels then run their ordinary queries when no usable snapshot exists.

A snapshot is fresh for 30 seconds. The minute tick queues upkeep while the setting is enabled, including when the dashboard is idle. A later eligible request can also serve the existing snapshot while queuing one refresh; a worker leaves an already fresh snapshot alone. The snapshot is retained for at most 270 seconds, allowing for the underlying analytical cache's 30-second freshness window and bounding numerical staleness to five minutes. A missing or expired snapshot queues a background build while each requested panel runs its own ordinary query. The initial shell and summary never wait for a full-dashboard rebuild. The explicit complete response (`?loading=complete`), used by the no-JavaScript link, retains its synchronous fallback. A healthy scheduled tick and worker keep idle snapshots prepared. Cache eviction, midnight range changes, changed definitions or a delayed worker can still cause a cold request. The host enables the embedded scheduler or configures the recurring schedule once; dashboard users only change the checkbox. See [Background jobs](background-jobs.md#precomputed-dashboard-refresh).

Keys include database and schema identity for engine, visit and event models; their scoped SQL; the site host and time zone; the local date range; engine definitions and settings; and resolved report and dimension definitions. Changes to goals, funnels, pinned questions, annotations, exclusions, page groups, segments or settings use a different snapshot. Custom report and dimension registries are resolved into the fingerprint; no callable or model instance is stored. A worker whose database, schema or definitions no longer match the queued key leaves the entry alone. Tenant-aware hosts must enter their site context before queuing each site's tick. With `config.context`, jobs restore that context automatically; the engine does not discover or iterate tenants.

Cache keys also include the configured host context ID. Isolation implemented through session variables needs this explicit identity; without it, leave precomputation disabled. See [Hosting the dashboard](extending.md#hosting-the-dashboard-in-a-separate-app) for the context contract and its data-isolation requirements.

When the host enables Rails fragment caching, report and funnel HTML from a prepared snapshot can also use the configured engine cache for that snapshot generation. Realtime and session-specific controls remain uncached.

The stored payload contains bounded analytical results and record IDs. Each panel request reloads only the definitions needed for its slice; the summary reads realtime activity separately. The dashboard displays "Snapshot updated" in its configured time zone. This timestamp describes snapshot assembly; the realtime pill and subsequent chart refreshes have their own freshness.

## Where everything else lives

Every other setting is stored in the `ahoy_dashboard_settings` table and changed on a screen. A change takes effect on the next request, with no deploy and no restart. The dashboard reads its settings once per request.

| Screen | What's on it |
|---|---|
| [Settings, Features](#settings-features) | Every optional feature, switched on or off |
| [Settings, General](#settings-general) | Site host, canonical host, time zone, internal addresses, known crawlers, precomputed dashboard |
| [Settings, Search provider](#settings-search-provider) | Rank tracking providers and their keys, keyword research and backlinks providers, the place list |
| [Settings, Search Console](#settings-search-console) | Google OAuth client, the Google connection, the property, the redirect URL |
| [Settings, Emails](#settings-emails) | Alert emails and traffic emails |
| Settings, Assistant | The assistant's provider, model, endpoint, key, temperature and max tokens. See [Assistant](assistant.md#set-up-a-provider). |
| Settings, AI visibility | Which assistants are asked, their keys and models, the prompts, how often, the monthly cap. See [AI visibility](ai-visibility.md). |

## What's optional

The analytics dashboard is always on. Everything in this table is optional, and every one except site icons starts off.

| Feature | Name for `--only` | Needs | Page |
|---|---|---|---|
| Site icons | (always installed) | Nothing | [Site icons](dashboard.md#site-icons) |
| Search Console | `search_console` | A Google Cloud OAuth client and a verified property | [Search Console](search-console.md) |
| Rank tracking | `serp` | A SerpApi, SearchApi or DataForSEO account | [Rank tracking](rank-tracking.md) |
| Keyword research | `keywords` | A DataForSEO login | [Keyword research and backlinks](keyword-research-and-backlinks.md) |
| Backlinks | `backlinks` | A DataForSEO login | [Keyword research and backlinks](keyword-research-and-backlinks.md) |
| The place list | `places` | Nothing. It builds itself once a month. | [Keyword research and backlinks](keyword-research-and-backlinks.md) |
| The assistant | `assistant` | An Anthropic, OpenAI or DeepSeek key, or an OpenAI-compatible server like LM Studio | [Assistant](assistant.md) |
| AI visibility | `ai_visibility` | A key for at least one assistant and some prompts | [AI visibility](ai-visibility.md) |
| Alerts | `alerts` | At least one rule on, and email periods and recipients | [Alerts](alerts.md) |
| Email reports | `reports` | Email periods and recipients | [Email reports](email-reports.md) |

Each optional feature has its own tables. The install generator copies all of them unless you tell it otherwise, and you can add one later. See [Adding a feature later](installation.md#adding-a-feature-later).

Turning a paid feature on doesn't spend anything by itself. Rank tracking, keyword research and backlinks use the free sample provider until you pick a real one, and AI visibility asks nothing until an assistant has a key. After that, each one stops at its monthly cap.

## Settings, Features

One row per optional feature, with what it does and where it stands:

| State | Means |
|---|---|
| On | Switched on, and nothing's missing. A Settings button takes you to its screen. |
| Off | Installed and switched off. Turn on is right there. |
| Needs setup | Switched on, but something it needs is missing. The row says the first missing thing and has a "Set it up" button that goes to the screen that fixes it. |
| Not installed | Its tables aren't in your database. The row shows the exact commands to install it, and Turn on is disabled with the reason. |

Needs setup only shows the first missing thing, in order, because the later ones don't mean anything yet. Search Console asks for the OAuth client before the Google connection, and the connection before the property.

A feature that isn't installed can't be switched on, from the screen or anywhere else.

Nothing is hidden when it isn't installed or isn't on. A screen or report for a feature that isn't installed opens an install page with the commands to run. A screen for one that's switched off says so and points at Settings, Features. A button that can't be used yet is shown disabled, with the reason.

## Settings, General

| Field | Default | Does |
|---|---|---|
| Site host | Empty. The box is filled in from the address you're on until you save. | The site being measured, like `example.com`. See below. |
| Canonical host | Empty | Only for a site that answers on more than one name. Links the dashboard builds back to your site use this one, including the Search Console redirect URL. Blank means the site host. |
| Time zone | UTC | The zone every range, day, chart, annotation, email and job time is read in |
| Internal addresses | The private and loopback ranges | Visits from these are left out of every number. See [Excluded traffic](excluded-traffic.md). |
| Hide known crawlers | Off | Visits whose user agent names a known crawler are left out of every number. See [Known crawlers](excluded-traffic.md#known-crawlers). |
| Precompute default dashboard | Off | Saves a reusable snapshot of the default 30-day dashboard and queues its first build when saved. See [Precomputed default dashboard](#precomputed-default-dashboard). |

The site host does a lot for one field:

- It's the site name in the header and the page title.
- Referrers from it and its subdomains count as Internal, not Referral. See [Channels](metrics-and-dimensions.md#channels).
- It's your own domain for rank tracking, backlinks, keyword gap and the brand split, and the site alerts watch.
- It's the fallback host for the Search Console redirect URL.

The queries read the host from the database every time they run, so changing it reclassifies your own pages as Internal on the next request. A leading `www.` is ignored. The form takes a bare host name: a pasted `https://` or path is trimmed off, and a port is refused.

The time zone is picked from a list, so it can't be misspelled.

The internal addresses take one address or range per line, or separated by commas. An empty box counts every visit. "Use the defaults" puts back `127.0.0.0/8`, `::1/128`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` and `fc00::/7`.

## Settings, Search provider

The Providers card lists SerpApi, SearchApi and DataForSEO. Each one takes its keys, and the one marked "Use this one" is the one rank tracking uses. With none marked, rank tracking runs on the sample provider, which invents results and costs nothing. The monthly cap is set on the provider too. See [Providers](rank-tracking.md#providers).

The card below it, "Keyword research, backlinks and places", holds:

| Field | Default | Does |
|---|---|---|
| Keyword research provider | The rank tracking provider | Where search volume and keyword ideas come from |
| Search from | `us` | The place a keyword lookup starts from |
| Language | `en` | The language a keyword lookup starts from |
| Backlinks provider | The rank tracking provider | Where the list of sites linking to you comes from |
| Include postal codes | Off | Adds postal codes to the place list |
| Monthly list address, under Advanced | DataForSEO's published list | Where the place list is downloaded from each month |

Until one of rank tracking, keyword research or backlinks is installed, this screen is an install page. See [Keyword research and backlinks](keyword-research-and-backlinks.md).

## Settings, Search Console

The OAuth client ID and secret, the Connect Google account button, the property picker, and a redirect URL override.

The redirect URL is the override when you've saved one. Otherwise it's built as `https://<canonical host><mount path>/settings/google_callback`, where the canonical host falls back to the site host. Hosts using `config.url_options` can supply the dashboard app's host and protocol instead. With no host and no override, there's no URL to register with Google yet, and the screen says so.

The built one is always `https`. Google only allows plain `http` for `localhost`, so in development save an override like:

```
http://localhost:3000/analytics-dashboard/settings/google_callback
```

Clear the field and save to go back to the built one. See [Search Console](search-console.md).

## Settings, Emails

Two cards, one for each kind of email.

Alert emails:

| Field | Default | Does |
|---|---|---|
| How often | None | Any of daily, weekly and monthly. None sends no alert emails, and alerts still show on the dashboard. |
| Send to | Nobody | One address per line, or separated by commas |
| Send from | Your app's usual sender | Like `alerts@example.com` or `Alerts <alerts@example.com>` |
| Send even when nothing fired | On | An email that says nothing fired, so you can tell the emails still work |

Traffic emails have How often, Send to and Send from, the same way.

Each email goes out the morning after its period ends. See [Alerts](alerts.md) and [Email reports](email-reports.md).

## Setting values from code

If you'd rather not click through the screens on every new environment, write the values from a seed file or a migration with `AhoyDashboard::Preferences.write`:

```ruby
AhoyDashboard::Preferences.write(:site, host: "example.com", time_zone: "America/Chicago")
AhoyDashboard::Preferences.write(:serp, enabled: true)
AhoyDashboard::Preferences.write(:alerts, enabled: true, digest: %w[daily weekly], recipients: ["you@example.com"])
```

It writes to `ahoy_dashboard_settings`, so it has to run after the dashboard's migrations. The first argument is the scope and the keywords are the settings in it:

| Scope | Settings |
|---|---|
| `:site` | `host`, `canonical_host`, `time_zone`, `internal_ips`, `hide_known_crawlers`, `precomputed_dashboard` |
| `:search_console` | `enabled`, `redirect_uri` |
| `:keywords` | `enabled`, `provider`, `location`, `language` |
| `:backlinks` | `enabled`, `provider` |
| `:places` | `enabled`, `postal_codes`, `source` |
| `:alerts` | `enabled`, `digest`, `recipients`, `from`, `send_empty` |
| `:reports` | `enabled`, `digest`, `recipients`, `from` |
| `:favicons`, `:serp`, `:assistant`, `:ai_visibility` | `enabled` |

A name that isn't in the table raises `ArgumentError`. Writing `nil` clears a setting back to its default. `AhoyDashboard::Preferences.read(:site, :host)` reads one back.

`write` skips the checks the screens make. It won't refuse to switch on a feature whose tables aren't installed, and it doesn't check that a host or a time zone is real. A bad time zone reads as UTC.

Writing `precomputed_dashboard` stores the preference only. Saving it through Settings, General also queues the initial snapshot build.

Keys and passwords aren't settings. They're encrypted and stored per provider, and only the screens write them.

Related: [Installation](installation.md), [Background jobs](background-jobs.md), [Security and privacy](security-and-privacy.md).
