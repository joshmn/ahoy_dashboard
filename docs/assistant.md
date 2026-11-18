# Assistant

Ask answers questions about your site in plain English: "which pages lost visitors this month", "where is this traffic coming from", "what changed since last week". It reads the same data the dashboard does, through the same queries, and it's told to answer only from what it read. Answers come with the charts and tables it read, and a link to open each one on its own screen. Those came straight from your data, so when a sentence and a chart disagree, trust the chart.

The model runs at a provider you pick: Anthropic, OpenAI, DeepSeek, or any server that speaks OpenAI's Chat Completions format. That last one covers a model on your own machine (LM Studio, Ollama, vLLM) and hosted ones (OpenRouter, Groq, Together). You bring the key, and the provider bills you for what it reads and writes.

Optional. It's off until you turn it on, and the rest of the dashboard works without it. It needs an Anthropic, OpenAI or DeepSeek key, or a Chat Completions server it can reach.

## Turn it on

Turn it on under Settings, Features. That's the kill switch. With it off, nothing is ever sent, whatever Settings, Assistant says.

Then give it a key on Settings, Assistant. See [Set up a provider](#set-up-a-provider). Until a provider is set up there, Settings, Features shows the assistant as Needs setup and says what's missing.

If the Features screen says the assistant is not installed, its tables aren't in your database yet. Run the two commands it shows, which are `bin/rails generate ahoy_dashboard:install --only assistant` and `bin/rails db:migrate`. See [Adding a feature later](installation.md#adding-a-feature-later).

Answers are written by a background job on the `default` queue. If nothing works that queue, every question waits forever. See [Background jobs](background-jobs.md).

## Providers

The dashboard calls them readers.

| Reader | Shown as | Endpoint | Default model | Needs a key |
|---|---|---|---|---|
| `anthropic` | Anthropic | `https://api.anthropic.com/v1` | `claude-sonnet-4-6` | Yes |
| `openai` | OpenAI | `https://api.openai.com/v1` | `gpt-4.1` | Yes |
| `deepseek` | DeepSeek | `https://api.deepseek.com` | `deepseek-flash` | Yes |
| `compatible` | OpenAI-compatible | `http://localhost:1234/v1` | None, so name one | Only if the server wants one |

Each one is called through its own API. Anthropic goes through its Messages API and OpenAI through its Responses API. DeepSeek and OpenAI-compatible both go through the Chat Completions format.

The Endpoint field on Anthropic, OpenAI and DeepSeek is only for a proxy in front of that provider's own API. Everything else goes through OpenAI-compatible.

### DeepSeek

DeepSeek thinks before every answer here. Thinking is already DeepSeek's default, and the dashboard asks for it by name anyway (`"thinking": {"type": "enabled"}`), so a change to DeepSeek's default doesn't quietly change your answers. That has a few consequences:

- No temperature is sent. Thinking ignores it.
- The default output limit is 65,536 tokens, which is DeepSeek's own default with thinking on. The thinking counts against that limit, so a small Output limit cuts answers off partway, sometimes before they start.
- Every request carries the tools, and DeepSeek wants the reasoning behind each earlier answer sent back on any request that carries tools. So the reasoning is stored with each answer, and every assistant message DeepSeek gets carries a `reasoning_content`: the stored one when DeepSeek wrote that answer through the same endpoint, an empty one when it didn't. DeepSeek never gets another reader's reasoning. See [What's sent to the provider](#whats-sent-to-the-provider).
- The same goes inside one answer: a tool round that came back with no reasoning goes back with an empty one.
- DeepSeek's Chat Completions API won't take tool calls it didn't just write, so earlier answers go back as their text and reasoning, without the tools they called. A follow-up that needs those figures reads them again.

`deepseek-flash` and `deepseek-v4-pro` are the two models DeepSeek lists. The Model box suggests whatever your key can use.

A conversation started on another reader carries on fine on DeepSeek: its earlier answers go back with an empty `reasoning_content`. That leans on reports from other integrations that DeepSeek checks the field is there rather than what's in it, which nobody here has tried against the live API. If DeepSeek still refuses with a 400 that says `The reasoning_content in the thinking mode must be passed back to the API`, start a new conversation.

### OpenAI-compatible

For anything that speaks OpenAI's Chat Completions format. With Endpoint blank it's LM Studio on this machine. For anything else, put the server's base address in Endpoint:

| Server | Endpoint | Key |
|---|---|---|
| LM Studio | `http://localhost:1234/v1` | None |
| Ollama | `http://localhost:11434/v1` | None |
| vLLM | `http://localhost:8000/v1`, or wherever you serve it | Only if you started it with one |
| OpenRouter | `https://openrouter.ai/api/v1` | Yes |
| Groq | `https://api.groq.com/openai/v1` | Yes |
| Together | `https://api.together.xyz/v1` | Yes |

The key is optional. A key you save goes to the server as a bearer token. With none saved, the dashboard sends a placeholder, which local servers ignore and hosted ones refuse.

There's no default model, so name one exactly as the server lists it. Pick one that can call tools: every answer starts with a tool call, and a server whose model can't make one usually refuses the request outright.

The output limit defaults to 4,096 tokens, which suits a local model with a small context window. Raise it for a hosted model.

Some servers send the model's reasoning back as `reasoning_content`, the way DeepSeek does (vLLM with a reasoning parser, for one). Those get it back on the answer it came with, as long as the same server at the same endpoint wrote it. Nothing else about the history changes: earlier tool calls still go back with a note that their figures weren't kept. A server that never sends reasoning never gets any, not even an empty one.

#### Upgrading from LM Studio

The LM Studio reader is now OpenAI-compatible. A provider saved as `lmstudio` keeps working with nothing to do: same model, same endpoint (blank still means `http://localhost:1234/v1`), same tuning, still marked "Use this one". Settings, Assistant shows it as OpenAI-compatible, and the first time you save it the row moves to the new name, `compatible`. Old links to `/settings/assistant_providers/lmstudio/edit` open the same form.

## Set up a provider

1. Open Settings, Assistant and click Edit on the reader.
2. Paste the API key. OpenAI-compatible takes one only if its server wants one.
3. Leave Model blank for the default, or name one. OpenAI-compatible has no default, so it needs the model name exactly as the server lists it. See [Model suggestions](#model-suggestions).
4. Leave Endpoint blank unless you're pointing at a proxy, or pointing OpenAI-compatible at something other than LM Studio on this machine. The hint under the box says what the address usually ends in.
5. Leave Temperature and Output limit blank unless you want to change them. See [Which settings win](#which-settings-win).
6. Switch on "Use this one".
7. Click "Save provider".

Keys are encrypted before they're stored and never shown again. A blank box keeps the stored key, so you can change the model without pasting the key again.

A stored key gets a Remove button beside it, shown only once a key is stored. It asks first, naming what stops working, for example "Remove the stored Anthropic key? The assistant stops answering until a key is saved again." On OpenAI-compatible it says the assistant asks without a key from then on, which only works if the server needs none. Removing deletes the encrypted value and keeps the rest of the row, and the field then reads "Nothing stored." There's nowhere else for a key to come from, so a reader that needs one stops until you save a new one.

The list on Settings, Assistant shows what the reader in use is really sending, not what's stored on the row. Its Key column reads Stored here or Missing (Not needed on OpenAI-compatible with no key saved), and its Model column shows the model that's actually sent. Every other row shows what it would send if you switched it on. A row with saved settings that isn't marked "Use this one" carries the note "Saved without Use this one, so the settings saved here are not used." Last error shows the message and how long ago it happened, and clears the next time you save that provider.

For a server on your own machine, start it and load a model first.

### Model suggestions

The Model box suggests models as you type. The page opens with the built-in list straight away, then asks the provider for its own list and swaps that in when it answers. Nothing on the page waits for it, and with JavaScript off you get the built-in list.

| Reader | Asks | Keeps |
|---|---|---|
| Anthropic | `GET /v1/models` with `x-api-key` and `anthropic-version: 2023-06-01`, a page of 1,000 at a time | Active models. Deprecated and retired ones are left out. |
| OpenAI | `GET /v1/models` with the key as a bearer token | Chat models |
| DeepSeek | `GET /models` with the key as a bearer token | Chat models |
| OpenAI-compatible | `GET {endpoint}/models`, with the key as a bearer token if one is saved | Chat models |

OpenAI and Chat Completions servers don't say what a model is for, so chat models are picked by name: anything that looks like an embedding, speech, transcription, image, video, moderation, realtime, audio, search or computer-use model is left out. LM Studio lists its embedding models alongside the chat ones, and this is what keeps them out of the box. A list that dates its models (OpenAI's does, OpenRouter's does) is sorted newest first. The rest keep the server's order.

A list that came back is kept for 10 minutes, per reader, endpoint and key, so changing any of the three asks again. A failure or an empty list isn't kept, and the box keeps the built-in list. Anthropic, OpenAI and DeepSeek aren't asked at all until a key is saved.

The request waits up to 3 seconds to connect and 5 for the answer, and tries once more if the network drops it. It goes only to the endpoint saved with the key, and a redirect counts as a failure rather than being followed, so the key never ends up anywhere else.

They're suggestions. Whatever you type in the box is what's saved and sent.

## Which settings win

Only the provider marked "Use this one" counts. A provider saved without it is ignored completely: its key, its model, its endpoint and its tuning.

| Setting | With a provider marked "Use this one" | With none |
|---|---|---|
| Reader | That provider | Anthropic |
| Model | Its Model box, or the reader's default | Anthropic's default, `claude-sonnet-4-6` |
| Key | Its stored key | None, so nothing is asked |
| Endpoint | Its Endpoint box, or the reader's default | Anthropic's default |
| Temperature | Its Temperature box. Blank sends none and the model uses its own. | None sent |
| Output limit | Its Output limit box, or the reader's default (below) | Anthropic's default |

The default output limit depends on the reader. Anthropic gets 64,000 tokens, or 8,192 on the older Claude 3, Opus 4.0, Opus 4.1 and Sonnet 4.0 models. OpenAI gets 32,000. DeepSeek gets 65,536, because its thinking counts against the limit. OpenAI-compatible gets 4,096. The form shows the default for the model you've typed as the box's placeholder.

Some models ignore temperature, like Anthropic's models that think before answering, GPT-5, GPT-6 and the o models. DeepSeek ignores it while thinking, so it's never sent there. The hint under the box says which.

Everything here is set on Settings, Assistant. Nothing in the initializer touches the assistant. See [Configuration](configuration.md#whats-left-in-the-initializer).

## Asking

### The Ask screen

Ask in the header, or `/chats`, lists your conversations. "Start a question" opens a new one with three to pick from:

- Which pages lost visitors this month?
- Where is the traffic coming from?
- What changed since last week?

Or type your own. Enter sends, and Shift+Enter starts a new line.

### Asking about the page you're on

On any other screen, Ask opens a panel beside the page, so the numbers stay in view while you ask about them. The panel stays open, with the same conversation in it, as you move around.

The panel knows what you're looking at. The first question saves the screen, the date range and the filters onto the conversation, and the model is told about them. "About: Dashboard, last 7 days, filtered to Country is US" at the top of the panel is exactly what it was told. Follow-ups stay about that slice, even from another screen. "New" starts a fresh conversation about the page behind the panel now.

The saved filters also reach the tools that read your visits. See [Filters](#filters).

### Reading an answer

While it works, the answer shows what it's doing: "Reading the data", then "Read the headline figures and a breakdown" as it calls tools, then the text as it's written.

A finished answer has:

- The text, with basic formatting and tables.
- Up to 6 charts, tables or tiles, one for each thing it read, each with a link like "Open on the dashboard" or "Open in Explore" that opens that screen on the same dates.
- A line saying what it read, and how many tokens the answer took. Answers that read nothing show neither.

If a table or chart can't fit everything a tool read, past 25 rows, 400 points or the 6th chart, the answer says what's missing instead of leaving it out.

## What it can read

The model gets six tools, and two more while [AI visibility](ai-visibility.md) is on. It can only read, and every read goes through the same queries as the dashboard, so its dates and numbers match what the dashboard shows. The one thing it can put on screen that isn't a chart or a table is a list of suggested prompts, and nothing on that list is saved until a person clicks Add.

| Tool | Reads | Draws |
|---|---|---|
| `traffic_summary` | Visitors, visits, pageviews, views per visit, bounce rate, visit duration and scroll depth for a date range, with a comparison to the period before or the year before | Tiles |
| `breakdown` | Visitors by any one dimension: pages, sources, countries, devices, goals, UTM tags, and any dimension your app registers. Up to 50 rows. | A table |
| `trend` | One metric over time, by hour, day, week or month, plus the total for the whole range | A chart |
| `search_console` | Search Console queries with clicks and impressions, or one query's history | A table |
| `rankings` | Your tracked rank positions, best and change, AI overview citations, or one keyword's history | A table |
| `app_context` | The dashboard's own screens, what each is for, and where it lives, so a "how do I" question gets a link | Nothing |
| `prompt_evidence` | Works backwards from the visitors who converted in the range: how they first arrived, where they landed, the Google searches behind those pages, paid search terms, the pages they read before converting, and the pages AI assistants send people to. Also your tracked prompts, the ones you aren't mentioned in, and who gets cited instead. Only while AI visibility is on. | A table |
| `propose_prompts` | Nothing. It checks the model's suggested prompts and puts them on screen. Only while AI visibility is on. | A list of prompts, each with an Add button |

Every read:

- Follows the filters saved on the conversation, on the tools that can take them. See [Filters](#filters).
- Leaves crawlers out.
- Takes a named period ("last 30 days", "last month"), exact dates, or a number of days back. It defaults to the last 30 days.

`rankings` only reads checks already stored. It never runs a paid search. `search_console` can ask Google for the newest few days the nightly sync hasn't stored yet, the same way the dashboard's Google search card does.

### Filters

`traffic_summary`, `breakdown`, `trend` and `prompt_evidence` take the filters saved on the conversation. The saved filters always apply. The model can add a filter of its own on top of them, like country is Germany, and it can't take the saved ones off.

`search_console` and `rankings` can't be filtered by visitor, since their rows have no visitor attached. When the conversation has filters, their results say "Not filtered: Search Console rows have no visitor attached." or "Not filtered: rank checks have no visitor attached.", and the model is told to pass that on.

`app_context` and `propose_prompts` don't read data, so filters don't apply to them. The tracked prompts and AI visibility answers `prompt_evidence` hands back aren't filtered either, for the same reason as Search Console.

Every chart or table a tool draws lists the filters it used under its title, and its "Open on the dashboard" or "Open in Explore" link carries them.

### What it's told

Besides the tools, the model is told:

- Your site host from Settings, General, today's date and your time zone.
- To answer from the tools only, and say so when a tool comes back empty.
- To ask each tool for the dates the question means. It's handed "last week" worked out as last Monday to Sunday.
- To lead with the answer, keep it short, and skip the preamble.
- Four things it mustn't get wrong: visitors don't add up across days, Search Console position is an average and not a rank, a goal or property added today reads all your history, and crawlers are hidden by default.
- When asked from the panel, the screen it was asked from.

## Limits

| What | Limit |
|---|---|
| Question length | 2,000 characters. Anything past that is cut off without a warning. |
| Earlier messages sent with each question | The last 20, text only, skipping any question that's still pending or failed. Past tool results aren't sent, so a follow-up reads the data again. A reader that sent reasoning with an answer, like DeepSeek, gets that reasoning back with it. |
| Requests to the provider per answer | 8. Each tool round is one. |
| Output tokens per request | The provider's Output limit. See [Which settings win](#which-settings-win) for the defaults. |
| Waiting for the provider | 10 seconds to connect, then up to 180 seconds between pieces of the answer |
| Charts and tables per answer | 6, with up to 25 rows per table and 400 points per chart |
| Conversations shown per page on the Ask screen | 50, newest first, with a pager for the rest |

A question can cost up to 8 requests, each carrying the whole conversation so far and every tool result. The token count under each answer is the whole exchange, every request added up.

## Conversations are shared

Conversations belong to the dashboard, not to a person. Everybody who can open the dashboard sees every conversation. They're kept until somebody deletes them, with Delete on the conversation.

When the reader sends its reasoning along with an answer (DeepSeek does, every time), that reasoning is stored on the answer's row too, with the reader and endpoint that wrote it. It's never shown on screen. It's there so it can go back to the same reader with the next question, and it goes when the conversation does.

## What's sent to the provider

Every question sends the provider your key, the question, the conversation so far, the tool results the model asks for, and a short system prompt. Tool results can hold page paths, referrer URLs, UTM tags, cities, custom property values, Search Console queries, and your tracked keywords. No raw visits, no visitor tokens, nothing about who's asking. [Security and privacy](security-and-privacy.md#assistant) has the full list.

Earlier answers go with their stored reasoning when the same reader at the same endpoint wrote it. Switch readers, or point the same one somewhere else, and the old reasoning stays in your database.

Opening a provider's page on Settings, Assistant also sends its stored key to that provider's model list, at the endpoint saved with it. See [Model suggestions](#model-suggestions).

With OpenAI-compatible on its default endpoint, LM Studio on this machine, nothing leaves the machine. Change the endpoint and it goes wherever that points.

## When it doesn't answer

| What you see | Means |
|---|---|
| "The assistant is off. Turn it on under Settings, Features." | The assistant is switched off on Settings, Features |
| "Anthropic has no key set, so nothing can be asked." | No provider is marked "Use this one", or the one that is has no key stored |
| "Not installed yet" with two commands | The assistant's tables aren't in your database. Run the commands shown, then reload. |
| "No model is set for OpenAI-compatible." | Name the model on Settings, Assistant |
| "That answer did not come back. Ask the question again." | The provider refused or failed: a wrong key, a wrong model name, an unreachable endpoint, or a timeout. The real error is under Last error on Settings, Assistant, and in the log as `dashboard assistant failed: ...`. |
| Last error says "402 from the model: the account is out of credit, so top it up with the provider and ask again" | The account at the provider has run out of money. DeepSeek and OpenRouter both say so with a 402. It isn't retried, since asking again won't fix it until you add funds. |
| Last error says "the provider ran out of capacity partway through the answer" | DeepSeek stopped writing because its servers were short on capacity (`insufficient_system_resource`). Ask again. |
| Last error says "the provider stopped the answer partway through" | The provider cut the answer off (`aborted`). Ask again. |
| Last error mentions `reasoning_content` on DeepSeek | DeepSeek refused the empty reasoning sent for an earlier answer it didn't write, or for a tool round that came back with none. It shouldn't, going by other integrations' reports. If it does, start a new conversation. |
| Answers on DeepSeek or a hosted model stop partway with the length note | The Output limit is too low for the thinking plus the answer. Clear the box to use the default, or raise it. |
| "Reading the data" forever | Nothing works the `default` queue, or the worker died. It never times out. |
| The text only shows up at the end | Something between the browser and your app is buffering the stream. The dashboard sends `X-Accel-Buffering: no` for nginx. |
| An empty answer with a "Read ..." line | The model kept calling tools for all 8 requests and never wrote an answer. Ask again, more narrowly. |

Each answer somebody is watching arrive holds one web server thread for up to 2 minutes at a time. On a server with few threads, a few people waiting on answers at once can slow everything else down.

Related: [Configuration](configuration.md#settings-features), [Security and privacy](security-and-privacy.md#assistant), [Background jobs](background-jobs.md).
