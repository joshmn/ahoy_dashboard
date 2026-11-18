require "rails_helper"

RSpec.describe AhoyDashboard::Assistant do
  it "is off in test, and says why" do
    expect(described_class).not_to be_available
    expect(described_class.unavailable_reason).to include("switched off")
  end

  it "refuses to build a chat while it is off rather than half configuring one" do
    expect { described_class.chat }.to raise_error(described_class::NotConfiguredError)
  end

  it "carries every tool it registered" do
    expect(described_class.tool_classes).to all(be < AhoyDashboard::LLM::Tool)
    expect(described_class.tool_classes.size).to eq(described_class::TOOLS.size)
    expect(described_class.tools).to all(be_a(AhoyDashboard::LLM::Tool))
  end

  it "names its tools for the model without the namespace the gem would build" do
    expect(described_class.tools.map(&:name)).to include("trend", "traffic_summary")
  end

  it "reads a stored tool call back as something a person can read" do
    expect(described_class.tool_label("trend")).to eq("the trend over time")
    expect(described_class.tool_label("dash--assistant--tools--trend")).to eq("the trend over time")
    expect(described_class.tool_label("SomethingElse")).to eq("something else")
  end

  it "gives each reader its own provider" do
    expect(described_class.context.provider).to eq(:anthropic)
    expect(described_class.context.chat(model: "claude-sonnet-4-6")).to be_a(AhoyDashboard::LLM::Anthropic::Chat)

    create(:dash_assistant_provider, :active, name: "openai", model: "gpt-5-mini")

    expect(described_class.context.provider).to eq(:openai)
    expect(described_class.context.chat(model: "gpt-5-mini")).to be_a(AhoyDashboard::LLM::OpenAI::Chat)

    AhoyDashboard::AssistantProvider.update_all(name: "compatible")

    expect(described_class.context.provider).to eq(:compatible)
    expect(described_class.context.chat(model: "qwen")).to be_a(AhoyDashboard::LLM::Compatible::Chat)

    AhoyDashboard::AssistantProvider.update_all(name: "deepseek")

    expect(described_class.context.provider).to eq(:compatible)
    expect(described_class.context.chat(model: "deepseek-flash")).to be_a(AhoyDashboard::LLM::Compatible::Chat)
  end

  it "sends the output limit saved on the screen over the reader's own" do
    create(:dash_assistant_provider, :active, name: "deepseek", max_tokens: 8_000, credentials: { api_key: "sk" })
    stub_request(:post, "https://api.deepseek.com/chat/completions").to_return(
      status: 200, body: "data: #{JSON.generate(choices: [ { delta: { content: "ok" }, finish_reason: "stop" } ])}\n\n"
    )

    described_class.context.chat(model: "deepseek-flash").ask("q")

    expect(WebMock).to have_requested(:post, "https://api.deepseek.com/chat/completions")
      .with { |request| JSON.parse(request.body)["max_tokens"] == 8_000 }
  end

  it "knows a loopback endpoint from one somewhere else" do
    expect(described_class.on_this_machine?("http://localhost:1234/v1")).to be(true)
    expect(described_class.on_this_machine?("http://127.0.0.1:1234/v1")).to be(true)
    expect(described_class.on_this_machine?("http://[::1]:1234/v1")).to be(true)
    expect(described_class.on_this_machine?("https://gpu.example.net/v1")).to be(false)
    expect(described_class.on_this_machine?("not a url")).to be(false)
  end

  it "answers with Anthropic and its default model until a reader is chosen on the screen" do
    expect(described_class.reader).to eq("anthropic")
    expect(described_class.model_name).to eq("claude-sonnet-4-6")
    expect(described_class.api_base).to eq("https://api.anthropic.com/v1")
  end

  it "sends no temperature and the reader's own output limit until the screen sets them" do
    expect(described_class.temperature).to be_nil
    expect(described_class.max_tokens).to be_nil
  end

  it "reads the temperature and output limit off the reader in use" do
    create(:dash_assistant_provider, :active, name: "openai", model: "gpt-4.1", temperature: 0.3, max_tokens: 2_000)

    expect(described_class.temperature).to eq(0.3)
    expect(described_class.max_tokens).to eq(2_000)
  end

  describe "where the key and the model come from" do
    it "has no key when nothing is set up on the screen, whatever the environment holds" do
      stub_const("ENV", ENV.to_h.merge("ANTHROPIC_API_KEY" => "from-env"))

      expect(described_class.api_key).to be_nil
      expect(described_class.key_source).to eq(:missing)
      expect(described_class).not_to respond_to(:fallback_key)
    end

    it "uses the key typed on the screen" do
      create(:dash_assistant_provider, :active, credentials: { api_key: "typed-in" })

      expect(described_class.api_key).to eq("typed-in")
      expect(described_class.record.api_key).not_to eq(described_class.record.read_attribute(:credentials))
    end

    it "takes the reader and the model off the active row" do
      create(:dash_assistant_provider, :active, name: "openai", model: "gpt-5-mini")

      expect(described_class.reader).to eq("openai")
      expect(described_class.api_base).to eq("https://api.openai.com/v1")
      expect(described_class.model_name).to eq("gpt-5-mini")
    end

    it "falls back to the reader's own default model" do
      create(:dash_assistant_provider, :active, model: nil)

      expect(described_class.model_name).to eq("claude-sonnet-4-6")
    end

    it "points an OpenAI-compatible reader at its own endpoint and needs no key" do
      create(:dash_assistant_provider, :active, name: "compatible", model: "qwen")

      expect(described_class.api_base).to eq("http://localhost:1234/v1")
      expect(described_class).to be_key_optional
      expect(described_class.key_source).to eq(:not_needed)
      expect(described_class).to be_provider_ready
    end

    it "says a key is stored for an OpenAI-compatible reader once one is" do
      create(:dash_assistant_provider, :active, name: "compatible", model: "some/model",
                                                 api_base: "https://openrouter.ai/api/v1", credentials: { api_key: "sk-or" })

      expect(described_class.key_source).to eq(:stored)
      expect(described_class.context.api_key).to eq("sk-or")
    end

    it "keeps an install whose stored reader is lmstudio on the OpenAI-compatible reader at LM Studio's address" do
      create(:dash_assistant_provider, :active, name: "lmstudio", model: "qwen")

      expect(described_class.reader).to eq("compatible")
      expect(described_class.reader_name).to eq("compatible")
      expect(described_class.settings.label).to eq("OpenAI-compatible")
      expect(described_class.api_base).to eq("http://localhost:1234/v1")
      expect(described_class.model_name).to eq("qwen")
      expect(described_class.key_source).to eq(:not_needed)
      expect(described_class).to be_provider_ready
      expect(described_class.context.chat(model: "qwen")).to be_a(AhoyDashboard::LLM::Compatible::Chat)
      expect(AhoyDashboard::AssistantProvider.for("compatible").name).to eq("lmstudio")
    end

    it "needs a DeepSeek key, thinks, and runs to the longer output limit thinking needs" do
      switch_on_ahoy_dashboard(:assistant)
      create(:dash_assistant_provider, :active, name: "deepseek")

      expect(described_class.api_base).to eq("https://api.deepseek.com")
      expect(described_class.model_name).to eq("deepseek-flash")
      expect(described_class.key_source).to eq(:missing)
      expect(described_class).not_to be_provider_ready
      expect(described_class.unavailable_reason).to eq("DeepSeek has no key set, so nothing can be asked.")
      expect(described_class.settings).to be_thinking
      expect(described_class.settings).to be_replays_reasoning
      expect(described_class.settings.max_tokens).to eq(65_536)
      expect(described_class.reader_for("compatible")).not_to be_replays_reasoning
      expect(described_class.reader_for("compatible")).not_to be_thinking
    end

    it "carries the key into the chat's own config rather than the global one" do
      create(:dash_assistant_provider, :active, credentials: { api_key: "typed-in" })

      expect(described_class.context.api_key).to eq("typed-in")
    end
  end

  describe "the tools offered to the model" do
    def offered
      described_class.tools.map(&:name)
    end

    it "offers search console and rankings when both are installed" do
      expect(offered).to include("search_console", "rankings")
      expect(offered).not_to include("prompt_evidence", "propose_prompts")
      expect(offered.size).to eq(described_class::TOOLS.size - 2)
    end

    it "offers the prompt tools only while AI visibility is on" do
      ai_visibility_settings(enabled: true) do
        expect(offered).to include("prompt_evidence", "propose_prompts")
        expect(offered.size).to eq(described_class::TOOLS.size)
      end
    end

    it "leaves out search console when its tables are not installed" do
      uninstall_ahoy_dashboard(:search_console)

      expect(offered).not_to include("search_console")
      expect(offered).to include("rankings", "traffic_summary", "breakdown", "trend", "app_context")
    end

    it "leaves out rankings when rank tracking is not installed" do
      uninstall_ahoy_dashboard(:serp)

      expect(offered).not_to include("rankings")
      expect(offered).to include("search_console")
    end

    it "keeps every tool's label for turns written while it was offered" do
      uninstall_ahoy_dashboard(:serp, :search_console)

      expect(described_class.tool_label("rankings")).to eq("the rank tracking")
      expect(described_class.tool_label("search_console")).to eq("Search Console")
    end
  end

  it "says the tables are missing when it is switched on without them" do
    switch_on_ahoy_dashboard(:assistant)
    uninstall_ahoy_dashboard(:assistant)

    expect(described_class.record).to be_nil
    expect(described_class.unavailable_reason).to include("--only assistant")
  end
end
