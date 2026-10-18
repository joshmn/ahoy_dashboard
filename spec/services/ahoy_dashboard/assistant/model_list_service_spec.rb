require "rails_helper"

RSpec.describe AhoyDashboard::Assistant::ModelListService do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before { AhoyDashboard.config.cache_store = cache }

  after { AhoyDashboard.config.cache_store = nil }

  def ids(name)
    described_class.call(name: name).map(&:id)
  end

  def listing(data, **extra)
    { status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate({ data: data }.merge(extra)) }
  end

  def provider(name, key: "sk-test", **attributes)
    create(:dash_assistant_provider, name: name, credentials: (key ? { api_key: key } : {}), **attributes)
  end

  describe "with no key stored" do
    it "offers the built in list without asking anybody" do
      expect(ids("anthropic")).to eq(AhoyDashboard::Assistant.reader_for("anthropic").models)
      expect(ids("openai")).to eq(AhoyDashboard::Assistant.reader_for("openai").models)
      expect(ids("deepseek")).to eq(%w[deepseek-flash deepseek-v4-pro])
      expect(WebMock).not_to have_requested(:any, /.*/)
    end
  end

  describe "Anthropic" do
    let(:url) { "https://api.anthropic.com/v1/models" }

    it "pages through with after_id, keeps the active models, and sends the key only as x-api-key" do
      provider("anthropic", key: "sk-ant")
      stub_request(:get, url).with(query: { "limit" => "1000" }).to_return(listing(
        [ { id: "claude-opus-5", display_name: "Claude Opus 5", lifecycle: "active", type: "model" },
          { id: "claude-3-opus-20240229", display_name: "Claude Opus 3", lifecycle: "retired", type: "model" } ],
        has_more: true, first_id: "claude-opus-5", last_id: "claude-3-opus-20240229"
      ))
      stub_request(:get, url).with(query: { "limit" => "1000", "after_id" => "claude-3-opus-20240229" }).to_return(listing(
        [ { id: "claude-sonnet-4-5", display_name: "Claude Sonnet 4.5", lifecycle: "deprecated", type: "model" },
          { id: "claude-haiku-4-5", display_name: "Claude Haiku 4.5", type: "model" } ],
        has_more: false, first_id: "claude-sonnet-4-5", last_id: "claude-haiku-4-5"
      ))

      options = described_class.call(name: "anthropic")

      expect(options.map(&:id)).to eq(%w[claude-opus-5 claude-haiku-4-5])
      expect(options.map(&:label)).to eq([ "Claude Opus 5", "Claude Haiku 4.5" ])
      expect(WebMock).to have_requested(:get, /api\.anthropic\.com/)
        .with(headers: { "x-api-key" => "sk-ant", "anthropic-version" => "2023-06-01" }).twice
      expect(WebMock).not_to have_requested(:get, /api\.anthropic\.com/).with(headers: { "Authorization" => /./ })
    end

    it "stops paging when a page says there is more but names no cursor" do
      provider("anthropic")
      stub_request(:get, url).with(query: hash_including({})).to_return(listing([ { id: "claude-opus-5" } ], has_more: true, last_id: nil))

      expect(ids("anthropic")).to eq([ "claude-opus-5" ])
      expect(WebMock).to have_requested(:get, /api\.anthropic\.com/).once
    end
  end

  describe "OpenAI" do
    let(:url) { "https://api.openai.com/v1/models" }

    it "keeps the chat models, newest first, and sends the key as a bearer token" do
      provider("openai", key: "sk-oai")
      models = %w[gpt-4.1 text-embedding-3-small tts-1 whisper-1 gpt-4o-transcribe dall-e-3 gpt-image-1
                  omni-moderation-latest gpt-4o-realtime-preview gpt-4o-audio-preview gpt-4o-search-preview
                  computer-use-preview davinci-002 sora-2 gpt-6-sol]
      data = models.each_with_index.map { |id, index| { id: id, object: "model", created: 1_700_000_000 + index, owned_by: "openai" } }
      stub_request(:get, url).to_return(listing(data))

      expect(ids("openai")).to eq(%w[gpt-6-sol gpt-4.1])
      expect(WebMock).to have_requested(:get, url).with(headers: { "Authorization" => "Bearer sk-oai" }).once
    end
  end

  describe "DeepSeek" do
    it "lists what the account can use, with the names it gives them" do
      provider("deepseek", key: "sk-deep")
      stub_request(:get, "https://api.deepseek.com/models").to_return(listing(
        [ { id: "deepseek-flash", object: "model", owned_by: "deepseek", name: "DeepSeek-V4.1-Flash" },
          { id: "deepseek-v4-pro", object: "model", owned_by: "deepseek", name: "DeepSeek-V4-Pro" } ],
        object: "list"
      ))

      options = described_class.call(name: "deepseek")

      expect(options.map(&:id)).to eq(%w[deepseek-flash deepseek-v4-pro])
      expect(options.map(&:label)).to eq(%w[DeepSeek-V4.1-Flash DeepSeek-V4-Pro])
      expect(WebMock).to have_requested(:get, "https://api.deepseek.com/models")
        .with(headers: { "Authorization" => "Bearer sk-deep" }).once
    end
  end

  describe "an OpenAI-compatible server" do
    it "asks a local server with no key and sends no Authorization header" do
      provider("compatible", key: nil, model: "qwen")
      stub_request(:get, "http://localhost:1234/v1/models").to_return(listing(
        [ { id: "qwen2.5-7b-instruct", object: "model" }, { id: "text-embedding-nomic-embed-text-v1.5", object: "model" },
          { id: "nomic-embed-text", object: "model" } ]
      ))

      expect(ids("compatible")).to eq([ "qwen2.5-7b-instruct" ])
      expect(WebMock).not_to have_requested(:get, "http://localhost:1234/v1/models").with(headers: { "Authorization" => /./ })
    end

    it "asks the endpoint saved on the row, with its key" do
      provider("compatible", key: "sk-or", api_base: "https://openrouter.ai/api/v1/")
      stub_request(:get, "https://openrouter.ai/api/v1/models").to_return(listing([ { id: "some/model", name: "Some: Model" } ]))

      expect(ids("compatible")).to eq([ "some/model" ])
      expect(WebMock).to have_requested(:get, "https://openrouter.ai/api/v1/models").with(headers: { "Authorization" => "Bearer sk-or" })
    end

    it "finds the row an install saved under lmstudio" do
      create(:dash_assistant_provider, name: "lmstudio", model: "qwen", api_base: "http://127.0.0.1:1234/v1")
      stub_request(:get, "http://127.0.0.1:1234/v1/models").to_return(listing([ { id: "qwen" } ]))

      expect(ids("lmstudio")).to eq([ "qwen" ])
      expect(ids("compatible")).to eq([ "qwen" ])
    end
  end

  describe "where the key goes" do
    it "sends a key only to the endpoint it was saved with" do
      provider("openai", key: "sk-oai", api_base: "https://proxy.example.com/v1")
      stub_request(:get, "https://proxy.example.com/v1/models").to_return(listing([ { id: "gpt-4.1" } ]))

      expect(ids("openai")).to eq([ "gpt-4.1" ])
      expect(WebMock).to have_requested(:get, "https://proxy.example.com/v1/models").with(headers: { "Authorization" => "Bearer sk-oai" })
      expect(WebMock).not_to have_requested(:any, /api\.openai\.com/)
    end

    it "does not follow a redirect to another host, and falls back to the built in list" do
      provider("deepseek", key: "sk-deep")
      stub_request(:get, "https://api.deepseek.com/models")
        .to_return(status: 302, headers: { "Location" => "https://collector.example.net/models" })

      expect(ids("deepseek")).to eq(%w[deepseek-flash deepseek-v4-pro])
      expect(WebMock).not_to have_requested(:any, /collector\.example\.net/)
    end
  end

  describe "caching" do
    let(:url) { "https://api.deepseek.com/models" }

    it "keeps a list for a short while rather than asking on every page load" do
      provider("deepseek")
      stub_request(:get, url).to_return(listing([ { id: "deepseek-flash" } ]))

      2.times { ids("deepseek") }

      expect(WebMock).to have_requested(:get, url).once
    end

    it "asks again once the list has expired" do
      provider("deepseek")
      stub_request(:get, url).to_return(listing([ { id: "deepseek-flash" } ]))

      ids("deepseek")
      travel(described_class::TTL + 1.second) { ids("deepseek") }

      expect(WebMock).to have_requested(:get, url).twice
    end

    it "keeps a list apart per key and per endpoint" do
      row = provider("deepseek", key: "sk-one")
      stub_request(:get, url).to_return(listing([ { id: "deepseek-flash" } ]))
      stub_request(:get, "https://proxy.example.com/models").to_return(listing([ { id: "deepseek-v4-pro" } ]))

      expect(ids("deepseek")).to eq([ "deepseek-flash" ])
      row.update!(credentials: { api_key: "sk-two" })
      expect(ids("deepseek")).to eq([ "deepseek-flash" ])
      row.update!(api_base: "https://proxy.example.com")
      expect(ids("deepseek")).to eq([ "deepseek-v4-pro" ])

      expect(WebMock).to have_requested(:get, url).twice
      expect(WebMock).to have_requested(:get, url).with(headers: { "Authorization" => "Bearer sk-one" }).once
      expect(WebMock).to have_requested(:get, url).with(headers: { "Authorization" => "Bearer sk-two" }).once
    end

    it "keeps no key in the cache key" do
      provider("deepseek", key: "sk-secret-value")
      stub_request(:get, url).to_return(listing([ { id: "deepseek-flash" } ]))
      written = []
      allow(cache).to receive(:write).and_wrap_original do |original, key, *rest, **options|
        written << key
        original.call(key, *rest, **options)
      end

      ids("deepseek")

      expect(written.size).to eq(1)
      expect(written.first).not_to include("sk-secret-value")
    end

    it "never keeps a failure, so the next load asks again" do
      provider("deepseek")
      stub_request(:get, url).to_return({ status: 500, body: "{}" }, listing([ { id: "deepseek-v4-pro" } ]))

      expect(ids("deepseek")).to eq(%w[deepseek-flash deepseek-v4-pro])
      expect(ids("deepseek")).to eq([ "deepseek-v4-pro" ])
      expect(WebMock).to have_requested(:get, url).twice
    end

    it "never keeps an empty list" do
      provider("deepseek")
      stub_request(:get, url).to_return(listing([]), listing([ { id: "deepseek-flash" } ]))

      expect(ids("deepseek")).to eq(%w[deepseek-flash deepseek-v4-pro])
      expect(ids("deepseek")).to eq([ "deepseek-flash" ])
    end
  end

  describe "failures" do
    it "falls back to the built in list when the server cannot be reached" do
      provider("deepseek")
      stub_request(:get, "https://api.deepseek.com/models").to_timeout

      expect(ids("deepseek")).to eq(%w[deepseek-flash deepseek-v4-pro])
    end

    it "falls back when the reply is not a model list" do
      provider("deepseek")
      stub_request(:get, "https://api.deepseek.com/models").to_return(status: 200, body: "<html>not here</html>")

      expect(ids("deepseek")).to eq(%w[deepseek-flash deepseek-v4-pro])
    end

    it "falls back on a refused key" do
      provider("openai")
      stub_request(:get, "https://api.openai.com/v1/models").to_return(status: 401, body: JSON.generate(error: { message: "bad key" }))

      expect(ids("openai")).to eq(AhoyDashboard::Assistant.reader_for("openai").models)
    end

    it "asks nothing when the saved endpoint is not a web address" do
      provider("compatible", key: nil, model: "qwen", api_base: "localhost:1234")

      expect(ids("compatible")).to eq([])
      expect(WebMock).not_to have_requested(:any, /.*/)
    end
  end
end
