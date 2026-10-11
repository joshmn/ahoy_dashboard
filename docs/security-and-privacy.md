# Security and privacy

The dashboard runs inside your app, reads your database, and sends nothing anywhere until you turn on a feature that has to. This page covers who can get in, what's stored, and exactly what leaves your server for each feature.

## Access

Every dashboard request, including its stylesheet, script, icons and CSV exports, goes through `config.authorize`. There's no public route.

- No `authorize` means no access for anybody.
- A refused request gets a 404 by default, the same answer as if nothing were mounted, so the dashboard never confirms it exists to somebody who can't open it. Set `signed_in` and `sign_in_path` to send signed-out people to sign in instead. See [Installation](installation.md#whos-allowed-in).
- There are no roles. Everybody who gets in sees everything and can change every setting, including provider keys, and can read every assistant conversation.

Other protections on every response:

- CSRF protection, raising on a bad token.
- `X-Robots-Tag: noindex, nofollow`, plus the same robots meta tag in the page.
- The front end is served by the dashboard itself, from the gem, behind the same check. No CDN, no third-party fonts, no analytics script. The browser only ever talks to your app.

## Cookies

| Cookie | Holds | Lasts |
|---|---|---|
| `dash_view` | Your last date range, grouping, metric, comparison and crawler setting. Never filters. | 90 days |
| `dash_ask` | Whether the Ask panel is open, and which conversation is in it | 90 days |

Both are `HttpOnly` and `SameSite=Lax`, and neither grants anything. They aren't signed or encrypted, because they only hold preferences.

## Stored secrets

Keys typed on the settings screens (rank tracking provider keys, assistant keys, AI visibility keys, the Google OAuth client ID and secret) and the Google tokens are encrypted before they're stored. Each is an `ActiveSupport::MessageEncryptor` blob, keyed from your app's `secret_key_base` with a separate salt per purpose, so a value written for one purpose can't be read as another.

- A stored key is never shown again. The form fields are always empty, and a blank field keeps what's stored.
- A stored key can be removed from its own settings screen. See [Removing a stored secret](#removing-a-stored-secret).
- Keys are only ever entered on a settings screen. The dashboard doesn't read them from environment variables, Rails credentials or the initializer.

Changing `secret_key_base` makes every stored secret unreadable. So does changing `config.active_support.key_generator_hash_digest_class`, or loading a database dump into an app with a different `secret_key_base`. Nothing raises. The keys read as missing and Google reads as not connected. To recover, re-enter each key on its settings screen and reconnect Google.

The dashboard uses its own encryption rather than Active Record encryption so that installing it doesn't change how the rest of your app handles keys.

### Removing a stored secret

A Remove button sits beside every stored secret: Settings, Assistant (each provider's key), Settings, Search Console (client ID, client secret), Settings, Search provider (each provider's key, and DataForSEO's login and password), and Settings, AI visibility (each assistant's key). It's only shown once a value is stored.

It asks first, naming what stops working, for example "Remove the stored Anthropic key? The assistant stops answering until a key is saved again."

Removing deletes the encrypted value and keeps the row and its other settings. The field then reads "Nothing stored." Nothing else supplies a key, so whatever used it stops until you save a new one.

Removing the Search Console client ID or secret stops syncing until one is saved again. The Google connection itself stays until you disconnect it.

## What leaves your server

Out of the box, nothing leaves except site icons (see below). Each other outbound call belongs to a feature you turn on yourself.

### Site icons

To show a referrer's icon, your server asks `icons.duckduckgo.com` for `/ip3/<domain>.ico`, sending the domain name and a User-Agent of `<your site host> favicon proxy`, built from the host on Settings, General (`ahoy_dashboard favicon proxy` when no host is set). It only asks for domains that have referred a visit to your site, caches each answer (30 days for an icon, a day for none, 10 minutes after a failure), and takes nothing bigger than 64 KB. The browser never contacts DuckDuckGo.

DuckDuckGo learns the list of sites that link to you, one domain at a time, from your server's address. Turn it off by switching off Site icons on Settings, Features. It's the one feature that starts on.

### The place list

Once a month, with the place list turned on, your server downloads a published list of search locations. By default that's a CSV from `cdn.dataforseo.com`, and the address can be changed under Advanced on Settings, Search provider. The request carries the same User-Agent as the icon fetch and nothing else. No key is sent.

### Search Console

Your server talks to Google's OAuth and Search Console APIs with your Google account's token. The only permission requested is `https://www.googleapis.com/auth/webmasters.readonly`, which is read only. What Google sends back (queries, pages, clicks, impressions, positions) is stored in your database. Nothing about your visitors is sent to Google. See [Search Console](search-console.md).

### Rank tracking, keyword research and backlinks

Your server sends the provider you picked (SerpApi, SearchApi or DataForSEO) the search phrases you track, the places and devices to search from, your own domain for backlinks, and your key. Nothing about your visitors is sent. With the sample provider, nothing is sent at all.

### Assistant

Every question asked in Ask sends the model provider:

- your API key
- a system prompt with your site host, today's date and your time zone
- when asked from the Ask panel, the screen's name, date range and filter labels, like "Country is US". A filter on a value puts that value in the prompt.
- the question, and up to 20 earlier messages from the same conversation, text only
- the tool results the model asked for: headline numbers, and breakdowns by any dimension, which can mean page paths, referrer URLs, UTM tags, cities, custom property values, Search Console queries, and your tracked keywords and ranking URLs
- the error message, when a tool fails, which can be a database error

It doesn't send raw visits or events, visitor tokens, or anything about the person asking. It does send whatever values your dimensions hold, so if your app registers an IP address dimension, IP addresses can be in a tool result.

With LM Studio on its default endpoint, `http://localhost:1234/v1`, it all stays on that machine. Change the endpoint and it goes wherever that points. See [Assistant](assistant.md).

### AI visibility

Each run sends your prompts, with that assistant's key, to every assistant that's on and has a key. Web search is turned on, since an answer with no search has nothing to cite. Nothing about your visitors is sent.

Answers are stored in your database until you delete the prompt that produced them. See [AI visibility](ai-visibility.md).

### Alerts

The alert emails go through your app's own mailer to the recipients on Settings, Emails. `config.alert_notifier` is your own code, so where it sends things is up to you.

### Email reports

The traffic email carries whole-site totals and the top pages, sources and countries for the period, and goes through your app's own mailer to the recipients you set. See [Email reports](email-reports.md).

## CSV exports

Exports hold the values your visitors brought with them: paths, referrers, UTM tags. SEO exports hold search queries and URLs from Google and your search provider. None of them are escaped for spreadsheets, so a value starting with `=`, `+`, `-` or `@` may run as a formula when the file is opened in Excel or Google Sheets. Open exports from an untrusted site as text, or import them rather than double-clicking.

## Content Security Policy

The dashboard sets no Content Security Policy of its own. If your app sets a strict one, it applies to the dashboard too, and the dashboard needs:

- `script-src 'self'`. The script tag carries no nonce, so a nonce-only policy blocks it.
- `style-src 'self' 'unsafe-inline'`. Bar widths and table columns are inline `style` attributes.
- `img-src 'self' data:`. The page icon and some backgrounds are `data:` URLs.
- `font-src 'self'` and `connect-src 'self'`.

## Data retention

The dashboard never deletes your ahoy data, and it never deletes most of what it stores either: Search Console rows, rank check results and the raw provider pages behind them, keyword ideas, backlinks, alerts, assistant conversations and AI visibility answers all pile up. Nothing prunes them. AI visibility answers go when you delete the prompt that produced them. The only thing pruned is the job run log, kept to the last 100 runs of each job.

## Visitor data

The dashboard reads the columns listed in [Tracking](tracking.md#visits) and nothing else. It doesn't read `ip`, `user_id`, `user_agent` or coordinates unless your app registers a dimension over them. What ahoy collects, and whether you need consent for it, is decided in your ahoy setup, not here.

Related: [Installation](installation.md), [Configuration](configuration.md), [Assistant](assistant.md).
