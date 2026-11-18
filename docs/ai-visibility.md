# AI visibility

AI visibility asks ChatGPT, Claude, Gemini and Perplexity the questions you'd want to show up in, on a schedule, and records whether each answer mentions you, links to you, or links to somebody else. You write the prompts, and the dashboard reads the answers and keeps every one.

Optional. It's off until you turn it on, and the rest of the dashboard works without it. It needs an API key for at least one assistant, and each assistant bills you for every answer.

[Rank tracking](rank-tracking.md#ai-overviews) already records Google's AI overview on a results page. This page is about the chat assistants.

## Turn it on

Turn it on under Settings, Features. Then, on Settings, AI visibility:

1. Click Edit on an assistant, paste its API key, and click Save. Repeat for each assistant you want asked.
2. Write your prompts in Prompts, one per line.
3. Pick How often: Daily, Weekly or Monthly.
4. Check the monthly cap. It starts at 200 requests.

Keys are only ever entered on that screen. Until at least one assistant is on with a key and there's a prompt, Settings, Features shows AI visibility as Needs setup and names the first thing missing.

If the Features screen says it's not installed, run `bin/rails generate ahoy_dashboard:install --only ai_visibility`, then `bin/rails db:migrate`. See [Adding a feature later](installation.md#adding-a-feature-later).

Runs are started by the tick and done on the `low` queue. See [Background jobs](background-jobs.md).

## Assistants

| Assistant | Name |
|---|---|
| ChatGPT | `openai` |
| Claude | `anthropic` |
| Gemini | `gemini` |
| Perplexity | `perplexity` |

Every assistant that's on and has a key is asked. To stop asking one and keep its key and past answers, switch off "Ask" on its Edit form.

Each one is asked through its provider's API with web search on. Without search, an assistant answers from what it was trained on and has nothing to cite.

Models starts on the provider's default. Pick more from the list, or name others under Other models, and each one is asked every prompt, so each adds a request per prompt to every run. Changing the model changes the answers, so expect a step in the chart right after you switch.

These keys are separate from the ones [Ask](assistant.md) uses. The same OpenAI key can go in both, and it has to be entered in both.

A stored key is encrypted and never shown again. Remove deletes it. See [Removing a stored secret](security-and-privacy.md#removing-a-stored-secret).

## Prompts

Prompts go on Settings, AI visibility, one per line. Write them the way a person types into a chat box, as a whole question, like "what's a good self-hosted alternative to Plausible", rather than as a search phrase.

How often applies to the whole set. A run asks every prompt of every model of every assistant that's on, once. So 10 prompts to 4 assistants with one model each is 40 requests a run: about 170 a month on Weekly, about 1,200 on Daily.

Deleting a prompt deletes every answer to it.

## Suggestions from Ask

Ask can suggest prompts, worked out backwards from the visitors who converted. Ask it something like "suggest AI visibility prompts from last quarter's signups" and it reads what those visitors did, then lists a few prompts with the reason for each. Add puts one in the set, and "Add all" adds every one that isn't tracked yet. You stay in the conversation, and anything already in the set shows as Tracked.

It needs [Ask](assistant.md) set up, and AI visibility turned on. Only somebody who can change settings sees the Add buttons. Everybody else gets the list and a pointer to this screen.

### What it works back from

A conversion is a [goal](goals-and-funnels.md) completed in the date range. Ask it about one goal by name, or it uses every goal. With no goals at all, it uses the first time each user signed in, which needs `user_id` on `ahoy_visits`. With neither, it says to add a goal.

For each person who converted, it reads their visits from the 90 days before the conversion, including days before the date range, and adds them up:

- the channel their first visit came from
- the pages they landed on, on their first visit and on any visit
- the top Google searches that land on those pages, when [Search Console](search-console.md) is connected
- the paid search terms they arrived on, from `utm_term`
- the pages they read before converting, and how much more likely they were to read each one than everyone else in the range
- the pages AI assistants send people to, and how many of those people converted

Alongside that, it gets your tracked prompts, the prompts no assistant mentioned you in over the last 90 days, the domains cited instead, and your brand terms. It follows the conversation's filters, like the rest of Ask, and anything you keep out of Ask on Settings, Assistant stays out of this too.

### What it can't do

Nobody's prompt is recorded anywhere. A visit from ChatGPT says it came from `chatgpt.com` and nothing about what was asked. So every suggestion is the model's guess at what a person who did those things would type. The Google searches are the closest thing to real wording, and they're searches anyone made to reach that page, not only the people who converted.

Under 20 conversions in the range is too few to read much into, and Ask is told to say so and suggest a longer range. With Search Console not connected, it has page paths to go on and not much else.

It only sees what already converts. A topic where you show up nowhere won't have converters behind it, so the domains cited instead are the only part of this that points at ground you don't have yet.

### What it won't suggest

A suggestion is turned away when it's already tracked (ignoring case), repeats another one, is blank, or runs past 500 characters. Ten at most are shown at once, and never more than the set has room for. One with your domain or a brand term in it is shown with "Has your name in it", since a prompt that names you gets you mentioned whether you're any good or not.

Under the list is what adding them costs: requests per run for each one, roughly how many a month at your current How often, and how much of the cap is used. Adding a prompt doesn't run it. It's asked on the next scheduled run, like the rest.

## The monthly cap

The cap is in requests. It starts at 200, and 0 means no cap. Set it on Settings, AI visibility, where "Used this month" shows how many have gone out.

A run that doesn't fit in what's left of the cap is skipped. It isn't sent in part, so every run on the chart is the whole set.

The cap counts requests, not dollars. Each provider prices its own requests, and some charge extra for web search, so check their pricing pages before you raise it.

"Run now" on SEO, AI visibility runs the whole set once, after asking. It counts against the cap like any other run.

## What gets recorded

For every answer:

| Field | Is |
|---|---|
| Answer | The full text |
| Sources | The links the answer cites |
| Mentioned | Your domain or one of your brand terms appears in the text |
| Cited | One of the sources is on your domain, or a subdomain of it |
| Position | Where your domain sits in the answer's list of sources |
| Cited instead | The other domains in the sources |

Your domain is the site host on Settings, General. Your brand terms are the ones saved on [Brand vs. non-brand](seo-reports.md#brand-terms), matched the same way: ignoring case, spaces and hyphens, and skipping anything on the exclude list. With nothing saved there, the brand term is the first part of that host.

Mentioned and Cited are counted separately, since an answer can do either one without the other.

## SEO, AI visibility

The page follows the date range, and an Assistant menu narrows it to one assistant.

| Tile | Is |
|---|---|
| Mention rate | Answers in the range that mention you, as a share of all answers |
| Citation rate | Answers in the range that cite your domain, as a share of all answers |
| Prompts | How many prompts are in the set |
| Answers | Answers recorded in the range |
| Used this month | Requests spent against the monthly cap |

Below the tiles:

- "Mention rate over time", one line per assistant.
- "By assistant": answers, how many mentioned you, how many cited you, and your average position when cited.
- "Prompts you don't show up in": prompts where no assistant's latest answer mentions you.
- "Who gets cited instead": the domains cited most, by how many answers cite them.

Every table has a CSV button. See [CSV](seo-reports.md#csv).

## One prompt

Click a prompt to see every answer to it over time, assistant by assistant, with the full text, its sources, and where you're mentioned.

## What it can't tell you

- What a person sees in the app. The ChatGPT, Claude, Gemini and Perplexity apps add memory, the person's location and their own settings. The API answer is the nearest the dashboard can get to that, and it won't always match.
- A steady number from a few prompts. The same prompt gets a different answer from one run to the next, so a rate built on a handful of prompts swings every week. Read the line over months.
- What people actually ask. It only measures the prompts you wrote. A high mention rate on prompts with your name in them tells you very little.

## What's sent

Your prompts, and each assistant's key, go to every assistant you have a key for. Nothing about your visitors is sent. Answers are stored in your database until you delete the prompt. See [Security and privacy](security-and-privacy.md#ai-visibility).

There's no sample mode. Every run is a real request, and every provider bills for it.

Related: [Rank tracking](rank-tracking.md), [SEO reports](seo-reports.md), [Configuration](configuration.md#settings-features), [Background jobs](background-jobs.md), [Security and privacy](security-and-privacy.md).
