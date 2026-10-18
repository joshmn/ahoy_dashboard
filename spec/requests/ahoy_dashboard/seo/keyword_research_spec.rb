require "rails_helper"

RSpec.describe "Dashboard keyword research", type: :request do
  before do
    sign_in create(:user, :admin)
    allow(AhoyDashboard::Keywords).to receive(:enabled?).and_return(true)
  end

  def saved_idea(query, provider: "fake", seed: "visiting", location: "us", language: "en")
    create(:dash_keyword_idea, seed: seed, query: query, location: location, language: language, volume: 100,
           provider: provider, fetched_at: 1.day.ago)
  end

  def research_path(**params)
    "/telemetry/seo/keyword_research?#{params.to_query}"
  end

  def idea_queries
    document.css("[aria-label='Keyword ideas'] tbody tr td:first-child").map { |cell| cell.text.squish }
  end

  describe "looking a phrase up" do
    it "fetches a phrase nobody has looked up yet" do
      expect {
        post "/telemetry/seo/keyword_research/lookups", params: { seed: "visiting" }
      }.to have_enqueued_job(AhoyDashboard::Keywords::FetchJob).with("visiting", location: "us", language: "en")

      expect(response).to redirect_to(research_path(language: "en", location: "us", seed: "visiting"))
    end

    it "opens a saved phrase without buying it again" do
      saved_idea("visiting hours")

      expect {
        post "/telemetry/seo/keyword_research/lookups", params: { seed: "Visiting" }
      }.not_to have_enqueued_job(AhoyDashboard::Keywords::FetchJob)

      expect(flash[:notice]).to include("already saved, so nothing was bought")
    end

    it "buys a saved phrase again from Look up again" do
      saved_idea("visiting hours")

      expect {
        post "/telemetry/seo/keyword_research/refreshes", params: { seed: "visiting" }
      }.to have_enqueued_job(AhoyDashboard::Keywords::FetchJob).with("visiting", true, location: "us", language: "en")

      expect(response).to redirect_to(research_path(language: "en", location: "us", seed: "visiting"))
    end

    it "refuses Look up again without a phrase" do
      expect {
        post "/telemetry/seo/keyword_research/refreshes", params: { seed: " " }
      }.not_to have_enqueued_job(AhoyDashboard::Keywords::FetchJob)

      expect(flash[:alert]).to eq("Give it a phrase to start from.")
    end

    it "offers Look up again on a saved phrase and says what the hint promises" do
      saved_idea("visiting hours")

      get "/telemetry/seo/keyword_research", params: { seed: "visiting" }
      form = document.css("form").find { |node| node["action"] == "/telemetry/seo/keyword_research/refreshes" }

      expect(form).to be_present
      expect(form.at_css("input[name=seed]")["value"]).to eq("visiting")
      expect(form.at_css("input[name=location]")["value"]).to eq("us")
      expect(form.at_css("input[name=language]")["value"]).to eq("en")
      expect(document.at_css("#seed-hint").text).to include("Saved phrases open without paying again")
      expect(response.body).not_to include("only paid for once")
    end
  end

  describe "place and language" do
    it "starts the form from the initializer's place and language" do
      allow(AhoyDashboard::Keywords).to receive_messages(location: "city:gb:London,England,United Kingdom", language: "fr")

      get "/telemetry/seo/keyword_research"
      form = document.css("form").find { |node| node["action"] == "/telemetry/seo/keyword_research/lookups" }

      expect(form.at_css("select[name=country] option[selected]")["value"]).to eq("gb")
      expect(form.at_css("input[name=city]")["value"]).to eq("London,England,United Kingdom")
      expect(form.at_css("input[name=language]")["value"]).to eq("fr")
      expect(document.at_css("label[for=country]").text).to eq("Place")
      expect(document.at_css("label[for=city]")).to be_present
      expect(document.at_css("label[for=language]").text).to eq("Language")
    end

    it "shows the place and language a saved set was bought under" do
      saved_idea("visiting hours uk", location: "gb")

      get "/telemetry/seo/keyword_research", params: { seed: "visiting", location: "gb", language: "en" }

      expect(document.at_css("select[name=country] option[selected]")["value"]).to eq("gb")
      expect(document.at_css("input[name=city]")["value"]).to eq("")
    end

    it "looks a phrase up under the place and language picked" do
      expect {
        post "/telemetry/seo/keyword_research/lookups",
             params: { seed: "visiting", country: "gb", city: "", language: "EN" }
      }.to have_enqueued_job(AhoyDashboard::Keywords::FetchJob).with("visiting", location: "gb", language: "en")

      expect(response).to redirect_to(research_path(language: "en", location: "gb", seed: "visiting"))
    end

    it "looks a phrase up from a city" do
      expect {
        post "/telemetry/seo/keyword_research/lookups",
             params: { seed: "visiting", country: "us", city: "Chicago,Illinois,United States", language: "en" }
      }.to have_enqueued_job(AhoyDashboard::Keywords::FetchJob)
        .with("visiting", location: "city:us:Chicago,Illinois,United States", language: "en")
    end

    it "buys a phrase saved under one place again under another" do
      saved_idea("visiting hours")

      expect {
        post "/telemetry/seo/keyword_research/lookups", params: { seed: "visiting", country: "gb", language: "en" }
      }.to have_enqueued_job(AhoyDashboard::Keywords::FetchJob).with("visiting", location: "gb", language: "en")
    end

    it "does not buy a phrase again under the place it is already saved for" do
      saved_idea("visiting hours", location: "gb")

      expect {
        post "/telemetry/seo/keyword_research/lookups", params: { seed: "visiting", country: "gb", language: "en" }
      }.not_to have_enqueued_job(AhoyDashboard::Keywords::FetchJob)

      expect(flash[:notice]).to start_with("visiting, United Kingdom, en is already saved, so nothing was bought.")
    end

    it "sends Look up again under the place and language on screen" do
      saved_idea("visiting hours", location: "gb", language: "de")

      expect {
        post "/telemetry/seo/keyword_research/refreshes", params: { seed: "visiting", location: "gb", language: "de" }
      }.to have_enqueued_job(AhoyDashboard::Keywords::FetchJob).with("visiting", true, location: "gb", language: "de")
    end

    it "refuses a language that is not a code" do
      expect {
        post "/telemetry/seo/keyword_research/lookups", params: { seed: "visiting", country: "us", language: "english" }
      }.not_to have_enqueued_job(AhoyDashboard::Keywords::FetchJob)

      expect(flash[:alert]).to eq("\"english\" is not a language code. Use one like en or es.")
    end

    it "refuses a country the provider cannot look up" do
      allow(AhoyDashboard::Keywords).to receive(:provider).and_return(:dataforseo)
      dataforseo_configured!

      expect {
        post "/telemetry/seo/keyword_research/lookups", params: { seed: "visiting", country: "cn", language: "zh" }
      }.not_to have_enqueued_job(AhoyDashboard::Keywords::FetchJob)

      expect(flash[:alert]).to eq("DataForSEO cannot look up searches from China. Pick another country.")
    end

    it "only shows the ideas for the phrase, place and language picked" do
      saved_idea("visiting hours us")
      saved_idea("visiting hours uk", location: "gb")
      saved_idea("visiting hours es", language: "es")

      get "/telemetry/seo/keyword_research", params: { seed: "visiting", location: "gb", language: "en" }

      expect(idea_queries).to eq([ "visiting hours uk" ])
    end

    it "lists the same phrase under each place separately in Saved phrases" do
      saved_idea("visiting hours us")
      saved_idea("visiting hours uk", location: "gb")
      saved_idea("visiting hours chicago", location: "city:us:Chicago,Illinois,United States")

      get "/telemetry/seo/keyword_research", params: { seed: "visiting", location: "gb", language: "en" }
      items = document.css("#tm-seo-seed a, [id^='tm-seo-seed'] a").map { |node| [ node.text.squish, node["href"] ] }.uniq

      expect(items.map(&:first)).to contain_exactly(
        a_string_including("visiting, Chicago, Illinois, United States, en"),
        a_string_including("visiting, United Kingdom, en"),
        a_string_including("visiting, United States, en")
      )
      expect(items.map(&:last)).to include(research_path(language: "en", location: "gb", seed: "visiting"))
    end

    it "opens the saved set under the initializer's place for a bare phrase link" do
      saved_idea("visiting hours uk", location: "gb")
      saved_idea("visiting hours us")

      get "/telemetry/seo/keyword_research", params: { seed: "visiting" }

      expect(idea_queries).to eq([ "visiting hours us" ])
    end

    it "opens whichever place a phrase is saved under when the initializer's has none" do
      saved_idea("visiting hours uk", location: "gb")

      get "/telemetry/seo/keyword_research", params: { seed: "visiting" }

      expect(idea_queries).to eq([ "visiting hours uk" ])
    end

    it "keeps the place and language on the easy wins filter" do
      create(:dash_keyword_idea, seed: "visiting", query: "visiting hours uk", location: "gb", language: "en",
             volume: 500, difficulty: 10, provider: "fake", fetched_at: 1.day.ago)

      get "/telemetry/seo/keyword_research", params: { seed: "visiting", location: "gb", language: "en" }

      expect(document.css("a").map { |node| node["href"] })
        .to include(research_path(language: "en", location: "gb", only: "easy", seed: "visiting"))
    end
  end

  describe "a provider with no login" do
    before do
      allow(AhoyDashboard::Keywords).to receive(:provider).and_return(:dataforseo)
      dataforseo_configured!(login: nil, password: nil)
    end

    it "keeps Look up disabled with the reason beside it" do
      get "/telemetry/seo/keyword_research"
      expect(disabled_button_reason("Look up")).to include("DataForSEO has no credentials set.")
    end

    it "refuses the lookup instead of queueing a job that fails" do
      expect {
        post "/telemetry/seo/keyword_research/lookups", params: { seed: "visiting" }
      }.not_to have_enqueued_job(AhoyDashboard::Keywords::FetchJob)

      expect(flash[:alert]).to eq("DataForSEO has no credentials set.")
    end
  end

  describe "the sample data warning" do
    before do
      allow(AhoyDashboard::Keywords).to receive(:provider).and_return(:dataforseo)
      dataforseo_configured!
    end

    it "stays on ideas bought on sample data after a real provider is chosen" do
      saved_idea("visiting hours", provider: "fake")

      get "/telemetry/seo/keyword_research", params: { seed: "visiting" }

      expect(response.body).to include("These are sample results.", "Look this phrase up again to replace them.")
    end

    it "is not shown on ideas a real provider sold" do
      saved_idea("visiting hours", provider: "dataforseo")

      get "/telemetry/seo/keyword_research", params: { seed: "visiting" }

      expect(response.body).not_to include("These are sample results.")
    end
  end
end
