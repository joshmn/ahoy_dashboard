require "rails_helper"

RSpec.describe AhoyDashboard::Serp do
  describe ".adapter_class" do
    it "resolves a registered adapter" do
      expect(described_class.adapter_class(:fake)).to eq(AhoyDashboard::Serp::Adapters::FakeAdapter)
      expect(described_class.adapter_class("serpapi")).to eq(AhoyDashboard::Serp::Adapters::SerpApiAdapter)
    end

    it "names itself the way the registry names it, both directions" do
      described_class::ADAPTERS.each_key do |key|
        expect(described_class.adapter_class(key).adapter_name.to_sym).to eq(key)
      end
    end

    it "refuses a name nobody registered" do
      expect { described_class.adapter_class(:google) }
        .to raise_error(AhoyDashboard::Serp::Error, /no serp adapter called :google/)
    end
  end

  it "builds the adapter for the active provider row" do
    create(:dash_serp_provider, :serpapi, :active)

    expect(described_class.adapter).to be_a(AhoyDashboard::Serp::Adapters::SerpApiAdapter)
  end

  it "defaults to the fake adapter, so nothing spends money by accident" do
    expect(described_class.provider).to eq(:fake)
    expect(described_class.adapter).to be_a(AhoyDashboard::Serp::Adapters::FakeAdapter)
  end

  describe ".credential" do
    it "reads one vendor's key off its stored row" do
      create(:dash_serp_provider, :serpapi, :active)

      expect(described_class.credential(:serpapi, :api_key)).to eq("stored-key")
    end

    it "reads a stored row that is not the active one, for keyword research and backlinks" do
      create(:dash_serp_provider, :active)
      create(:dash_serp_provider, name: "dataforseo", credentials: { login: "me@example.com", password: "hunter2" })

      expect(described_class.credential(:dataforseo, :password)).to eq("hunter2")
      expect(described_class).to be_configured(:dataforseo)
    end

    it "answers nil for a vendor with nothing stored" do
      expect(described_class.credential(:serpapi, :api_key)).to be_nil
    end

    it "never reads a key out of the environment" do
      stub_const("ENV", ENV.to_h.merge("SERPAPI_KEY" => "from-env", "SERPAPI_API_KEY" => "from-env"))

      expect(described_class.credential(:serpapi, :api_key)).to be_nil
      expect(described_class).not_to be_configured(:serpapi)
    end
  end

  describe ".ready?" do
    it "needs the switch as well as the credentials" do
      serp_settings(enabled: false) do
        expect(described_class.configured?).to be(true)
        expect(described_class).not_to be_ready
      end
    end

    it "is ready when both are true" do
      serp_settings(enabled: true) { expect(described_class).to be_ready }
    end
  end

  it "normalises its own domain out of the configured host" do
    allow(Rails.application.config.x).to receive(:main_host).and_return("www.Example.com:5000")

    expect(described_class.own_domain).to eq("example.com")
  end
end
