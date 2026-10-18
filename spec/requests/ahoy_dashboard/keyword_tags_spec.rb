require "rails_helper"

RSpec.describe "Dashboard keyword tags", type: :request do
  let(:now) { dash_time(2026, 8, 20, 9, 0) }
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }

  around { |example| travel_to(now) { example.run } }

  def reading(keyword, position: 3)
    run = create(:dash_serp_run, keyword: keyword, checked_at: now - 1.day)
    create(:dash_serp_check, run: run, site: site, position: position)
  end

  def listed
    document.css("#tracked-searches tbody tr a[href*='/rank_keyword']").map { |link| link.text.strip }
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    describe "the keyword form" do
      it "offers the tags already in use" do
        create(:dash_serp_keyword, tags: [ "Brand", "pricing" ])

        get "/telemetry/settings/serp_keywords/new"

        field = document.at_css("#serp_keyword_tags")
        expect(field["list"]).to eq("serp_keyword_tag_suggestions")
        expect(document.css("#serp_keyword_tag_suggestions option").map { |option| option["value"] }).to eq([ "Brand", "pricing" ])
        expect(document.at_css("label[for='serp_keyword_tags']").text).to include("Tags")
        expect(field.ancestors("[data-controller='dash--tag-field']")).to be_present
      end

      it "saves the tags a keyword is given, one per chip or comma separated" do
        create(:dash_serp_keyword, tags: [ "Brand" ])

        post "/telemetry/settings/serp_keywords",
          params: { serp_keyword: { query: "visiting hours", locations: "us", pages: "1", frequency: "weekly",
                                    device: "desktop", language: "en", engine: "google", enabled: "1",
                                    tags: [ "brand", "guides, Mail " ] } }

        expect(response).to redirect_to("/telemetry/settings/serp_keywords")
        expect(AhoyDashboard::SerpKeyword.find_by(query: "visiting hours").tags).to eq([ "Brand", "guides", "Mail" ])
      end

      it "fills the edit form with the tags it has and clears them when they are all taken off" do
        keyword = create(:dash_serp_keyword, tags: [ "Brand", "guides" ])

        get "/telemetry/settings/serp_keywords/#{keyword.id}/edit"

        expect(document.at_css("#serp_keyword_tags")["value"]).to eq("Brand, guides")

        patch "/telemetry/settings/serp_keywords/#{keyword.id}",
          params: { serp_keyword: { query: keyword.query, locations: "us", pages: "1", frequency: "daily",
                                    device: "desktop", language: "en", engine: "google", enabled: "1", tags: [ "" ] } }

        expect(keyword.reload.tags).to eq([])
      end

      it "refuses a tag too long to show and says which field" do
        post "/telemetry/settings/serp_keywords",
          params: { serp_keyword: { query: "visiting hours", locations: "us", pages: "1", frequency: "daily",
                                    device: "desktop", language: "en", engine: "google", tags: [ "x" * 41 ] } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(document.at_css("#serp_keyword_tags_error").text).to include("40 characters at most")
        expect(AhoyDashboard::SerpKeyword.count).to eq(0)
      end

      it "shows each keyword's tags on the list" do
        create(:dash_serp_keyword, query: "visiting hours", tags: [ "guides" ])

        get "/telemetry/settings/serp_keywords"

        row = document.css("tbody tr").find { |node| node.text.include?("visiting hours") }
        expect(row.text.squish).to include("Tags: guides")
      end
    end

    describe "importing" do
      it "gives every imported keyword the same tags" do
        post "/telemetry/settings/serp_keyword_import",
          params: { serp_keyword_import: { pasted: "visiting hours\ncommissary list", locations: "us", pages: "1",
                                           frequency: "weekly", device: "desktop", language: "en",
                                           engine: "google", tags: [ "guides" ] } }

        expect(response).to redirect_to("/telemetry/settings/serp_keywords")
        expect(AhoyDashboard::SerpKeyword.pluck(:tags)).to eq([ [ "guides" ], [ "guides" ] ])
      end

      it "refuses the whole import over a bad tag rather than rejecting every keyword" do
        post "/telemetry/settings/serp_keyword_import",
          params: { serp_keyword_import: { pasted: "visiting hours", locations: "us", pages: "1",
                                           frequency: "weekly", device: "desktop", language: "en",
                                           engine: "google", tags: [ "x" * 41 ] } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AhoyDashboard::SerpKeyword.count).to eq(0)
      end
    end

    describe "Rankings" do
      let!(:branded) { create(:dash_serp_keyword, query: "federal prison consultant", tags: [ "Brand" ]) }
      let!(:guide) { create(:dash_serp_keyword, query: "visiting hours", tags: [ "guides" ]) }

      before do
        reading(branded, position: 2)
        reading(guide, position: 5)
      end

      it "lists All tags then every tag in use" do
        get "/telemetry/rankings"

        expect(document.at_css("#tm-rankings-tag-button").text.squish).to eq("All tags")
        expect(document.css("#tm-rankings-tag a").map { |link| link.text.squish }).to eq([ "All tags", "Brand", "guides" ])
      end

      it "reads one tag at a time and says which" do
        get "/telemetry/rankings", params: { tag: "Brand" }

        expect(listed).to eq([ "federal prison consultant" ])
        expect(document.at_css("#tm-rankings-tag-button").text.squish).to eq("Tag: Brand")
        expect(document.at_css("[aria-label='Summary figures']").text.squish).to include("Searches 1")
      end

      it "keeps the tag through the date, site and band links" do
        create(:dash_serp_site, name: "Them", domain: "rival.com")

        get "/telemetry/rankings", params: { tag: "Brand" }

        hrefs = document.css("#tm-rankings-period a, #tm-rankings-site a").map { |link| link["href"] }
        expect(hrefs).to all(include("tag=Brand"))
        expect(document.css("[aria-label='Filter tracked searches by band'] a").map { |link| link["href"] })
          .to all(include("tag=Brand"))
      end

      it "says so and offers every tag back when a tag has nothing in the range" do
        get "/telemetry/rankings", params: { tag: "Nobody" }

        expect(response.body).to include("No check tagged Nobody ran in these dates.")
        expect(document.css("a").find { |link| link.text.squish == "Show all tags" }["href"]).not_to include("tag=")
      end

      it "leaves the menu out when no keyword has a tag" do
        AhoyDashboard::SerpKeyword.update_all(tags: [])

        get "/telemetry/rankings"

        expect(document.at_css("#tm-rankings-tag")).to be_nil
      end

      it "offers a box per search that belongs to the tagging form" do
        get "/telemetry/rankings"

        form = document.at_css("form#rankings-tagging")
        boxes = document.css("input[type='checkbox'][form='rankings-tagging'][name='keyword_tag[keyword_ids][]']")

        expect(form["action"]).to eq("/telemetry/rankings/tags")
        expect(boxes.map { |box| box["value"] }).to contain_exactly(branded.id.to_s, guide.id.to_s)
        expect(form.css("button[type='submit']").map { |button| button.text.squish }).to eq([ "Add tag", "Remove tag" ])
        expect(form.at_css("button[name='_method']")["value"]).to eq("delete")
      end
    end

    describe "tagging in bulk" do
      let!(:one) { create(:dash_serp_keyword, tags: [ "Brand" ]) }
      let!(:two) { create(:dash_serp_keyword) }

      def tag_params(tag, *keywords)
        { keyword_tag: { tag: tag, keyword_ids: keywords.map { |keyword| keyword.id.to_s } },
          return_to: "/telemetry/rankings?tag=Brand" }
      end

      it "adds a tag to every ticked keyword, reusing the spelling already in use" do
        post "/telemetry/rankings/tags", params: tag_params("brand", one, two)

        expect(response).to redirect_to("/telemetry/rankings?tag=Brand")
        expect(flash[:notice]).to eq("Added Brand to 1 keyword.")
        expect(two.reload.tags).to eq([ "Brand" ])
        expect(one.reload.tags).to eq([ "Brand" ])
      end

      it "takes a tag off every ticked keyword" do
        two.update!(tags: [ "Brand", "guides" ])

        delete "/telemetry/rankings/tags", params: tag_params("BRAND", one, two)

        expect(flash[:notice]).to eq("Took Brand off 2 keywords.")
        expect(one.reload.tags).to eq([])
        expect(two.reload.tags).to eq([ "guides" ])
        expect(AhoyDashboard::SerpKeyword.tags_in_use).to eq([ "guides" ])
      end

      it "says so when nothing needed changing" do
        post "/telemetry/rankings/tags", params: tag_params("Brand", one)

        expect(flash[:notice]).to eq("Every ticked keyword already has Brand.")
      end

      it "leaves a keyword that already has every tag it can carry alone" do
        two.update!(tags: (1..AhoyDashboard::SerpKeyword::MAX_TAGS).map { |n| "tag #{n}" })

        post "/telemetry/rankings/tags", params: tag_params("Brand", two)

        expect(flash[:notice]).to eq("1 keyword already has 20 tags and was left alone.")
        expect(two.reload.tags.size).to eq(20)
      end

      it "refuses with nothing ticked or no tag typed" do
        post "/telemetry/rankings/tags", params: tag_params("Brand")
        expect(flash[:alert]).to eq("Tick at least one search first.")

        post "/telemetry/rankings/tags", params: tag_params(" ", two)
        expect(flash[:alert]).to eq("Type a tag first.")
        expect(two.reload.tags).to eq([])
      end

      it "goes back to Rankings rather than to another host" do
        post "/telemetry/rankings/tags", params: tag_params("x", two).merge(return_to: "//evil.example/rankings")

        expect(response).to redirect_to("/telemetry/rankings")
      end

      it "goes back to Rankings for any return address a browser would read as another host" do
        [ "/\t/evil.example", "/\n/evil.example", "/\r/evil.example", "//evil.example", "/\\evil.example" ].each do |value|
          post "/telemetry/rankings/tags", params: tag_params("x", two).merge(return_to: value)

          expect(response).to redirect_to("/telemetry/rankings"), value.inspect
        end
      end
    end

    describe "the SEO reports" do
      let!(:branded) { create(:dash_serp_keyword, query: "federal prison consultant", tags: [ "Brand" ]) }
      let!(:guide) { create(:dash_serp_keyword, query: "visiting hours", tags: [ "guides" ]) }

      before do
        create(:dash_serp_site, name: "Them", domain: "rival.com")
        reading(branded, position: 2)
        reading(guide, position: 5)
      end

      %w[visibility position_change landing_page keyword_gap volatility serp_feature].each do |report|
        it "puts a Tag menu on #{report} that keeps the site" do
          get "/telemetry/seo/#{report}", params: { tag: "Brand", site: site.id }

          expect(response).to have_http_status(:ok)
          expect(document.at_css("#tm-seo-tag-button").text.squish).to eq("Tag: Brand")
          expect(document.css("#tm-seo-tag a").map { |link| link.text.squish }).to eq([ "All tags", "Brand", "guides" ])
          expect(document.css("#tm-seo-tag a").map { |link| link["href"] }).to all(include("site=#{site.id}"))
          expect(document.css("#tm-seo-period a").map { |link| link["href"] }).to all(include("tag=Brand"))
        end
      end

      it "narrows Position changes to the tag" do
        get "/telemetry/seo/position_change", params: { tag: "Brand" }

        expect(response.body).to include("federal prison consultant")
        expect(response.body).not_to include("visiting hours")
      end

      it "carries the tag along the rail between rank reports" do
        get "/telemetry/seo/visibility", params: { tag: "Brand" }

        link = document.css("nav.seo-rail a").find { |node| node.text.squish == "Keyword gap" }
        expect(link["href"]).to include("tag=Brand")
      end

      it "keeps the menu off the Search Console reports" do
        get "/telemetry/seo/opportunity"

        expect(document.at_css("#tm-seo-tag")).to be_nil
      end

      it "offers every tag back when a tag has nothing in the range" do
        get "/telemetry/seo/visibility", params: { tag: "Nobody" }

        expect(response.body).to include("No tracked search tagged Nobody was read in this range.")
        expect(document.css("a").find { |link| link.text.squish == "Show all tags" }).to be_present
      end
    end
  end
end
