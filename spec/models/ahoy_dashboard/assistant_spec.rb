require "rails_helper"
require "support/ahoy_dashboard/assistant"
require "support/ahoy_dashboard/installation"
require "support/ahoy_dashboard/switches"

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

    AhoyDashboard::AssistantProvider.update_all(name: "lmstudio")

    expect(described_class.context.provider).to eq(:compatible)
    expect(described_class.context.chat(model: "qwen")).to be_a(AhoyDashboard::LLM::Compatible::Chat)
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

    it "points a local reader at its own endpoint and needs no key" do
      create(:dash_assistant_provider, :active, name: "lmstudio", model: "qwen")

      expect(described_class.api_base).to eq("http://localhost:1234/v1")
      expect(described_class).to be_local
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
      expect(offered.size).to eq(described_class::TOOLS.size)
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

    it "answers with an error rather than reading a missing table if one is called anyway" do
      uninstall_ahoy_dashboard(:serp, :search_console)

      expect(AhoyDashboard::Assistant::Tools::Rankings.new.execute).to include(error: a_string_including("not installed"))
      expect(AhoyDashboard::Assistant::Tools::SearchConsole.new.execute).to include(error: a_string_including("not installed"))
    end
  end

  it "says the tables are missing when it is switched on without them" do
    switch_on_ahoy_dashboard(:assistant)
    uninstall_ahoy_dashboard(:assistant)

    expect(described_class.record).to be_nil
    expect(described_class.unavailable_reason).to include("--only assistant")
  end
end
