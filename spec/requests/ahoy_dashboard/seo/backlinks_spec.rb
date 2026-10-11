require "rails_helper"
require "support/ahoy_dashboard/serp"

RSpec.describe "Dashboard backlinks", type: :request do
  let(:document) { Nokogiri::HTML5(response.body) }
  let(:today) { Date.current }

  before do
    sign_in create(:user, :admin)
    allow(AhoyDashboard::Backlinks).to receive(:enabled?).and_return(true)
  end

  def linker(domain, follow: true, lost_on: nil, first_seen_on: today - 400, provider: "dataforseo", links: 2)
    AhoyDashboard::BacklinkDomain.create!(domain: domain, authority: 30, links: links, follow: follow,
                                          first_seen_on: first_seen_on, last_seen_on: today,
                                          lost_on: lost_on, provider: provider)
  end

  def tile(label)
    node = document.css("[class*=tile]").find { |each| each.text.squish.start_with?(label) }
    node && node.text.squish.delete_prefix(label).strip.split(" ").first
  end

  def sync_button(label = "Sync now")
    document.css("button").find { |node| node.text.strip == label }
  end

  describe "with a real provider" do
    before do
      allow(AhoyDashboard::Backlinks).to receive(:provider).and_return(:dataforseo)
      dataforseo_configured!
    end

    it "counts every live site in the tiles, not only the ones listed" do
      45.times { |index| linker("site-#{index}.com", follow: index >= 12) }
      18.times { |index| linker("new-#{index}.com", first_seen_on: today - 1) }
      17.times { |index| linker("lost-#{index}.com", lost_on: today - 1) }
      AhoyDashboard::BacklinkSample.create!(on: today - 1, domains: 63, links: 126, provider: "dataforseo")

      get "/telemetry/seo/backlink"

      expect(tile("Referring domains")).to eq("63")
      expect(tile("Links")).to eq("126")
      expect(tile("New")).to eq("18")
      expect(tile("Lost")).to eq("17")
      expect(tile("Nofollow")).to eq("12")
      expect(tile("Followed")).to eq("81%")
      expect(response.body).to include("Highest authority first, top 40 of 63")
    end

    it "queues a sync" do
      expect { post "/telemetry/seo/backlink/syncs" }.to have_enqueued_job(AhoyDashboard::Backlinks::SyncJob)

      expect(flash[:notice]).to include("Pulling the backlink profile")
    end

    it "refuses to say a sync started when there is no host to look up" do
      allow(AhoyDashboard::Backlinks).to receive(:domain).and_return(nil)

      expect { post "/telemetry/seo/backlink/syncs" }.not_to have_enqueued_job(AhoyDashboard::Backlinks::SyncJob)

      expect(flash[:alert]).to include("so backlinks know which site to look up")
      expect(flash[:notice]).to be_nil
    end

    it "keeps Sync now disabled with the reason when there is no host" do
      allow(AhoyDashboard::Backlinks).to receive(:domain).and_return(nil)

      get "/telemetry/seo/backlink"

      expect(sync_button["disabled"]).not_to be_nil
      expect(document.at_css("##{sync_button['aria-describedby']}").text).to include("which site to look up")
    end

    it "refuses a sync without a login" do
      dataforseo_configured!(login: nil, password: nil)

      expect { post "/telemetry/seo/backlink/syncs" }.not_to have_enqueued_job(AhoyDashboard::Backlinks::SyncJob)

      get "/telemetry/seo/backlink"

      expect(sync_button["disabled"]).not_to be_nil
      expect(response.body).to include("DataForSEO has no credentials set.")
    end

    it "keeps the sample warning on sites synced from sample data" do
      linker("reddit.com", provider: "fake")

      get "/telemetry/seo/backlink"

      expect(response.body).to include("These are sample results.", "The next real sync replaces them.")
    end

    it "shows no sample warning on real data" do
      linker("a.com")

      get "/telemetry/seo/backlink"

      expect(response.body).not_to include("These are sample results.")
    end
  end

  describe "on the sample provider" do
    it "refuses Sync now instead of writing made up sites" do
      expect { post "/telemetry/seo/backlink/syncs" }.not_to have_enqueued_job(AhoyDashboard::Backlinks::SyncJob)

      expect(flash[:alert]).to eq("Backlinks would come from sample data. Choose a real search provider.")
    end

    it "keeps Sync now disabled and points at choosing a provider" do
      get "/telemetry/seo/backlink"

      expect(sync_button["disabled"]).not_to be_nil
      expect(response.body).to include("Choose a real search provider", "/telemetry/settings/serp_providers")
    end
  end
end
