require "rails_helper"

RSpec.describe "Dashboard page group settings", type: :request do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    describe "index" do
      it "says there are none yet" do
        get "/telemetry/settings/page_groups"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No page groups yet")
      end

      it "does not promise that groups fold the page journey" do
        create(:dash_page_group, name: "Blog", position: 1, patterns: [ "/blog/*" ])
        dash_landing("/blog/first", at: now - 1.day, visitor: "one")

        get "/telemetry/settings/page_groups"

        expect(document.text.squish).to include("The page journey still lists each path.")
        expect(document.text.squish).not_to include("and in journeys")

        get "/telemetry/journey"

        expect(response.body).to include("/blog/first")
      end

      it "lists every rule in position order with its patterns" do
        create(:dash_page_group, name: "Later", position: 2, patterns: [ "/b/*" ])
        create(:dash_page_group, name: "Sooner", position: 1, patterns: [ "/a/*", "/c" ])

        get "/telemetry/settings/page_groups"
        chips = document.css("tbody tr").first.css(".mchip").map { |chip| chip.text.strip }

        expect(chips).to eq([ "/a/*", "/c" ])
        expect(response.body.index("Sooner")).to be < response.body.index("Later")
      end
    end

    describe "the pattern preview" do
      def summary
        document.at_css(".grp-preview-hd [data-dash--pattern-preview-target=summary]").text.strip
      end

      def rows(scope)
        document.css(scope).map { |row| row.css("span").map { |part| part.text.strip }.join(" ") }
      end

      def shown
        rows(".grp-preview .grp-list li:not(.grp-more)")
      end

      def all
        rows(".grp-list-all li")
      end

      it "lists the visited pages a pattern groups, most visited first" do
        2.times { dash_page_view(dash_visit(started_at: 1.day.ago), path: "/blog/a") }
        dash_page_view(dash_visit(started_at: 1.day.ago), path: "/blog/b")
        dash_page_view(dash_visit(started_at: 1.day.ago), path: "/pricing")
        rule = create(:dash_page_group, patterns: [ "/blog/*" ])

        get "/telemetry/settings/page_groups/#{rule.id}/edit"

        expect(shown).to eq([ "/blog/a 2 visitors", "/blog/b 1 visitor" ])
        expect(summary).to eq("Matches 2 of 3 pages visited in the last 30 days.")
      end

      it "puts the whole list in a dialog behind the last row" do
        10.times { |index| dash_page_view(dash_visit(started_at: 1.day.ago, visitor: "v#{index}"), path: "/blog/#{index}") }
        rule = create(:dash_page_group, patterns: [ "/blog/*" ])

        get "/telemetry/settings/page_groups/#{rule.id}/edit"
        opener = document.at_css(".grp-more button")

        expect(shown.size).to eq(8)
        expect(opener.text.strip).to eq("and 2 more")
        expect(opener["data-dash--modal-key-param"]).to eq("page-group-matches")
        expect(document.at_css("#tm-modal-page-group-matches .modal-title").text.strip).to eq("All 10 pages it groups")
        expect(all.size).to eq(10)
      end

      it "leaves the dialog empty of a way in while everything fits" do
        dash_page_view(dash_visit(started_at: 1.day.ago), path: "/blog/a")
        rule = create(:dash_page_group, patterns: [ "/blog/*" ])

        get "/telemetry/settings/page_groups/#{rule.id}/edit"

        expect(document.at_css(".grp-more")).to be_nil
        expect(all).to eq([ "/blog/a 1 visitor" ])
      end

      it "says there is nothing to check against without page views" do
        get "/telemetry/settings/page_groups/new"

        expect(summary).to eq("No page views in the last 30 days to check against.")
      end

      it "matches nothing with a bare star, the same as the report does" do
        dash_page_view(dash_visit(started_at: 1.day.ago), path: "/pricing")
        rule = create(:dash_page_group, patterns: [ "*" ])

        get "/telemetry/settings/page_groups/#{rule.id}/edit"

        expect(document.css(".grp-preview .grp-list li")).to be_empty
        expect(summary).to eq("Matches none of 1 page visited in the last 30 days.")
      end
    end

    describe "creating" do
      it "splits a comma separated line into patterns" do
        post "/telemetry/settings/page_groups",
             params: { page_group: { name: "Blog", patterns: "/blog/*, /changelog/*" } }

        expect(response).to redirect_to("/telemetry/settings/page_groups")
        expect(sole_item(AhoyDashboard::PageGroup).pattern_list).to eq([ "/blog/*", "/changelog/*" ])
      end

      it "refuses a rule with nothing to match" do
        post "/telemetry/settings/page_groups", params: { page_group: { name: "Blog", patterns: "  " } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AhoyDashboard::PageGroup.count).to be_zero
        expect(response.body).to include("at least one path")
      end

      it "refuses a name already taken" do
        create(:dash_page_group, name: "Blog")

        post "/telemetry/settings/page_groups", params: { page_group: { name: "Blog", patterns: "/x" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AhoyDashboard::PageGroup.count).to eq(1)
      end
    end

    it "reorders, because the first matching rule wins" do
      first = create(:dash_page_group, name: "First", position: 1)
      create(:dash_page_group, name: "Second", position: 2)

      patch "/telemetry/settings/page_groups/#{first.id}", params: { page_group: { nudge: "down" } }

      expect(AhoyDashboard::PageGroup.ordered.map(&:name)).to eq([ "Second", "First" ])
    end

    it "deletes one" do
      rule = create(:dash_page_group)

      delete "/telemetry/settings/page_groups/#{rule.id}"

      expect(response).to redirect_to("/telemetry/settings/page_groups")
      expect(AhoyDashboard::PageGroup.count).to be_zero
    end
  end

  describe "on the pages card" do
    before { sign_in create(:user, :admin) }

    def traffic!
      %w[/blog/one /blog/two /about].each_with_index do |path, index|
        dash_landing(path, at: now - 1.day, visitor: "visitor-#{index}")
      end
    end

    def labels
      document.css(".p-list .data-row .nm").map { |node| node.text.strip }
    end

    it "reads the paths as themselves until a rule is written" do
      traffic!

      get "/telemetry/reports/pages", params: { tab: "pages", breakdown: "grouped" }

      expect(labels).to contain_exactly("/blog/one", "/blog/two", "/about")
    end

    it "folds the matching paths into the group and leaves the rest alone" do
      create(:dash_page_group, name: "Blog", patterns: [ "/blog/*" ])
      traffic!

      get "/telemetry/reports/pages", params: { tab: "pages", breakdown: "grouped" }

      expect(labels).to contain_exactly("Blog", "/about")
    end

    it "counts a visitor who read two pages in the group once" do
      create(:dash_page_group, name: "Blog", patterns: [ "/blog/*" ])
      visit = dash_landing("/blog/one", at: now - 1.day, visitor: "one")
      dash_page_view(visit, path: "/blog/two", at: now - 1.day)

      get "/telemetry/reports/pages", params: { tab: "pages", breakdown: "grouped" }
      row = document.at_css(".p-list .data-row")

      expect(row.at_css(".nm").text.strip).to eq("Blog")
      expect(row.at_css(".cnt").text.strip).to eq("1")
    end

    it "leaves the plain breakdown alone" do
      create(:dash_page_group, name: "Blog", patterns: [ "/blog/*" ])
      traffic!

      get "/telemetry/reports/pages", params: { tab: "pages", breakdown: "path" }

      expect(labels).to contain_exactly("/blog/one", "/blog/two", "/about")
    end

    it "treats an underscore in a pattern as an underscore" do
      create(:dash_page_group, name: "Odd", patterns: [ "/a_b" ])
      dash_landing("/axb", at: now - 1.day, visitor: "one")

      get "/telemetry/reports/pages", params: { tab: "pages", breakdown: "grouped" }

      expect(labels).to eq([ "/axb" ])
    end
  end
end
