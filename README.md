# ahoy_dashboard

A self-hosted analytics and SEO dashboard for Rails apps that already record visits with [ahoy_matey](https://github.com/ankane/ahoy). It's a Rails engine: it mounts inside your app, reads your `ahoy_visits` and `ahoy_events` tables where they already sit, and adds Search Console, rank tracking and an assistant on top.

Nothing is sent anywhere to be counted. There's no tracking script, no third-party analytics service and no second database. Your numbers stay in your Postgres.

## What's in it

### Built in

- [Dashboard](docs/dashboard.md): visitors, visits, pageviews, bounce rate, visit duration and scroll depth over any date range, with a comparison period, a chart you can drag to zoom, annotations, and cards for sources, pages, locations and devices.
- [Filters and segments](docs/filters-and-segments.md): narrow everything to a page, a source, a country or a custom property, with "or" when you want either, save the combination, and fold URLs into page groups.
- [Excluded traffic](docs/excluded-traffic.md): leave data centers, scanners and your own office out of every number, the emails and the alerts, with a switch to see them again.
- [Goals and funnels](docs/goals-and-funnels.md): count page visits and custom events as conversions, with revenue, and see where people drop out of a sequence of steps.
- [Custom properties](docs/custom-properties.md): break numbers down by anything your events carry.
- [Page journey](docs/page-journey.md): where people go next from any page, one step at a time.
- [Visitor journey](docs/visitor-journey.md): one person's every visit and event in order, merged across devices once they sign in, with links your app can use.
- [Explore](docs/explore.md): one number broken down by one dimension, with the columns you want. Save a question, and pin up to three to the dashboard.
- Realtime, CSV exports, a command palette, and a view that remembers where you left it.

### Optional

Each of these has its own tables, so you install only the ones you want, and each is off until you turn it on under Settings, Features. Most need an outside account: Google for Search Console, a search data provider for rank tracking, DataForSEO for keyword research and backlinks, and an API key for AI visibility and Ask. [What's optional](docs/configuration.md#whats-optional) lists every feature and what it needs.

- [Search Console](docs/search-console.md): your Google queries, pages, clicks, impressions and positions by device and country, pulled nightly and kept past Google's 16 months.
- [Rank tracking](docs/rank-tracking.md): where you rank for searches you pick, from places you pick, next to your competitors, with tags, AI overview citations and a monthly spend cap.
- [SEO reports](docs/seo-reports.md): visibility, position changes, landing pages, keyword gap, volatility, SERP features, opportunities, cannibalization, brand vs. non-brand, and search to conversion, all from data already stored.
- [Keyword research and backlinks](docs/keyword-research-and-backlinks.md): bought from DataForSEO by the row, and cached.
- [AI visibility](docs/ai-visibility.md): whether ChatGPT, Claude, Gemini and Perplexity mention you or cite you for the prompts you write.
- [Alerts](docs/alerts.md): hear about a ranking drop, falling search clicks, a goal that stopped converting, a failed job or a traffic spike, by email or in your own code.
- [Email reports](docs/email-reports.md): a daily, weekly or monthly email of your traffic.
- [Ask](docs/assistant.md): ask questions about your data in plain English, about the page and filters you're looking at, with the charts it read and links to each screen. Runs on Anthropic, OpenAI, DeepSeek, or any OpenAI-compatible server, local or hosted.

## Requirements

- Ruby 2.5 or newer, using the version required by your Rails release
- Rails 6.0 or newer
- PostgreSQL 14 or newer, 15 recommended
- ahoy_matey writing `ahoy_visits` and `ahoy_events`
- A job backend, for the optional features that run in the background: Search Console, rank tracking, keyword research, backlinks, the place list, AI visibility, alerts, email reports and the assistant

CSS, JavaScript and fonts ship prebuilt. The engine runs independently of the host asset pipeline, Hotwire, Redis and Action Cable. See the [compatibility matrix](docs/installation.md#compatibility-matrix) for the configured Rails and Ruby test combinations.

## Install

It isn't on RubyGems. Vendor it into your app:

```ruby
gem "ahoy_dashboard", path: "vendor/gems/ahoy_dashboard"
```

```sh
bundle install
bin/rails generate ahoy_dashboard:install
bin/rails db:migrate
```

The generator writes `config/initializers/ahoy_dashboard.rb`, mounts the engine at `/analytics-dashboard` and copies the migrations, every optional feature included. Pass `--only serp,alerts` or `--skip keywords,backlinks` to pick. Running it again later adds a feature or brings an install up to date.

The initializer says who's allowed in. It's the one thing you have to check:

```ruby
AhoyDashboard.configure do |config|
  config.authorize = ->(controller) { controller.current_user&.admin? }
end
```

Restart and open `/analytics-dashboard`. Until `authorize` lets you in, every dashboard URL is a 404.

Everything else is set in the dashboard. Set your site host and time zone on Settings, General, then turn on what you want under Settings, Features. Keys and passwords go on the screen for each feature. Nothing is read from environment variables or Rails credentials.

For scheduled work, opt in to the [embedded scheduler](docs/background-jobs.md#embedded-scheduler) with `config.embedded_scheduler = true` in the initializer, or schedule `AhoyDashboard::TickJob` every minute through your job backend. The embedded loop starts on each web worker's first request and still uses Active Job for the resulting work.

Your app has to record page views as `page_view` events with a `path`. [Tracking](docs/tracking.md) has the details. [Installation](docs/installation.md) covers the generator, upgrading, the mount path, who's allowed in, and keeping the dashboard out of its own numbers. [Configuration](docs/configuration.md) covers every screen and what's left in the initializer.

## Docs

Getting set up

- [Installation](docs/installation.md)
- [Configuration](docs/configuration.md)
- [Hosting multiple sites in a separate app](docs/extending.md#hosting-the-dashboard-in-a-separate-app)
- [Tracking](docs/tracking.md)
- [Background jobs](docs/background-jobs.md)

Analytics

- [Dashboard](docs/dashboard.md)
- [Metrics and dimensions](docs/metrics-and-dimensions.md)
- [Filters and segments](docs/filters-and-segments.md)
- [Excluded traffic](docs/excluded-traffic.md)
- [Goals and funnels](docs/goals-and-funnels.md)
- [Custom properties](docs/custom-properties.md)
- [Page journey](docs/page-journey.md)
- [Visitor journey](docs/visitor-journey.md)
- [Explore](docs/explore.md)
- [Email reports](docs/email-reports.md) (optional)

SEO, all optional

- [Search Console](docs/search-console.md)
- [Rank tracking](docs/rank-tracking.md)
- [SEO reports](docs/seo-reports.md)
- [Keyword research and backlinks](docs/keyword-research-and-backlinks.md)
- [AI visibility](docs/ai-visibility.md)
- [Alerts](docs/alerts.md)

Everything else

- [Assistant](docs/assistant.md) (optional)
- [Extending](docs/extending.md)
- [Security and privacy](docs/security-and-privacy.md)
- [Troubleshooting](docs/troubleshooting.md)

## License

MIT
