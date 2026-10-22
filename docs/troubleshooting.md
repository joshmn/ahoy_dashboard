# Troubleshooting

Find what you're seeing in the left column. Each feature's own page has more.

## Getting in

| You see | Why | Fix |
|---|---|---|
| Every dashboard URL is a 404, even for admins | `config.authorize` isn't set, or returns false. A refused request looks exactly like a missing route, on purpose. | Set `authorize`. See [Who's allowed in](installation.md#whos-allowed-in). |
| `NoMethodError` for `current_user` or `admin?` on every request | The generated `authorize` assumes a `current_user` with an `admin?` method | Write your own lambda |
| Signed-out people land on your home page | `signed_in` returns false and `sign_in_path` is still `"/"` | Set `sign_in_path` |
| `UnsafeRedirectError` when signed out | `sign_in_path` is a URL on another host | Use a path, or a URL on the same host |
| Your helpers or `Current` values are missing in `authorize` | The default controller parent is `ActionController::Base` | Configure `parent_controller` or look the user up in the lambda. See [Using your ApplicationController](installation.md#using-your-applicationcontroller). |
| Links from Ask point at `/` | The mount has a custom `as:` name | Mount without `as:` |

## Installing and booting

| You see | Why | Fix |
|---|---|---|
| `Unknown migration version 8.1` | Rails 8.0 | Rails 8.1 or newer |
| A migration fails on `create statistics` | Postgres older than 14, or `ahoy_events` doesn't exist yet | Postgres 14 or newer, and install ahoy first |
| The first migration fails with `relation "ahoy_visits" does not exist` | Ahoy isn't installed yet | Install ahoy and run its migrations first |
| A page says "Not installed yet" and shows two commands | That feature's tables aren't in your database | Run the commands it shows, from your app's folder, then reload. See [Adding a feature later](installation.md#adding-a-feature-later). |
| "Turn on" on Settings, Features is disabled | The feature isn't installed, and a feature without tables can't be switched on | Install it first. See [Adding a feature later](installation.md#adding-a-feature-later). |
| A feature says Needs setup on Settings, Features | It's on, but something it needs is missing, like a key, a provider, a host, a prompt or a rule. Only the first missing thing is shown. | Click "Set it up" beside it, fix that, and come back to see if anything else is missing |
| The generator stops with `this app ran an older ahoy_dashboard but is missing some of its migrations: ...` | The app ran an older version, and neither `db/migrate` nor the database has what some of those migrations made | Copy the named files from the version you had, run them, then run the generator again. If the message says the database could not be reached, start it and run the generator again first. See [Upgrading](installation.md#upgrading). |
| A migration stops with `Tracked keywords differ only by capitals` | Two tracked keywords are the same search apart from capitals, like "Best CRM" and "best crm", so the same results were being bought twice. The message lists their IDs. | Keep one of each on Settings, Rank tracking, delete the rest, then migrate again |
| The generator says `separate features with commas, not spaces` | `--only` or `--skip` got a list with spaces | Use `--only serp,alerts` |
| `NameError` at boot, naming your mailer | `alerts[:parent_mailer]` names a class that doesn't exist | Fix the name |
| The page loads with no styles and nothing clicks | The stylesheet or script didn't load: a bad `assets_root`, a Content Security Policy blocking it, or a proxy stripping the session cookie | Open `<mount>/assets/<build>/ahoy_dashboard.css` while signed in and see what comes back. See [Content Security Policy](security-and-privacy.md#content-security-policy). |
| Slow dashboard on a big site | The index migration hasn't run yet, or planner statistics were lost to `db:schema:load` | Run the generator again and migrate (see [Upgrading](installation.md#upgrading)), then see [Planner statistics](installation.md#planner-statistics) |

## The numbers

| You see | Why | Fix |
|---|---|---|
| Zero pageviews while ahoy has events | Page views aren't named `page_view`, or have no `path`. ahoy.js's `trackView` sends `$view`, which isn't read. | Send `page_view` with a `path`. See [Page views](tracking.md#page-views). |
| Scroll depth 0% and time on page 0s | Nothing sends `engagement` events. The dashboard doesn't include a script for them. | See [Scroll depth and time on page](tracking.md#scroll-depth-and-time-on-page) |
| Your own site shows as a Referral source | The site host on Settings, General is blank or wrong | Set it there. It takes effect on the next request, with no restart. |
| Times and days look off by hours | The time zone is still UTC, the default | Pick yours on Settings, General |
| Looking at the dashboard adds visits | ahoy records visits on the server and the dashboard's path isn't excluded | See [Keep the dashboard out of your own numbers](installation.md#keep-the-dashboard-out-of-your-own-numbers) |
| Visitors on a card or the chart add up to more than the total | A visitor who shows up in two rows, or on two days, counts in both | Nothing. See [Unique visitors](metrics-and-dimensions.md#unique-visitors). |
| The Properties card says "No custom properties in this range" | No event in the range carries a property, and none is shown on Settings, Custom properties | Send properties with your events, or add one. See [Custom properties report](custom-properties.md#custom-properties-report). |
| A goal reads 0, or fewer than its event | An earlier goal in the list matches the same events and claims them first | Move the narrower goal up. See [Goal order](goals-and-funnels.md#goal-order). |

## Background jobs

| You see | Why | Fix |
|---|---|---|
| "Nothing has run yet." on Settings, Jobs | The tick has not started work yet | See [Schedule the tick](background-jobs.md#schedule-the-tick) |
| Embedded scheduling stops while the site is quiet | The host retired every web worker, or no worker has received its first request | Keep a web worker available and send an initial request, or use an [external scheduler](background-jobs.md#external-scheduler) |
| A job stays Running, then shows "Did not finish" | Nothing works the `low` queue, or the worker died | Run a worker on `low` and `default` |
| A job shows Off | One of its conditions isn't met, and the row says which | Follow its "Set it up" link |
| A job says Ran and didn't work | Several jobs record their own failures somewhere else | See [What "Ran" means](background-jobs.md#what-ran-means) |
| "Run history is not set up yet" | The migrations haven't all run | `bin/rails db:migrate` |
| Keys saved on settings screens are gone, and Google says not connected | `secret_key_base` changed | Enter the keys again and reconnect Google. See [Stored secrets](security-and-privacy.md#stored-secrets). |

## Search Console

| You see | Why | Fix |
|---|---|---|
| Settings, Search Console says "There is no URL to add yet." | No site host or canonical host on Settings, General, and no redirect URL override on Settings, Search Console | Set the site host on Settings, General |
| Google shows `redirect_uri_mismatch` | The redirect URI registered with Google isn't exactly the one sent | See [The redirect URI](search-console.md#the-redirect-uri) |
| "That did not come back from a sign-in this browser started." | The callback landed on a different hostname or browser than the one that started | Connect from the same address the redirect URI uses |
| Reconnecting every 7 days | The Google Cloud consent screen is still on Testing | Set it to In production |
| The newest 3 days are missing | Google finalizes days 3 days late. Only the Google search card shows unfinished days. | Nothing |
| The card and Performance disagree on a query | They can cover different days | See [Why the numbers don't add up](search-console.md#why-the-numbers-dont-add-up) |
| A gap of missing days in the middle | An outage longer than 7 days. The nightly job only re-reads the last week. | "Fill these days" on Settings, Search Console. See [Fill missing days](search-console.md#fill-missing-days). |
| A device or a country adds up to less than All devices or All countries | Rows synced before device and country were pulled read as Unknown, and Google hides more queries the finer you cut | Nothing. See [Device and country](search-console.md#device-and-country). |

More in [When it stops syncing](search-console.md#when-it-stops-syncing).

## Rank tracking

| You see | Why | Fix |
|---|---|---|
| "These are sample results." | The sample provider is active | Pick a real one on Settings, Search provider |
| Every check button is disabled | Tracking is off, the provider has no key, or the cap is spent. The button says which. | See [Check now](rank-tracking.md#check-now) |
| A keyword's "Last checked" never moves | Its checks keep failing. They're retried every hour. | See [When checks fail](rank-tracking.md#when-checks-fail) |
| Spending with no monthly cap | The provider's monthly cap is 0, which means no cap | Set a cap on the provider's Edit form on Settings, Search provider |
| The spend card's bars don't add up to the month's total | Daily rows start at the upgrade. Rank checks before it are rebuilt from stored searches; keyword lookups and backlink syncs before it aren't recorded anywhere | Nothing. It's right from the first full month. See [The spend card](rank-tracking.md#the-spend-card) |
| No warning at 80% of the cap | The "Nearing the monthly cap" rule is off, or the provider has no cap | Switch it on at Settings, Alerts, and set a cap on Settings, Search provider |
| Positions jumped after switching providers | DataForSEO counts results above yours that the others don't | See [Positions differ between providers](rank-tracking.md#positions-differ-between-providers) |

## Assistant

| You see | Why | Fix |
|---|---|---|
| "The assistant is off. Turn it on under Settings, Features." | The assistant is switched off | Turn it on under Settings, Features. If it's on and Ask still won't answer, the notice says why. |
| "That answer did not come back. Ask the question again." | The provider refused or failed | Check Last error on Settings, Assistant, or the log for `dashboard assistant failed:`. See [When it doesn't answer](assistant.md#when-it-doesnt-answer). |
| "Reading the data" forever | Nothing works the `default` queue | Run a worker on `default` |
| Last error on DeepSeek says "402 from the model: the account is out of credit" | The DeepSeek balance is empty | Top it up at DeepSeek. The dashboard doesn't retry a 402. |
| Last error on DeepSeek mentions `reasoning_content` | DeepSeek refused the empty reasoning sent in place of one it didn't write, usually in a conversation another reader started | Start a new conversation. See [DeepSeek](assistant.md#deepseek). |
| The key saved on Settings, Assistant isn't used | The provider isn't marked "Use this one" | See [Which settings win](assistant.md#which-settings-win) |
| Search Console and ranking answers ignore the conversation's filters | Those rows have no visitor attached, so there's nothing to filter | Nothing. The answer says it wasn't filtered. See [Filters](assistant.md#filters). |

## Alerts

| You see | Why | Fix |
|---|---|---|
| Nothing ever fires | Alerts off, no rule on, or the data a rule reads isn't set up. Rank tracking rules also need a site matching the site host on Settings, General, and recent checks. | See [When nothing fires](alerts.md#when-nothing-fires) |
| The traffic rules say "Needs 28 days of visits" | They compare against the same hour and weekday over the last 28 days | Wait. See [Traffic rules](alerts.md#traffic-rules). |
| A Search Console alert fires days after the drop | Search Console rules only read finished days, and Google finishes a day 3 days late | Nothing. See [Search Console rules](alerts.md#search-console-rules). |
| No alert emails | No period or no recipients for alert emails on Settings, Emails, or no host in the mailer's `default_url_options` | See [Alert emails](alerts.md#alert-emails) |
| Every alert email says no searches were checked | Rank tracking rules are on and no site matches the site host on Settings, General | Add your site on Settings, Rank tracking |

## Email reports

| You see | Why | Fix |
|---|---|---|
| No traffic emails | Email reports are off on Settings, Features, no period or no recipients are set for traffic emails on Settings, Emails, or the mailer has no `host` | See [When no email arrives](email-reports.md#when-no-email-arrives) |
| The first weekly email hasn't come | It covers a finished Monday to Sunday | Wait for the Monday after you turned it on |

## AI visibility

| You see | Why | Fix |
|---|---|---|
| SEO, AI visibility is empty | AI visibility is off on Settings, Features, no assistant is on with a key, there are no prompts, the tick isn't scheduled, or nothing works the `low` queue | See [Turn it on](ai-visibility.md#turn-it-on) |
| An assistant is never asked | It has no key, or its "Ask" switch is off | Edit it on Settings, AI visibility |
| A run was skipped | It didn't fit in what was left of the monthly cap | Raise the cap, or ask fewer prompts or fewer assistants. See [The monthly cap](ai-visibility.md#the-monthly-cap). |
| The mention rate jumps from week to week | Answers change from run to run, and a few prompts make a noisy rate | Add prompts, and read the line over months. See [What it can't tell you](ai-visibility.md#what-it-cant-tell-you). |

Related: [Installation](installation.md), [Configuration](configuration.md), [Background jobs](background-jobs.md).
