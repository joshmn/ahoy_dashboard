require "rails_helper"

RSpec.describe AhoyDashboard::Serp::BoughtData do
  {
    AhoyDashboard::Keywords => {
      disabled: "Keyword research is off. Turn it on under Settings, Features.",
      unsupported: "Your search provider has no keyword data."
    },
    AhoyDashboard::Backlinks => {
      disabled: "Backlinks are off. Turn them on under Settings, Features.",
      unsupported: "Your search provider has no backlink data.",
      no_host: "Set your site's host under Settings, General so backlinks know which site to look up.",
      sample: "Backlinks would come from sample data. Choose a real search provider."
    }
  }.each do |feature, messages|
    describe feature.name do
      before { allow(feature).to receive_messages(installed?: true, provider: :dataforseo) }

      it "keeps its own wording for each refusal" do
        messages.each { |key, text| expect(feature.refusal_message(key)).to eq(text) }
        expect(feature.refusal_message(:unconfigured)).to eq("DataForSEO has no credentials set.")
        expect(feature.refusal_message(:capped)).to eq("The monthly ceiling is spent, so nothing was sent.")
      end

      it "says whether the provider sells it without building an adapter" do
        allow(AhoyDashboard::Serp).to receive(:adapter).and_call_original

        expect(feature).to be_sells
        expect(AhoyDashboard::Serp).not_to have_received(:adapter)
      end

      it "costs what the provider charges for it" do
        expect(feature.cost_units).to eq(2)
      end

      it "treats an adapter nobody registered as not sold and not configured, with room to spare" do
        allow(feature).to receive(:provider).and_return(:gone)

        expect(feature).not_to be_sells
        expect(feature).not_to be_configured
        expect(feature).to be_room
      end
    end
  end

  it "counts the sample provider as sample data" do
    allow(AhoyDashboard::Backlinks).to receive(:provider).and_return(:fake)

    expect(AhoyDashboard::Backlinks).to be_sample
    expect(AhoyDashboard::Serp.sample?("fake")).to be(true)
    expect(AhoyDashboard::Serp.sample?(:serpapi)).to be(false)
  end
end
