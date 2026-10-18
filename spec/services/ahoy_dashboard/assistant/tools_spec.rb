require "rails_helper"

RSpec.describe "Dashboard assistant tools" do
  describe AhoyDashboard::Assistant::Tools::TrafficSummary do
    it "answers with the headline figures and says crawlers are out" do
      answer = described_class.new.execute(days: 7)

      expect(answer[:days]).to eq(7)
      expect(answer[:crawlers]).to eq("excluded")
      expect(answer[:figures]).to include("visitors")
    end
  end

  describe AhoyDashboard::Assistant::Tools::Breakdown do
    it "lists the dimensions when it is not told which one" do
      answer = described_class.new.execute

      expect(answer[:dimensions].map { |row| row[:key] }).to include("page", "source")
    end

    it "refuses a dimension nobody registered and offers the list" do
      answer = described_class.new.execute(dimension: "nonsense")

      expect(answer[:error]).to include("nonsense")
      expect(answer[:dimensions]).to be_present
    end

    context "with a dimension the host withheld" do
      before { AhoyDashboard::Setting.write(AhoyDashboard::Assistant::WITHHELD_KEY, %w[city]) }

      it "leaves it off the list" do
        keys = described_class.new.execute[:dimensions].map { |row| row[:key] }

        expect(keys).to include("country")
        expect(keys).not_to include("city")
      end

      it "refuses to read it" do
        answer = described_class.new.execute(dimension: "city", days: 7)

        expect(answer[:error]).to include("kept out of the assistant")
        expect(answer).not_to have_key(:rows)
      end
    end

    it "groups by one dimension" do
      answer = described_class.new.execute(dimension: "page", days: 7, limit: 3)

      expect(answer[:dimension]).to eq("page")
      expect(answer[:rows]).to be_an(Array)
    end
  end

  describe AhoyDashboard::Assistant::Tools::Trend do
    it "buckets a metric over time" do
      answer = described_class.new.execute(metric: "visitors", days: 7)

      expect(answer[:metric]).to eq("visitors")
      expect(answer[:points]).to be_an(Array)
    end

    it "refuses a metric nobody registered and offers the list" do
      answer = described_class.new.execute(metric: "nonsense")

      expect(answer[:error]).to include("nonsense")
      expect(answer[:metrics]).to include("visitors")
    end
  end

  describe AhoyDashboard::Assistant::Tools::SearchConsole do
    it "says the counts are short of the truth by design" do
      answer = described_class.new.execute(days: 7)

      expect(answer[:note]).to include("google withholds rare queries")
      expect(answer[:queries]).to be_an(Array)
    end

    it "reads one keyword's history" do
      create(:dash_search_console_keyword, query: "visiting hours", date: Date.current - 2,
             clicks: 3, impressions: 90, position: 8.4)

      answer = described_class.new.execute(query: "visiting hours", days: 7)

      expect(answer[:keyword]).to eq("visiting hours")
      expect(answer[:totals][:clicks]).to eq(3)
    end
  end

  describe AhoyDashboard::Assistant::Tools::Rankings do
    it "says there is nothing to look for before a site is set up" do
      expect(described_class.new.execute[:error]).to include("no site is set up")
    end

    it "reads the tracked searches" do
      create(:dash_serp_site, domain: "example.com")

      answer = described_class.new.execute(days: 7)

      expect(answer[:site]).to eq("example.com")
      expect(answer[:searches]).to eq([])
    end

    it "says a keyword is not tracked rather than inventing one" do
      create(:dash_serp_site, domain: "example.com")

      answer = described_class.new.execute(query: "not tracked")

      expect(answer[:error]).to include("not tracked")
    end

    it "finds a tracked keyword whatever case it is asked about in" do
      create(:dash_serp_site, domain: "example.com")
      create(:dash_serp_keyword, query: "Visiting Hours")

      answer = described_class.new.execute(query: "visiting hours")

      expect(answer[:error]).to be_nil
      expect(answer[:keyword]).to eq("Visiting Hours")
    end
  end

  describe AhoyDashboard::Assistant::Tools::AppContext do
    it "finds the screen somebody is describing" do
      answer = described_class.new.execute(topic: "how do I track a keyword ranking")

      expect(answer[:screens].map { |screen| screen[:path] }).to include("/telemetry/settings/serp_keywords")
    end

    it "hands back everything when it cannot tell" do
      expect(described_class.new.execute[:screens].size).to eq(described_class::SCREENS.size)
    end

    it "gives back paths that are real routes" do
      described_class.new.execute[:screens].each do |screen|
        relative_path = screen[:path].delete_prefix(AhoyDashboard.mount_path).presence || "/"
        expect { AhoyDashboard::Engine.routes.recognize_path(relative_path) }.not_to raise_error
      end
    end
  end

  describe "filters" do
    let(:us) { { "dimension" => "country", "operator" => "is", "value" => "US" } }
    let(:conversation) { AhoyDashboard::Assistant::Slice.from_context("slice" => { "filters" => [ us ] }) }

    before do
      travel_to(dash_time(2026, 8, 21, 14, 30))
      [ "US", "US", "CA" ].each do |country|
        dash_page_view(dash_visit(started_at: 1.day.ago, visitor: SecureRandom.uuid, country: country))
      end
    end

    after { travel_back }

    def visitors(answer)
      answer[:figures]["visitors"][:value]
    end

    it "reads the slice the conversation is about" do
      answer = AhoyDashboard::Assistant::Tools::TrafficSummary.new(slice: conversation).execute(days: 7)

      expect(visitors(answer)).to eq(2)
      expect(answer[:filters]).to eq([ "Country is US" ])
    end

    it "reads the whole site when the model passes an empty list" do
      answer = AhoyDashboard::Assistant::Tools::TrafficSummary.new(slice: conversation).execute(days: 7, filters: [])

      expect(visitors(answer)).to eq(3)
      expect(answer[:filters]).to eq("none, the whole site")
      expect(answer[:filters_from]).to eq("you")
    end

    it "reads a slice the model asked for in place of the conversation's" do
      answer = AhoyDashboard::Assistant::Tools::Breakdown.new(slice: conversation)
        .execute(dimension: "country", days: 7, filters: [ { "dimension" => "country", "value" => "CA" } ])

      expect(answer[:rows]).to eq([ { name: "CA", visitors: 1 } ])
    end

    it "reads the default segment on a conversation that saved no slice, and says so" do
      create(:dash_segment, applied_by_default: true)

      answer = AhoyDashboard::Assistant::Tools::TrafficSummary.new.execute(days: 7)

      expect(visitors(answer)).to eq(2)
      expect(answer[:filters_from]).to eq("the dashboard's defaults")
    end

    it "does not bring the default segment back into a conversation saved with none" do
      create(:dash_segment, applied_by_default: true)
      none = AhoyDashboard::Assistant::Slice.from_context("slice" => { "filters" => "none" })

      expect(visitors(AhoyDashboard::Assistant::Tools::TrafficSummary.new(slice: none).execute(days: 7))).to eq(3)
    end

    it "compares against the same slice" do
      answer = AhoyDashboard::Assistant::Tools::TrafficSummary.new(slice: conversation)
        .execute(days: 7, compare: "previous_period")

      expect(answer[:figures]["visitors"][:change]).to be_nil.or(be_a(Numeric))
      expect(answer[:compared_to]).to be_present
    end

    it "counts the trend's points and its total through the slice" do
      answer = AhoyDashboard::Assistant::Tools::Trend.new(slice: conversation).execute(metric: "visitors", days: 7)

      expect(answer[:total][:value]).to eq(2)
      expect(answer[:points].sum { |point| point[:value] }).to eq(2)
    end

    it "puts the filters on what it draws and on the link through" do
      views = AhoyDashboard::Assistant::Views.new
      AhoyDashboard::Assistant::Tools::Breakdown.new(views: views, slice: conversation)
        .execute(dimension: "page", days: 7)
      drawn = views.to_a.first

      expect(drawn.subtitle).to eq("By visitors, Country is US")
      expect(Rack::Utils.parse_nested_query(URI(drawn.path).query)["filters"]).to eq([ us ])
    end

    it "reads an or group the model asked for, and says it with or" do
      views = AhoyDashboard::Assistant::Views.new
      answer = AhoyDashboard::Assistant::Tools::TrafficSummary.new(views: views, slice: conversation)
        .execute(days: 7, filters: [ { "dimension" => "country", "value" => "US", "group" => 0 },
                                     { "dimension" => "country", "value" => "CA", "group" => 0 } ])

      expect(visitors(answer)).to eq(3)
      expect(answer[:filters]).to eq([ "Country is US or CA" ])
      expect(views.to_a.first.subtitle).to eq("Crawlers excluded, Country is US or CA")
    end

    it "carries the crawler toggle into the read and the link" do
      views = AhoyDashboard::Assistant::Views.new
      slice = AhoyDashboard::Assistant::Slice.from_context("slice" => { "filters" => "none", "crawlers" => true })

      answer = AhoyDashboard::Assistant::Tools::TrafficSummary.new(views: views, slice: slice).execute(days: 7)

      expect(answer[:crawlers]).to eq("included")
      expect(views.to_a.first.subtitle).to eq("Crawlers included")
      expect(views.to_a.first.path).to include("crawlers=1")
    end

    it "reads nothing and draws nothing when a filter is wrong" do
      views = AhoyDashboard::Assistant::Views.new
      answer = AhoyDashboard::Assistant::Tools::Breakdown.new(views: views)
        .execute(dimension: "page", filters: [ { "dimension" => "nonsense", "value" => "x" } ])

      expect(answer[:error]).to include("nothing was read").and include("nonsense")
      expect(answer[:dimensions]).to include("country")
      expect(answer[:operators]).to include("is_not")
      expect(views).not_to be_any
    end

    it "says Search Console cannot apply the filters" do
      views = AhoyDashboard::Assistant::Views.new
      create(:dash_search_console_keyword, query: "visiting hours", date: Date.current - 2,
             clicks: 3, impressions: 90, position: 8.4)

      answer = AhoyDashboard::Assistant::Tools::SearchConsole.new(views: views, slice: conversation)
        .execute(query: "visiting hours", days: 7)

      expect(answer[:filters]).to eq("none, the whole site")
      expect(answer[:filters_not_applied]).to eq([ "Country is US" ])
      expect(views.to_a.first.subtitle).to include("filters do not apply here")
    end

    it "says rank tracking cannot apply the filters" do
      create(:dash_serp_site, domain: "example.com")

      answer = AhoyDashboard::Assistant::Tools::Rankings.new(slice: conversation).execute(days: 7)

      expect(answer[:filters_not_applied]).to eq([ "Country is US" ])
    end

    it "says nothing about filters it did not have" do
      create(:dash_serp_site, domain: "example.com")

      answer = AhoyDashboard::Assistant::Tools::Rankings.new.execute(days: 7)

      expect(answer).not_to have_key(:filters_not_applied)
      expect(answer[:filters]).to eq("none, the whole site")
    end

    it "gives the model the fixed choices as enums rather than prose" do
      properties = lambda do |tool|
        AhoyDashboard::Assistant::Tools.const_get(tool).to_function.dig("function", "parameters", "properties")
      end

      expect(properties.call(:TrafficSummary).dig("period", "enum")).to eq(AhoyDashboard::Assistant::Window.keys)
      expect(properties.call(:TrafficSummary).dig("compare", "enum")).to eq(AhoyDashboard::QueryForm::COMPARISONS)
      expect(properties.call(:Trend).dig("metric", "enum")).to eq(AhoyDashboard::Metric::ALL.map(&:key))
      expect(properties.call(:Trend).dig("interval", "enum")).to eq(%w[hour day week month])
      expect(properties.call(:Breakdown).dig("from", "format")).to eq("date")
    end

    it "says when to call each tool that reads data" do
      AhoyDashboard::Assistant.tool_classes.each do |tool|
        expect(tool.desc).to include("Call this")
      end
    end

    it "offers every data tool the same filters param" do
      AhoyDashboard::Assistant.tool_classes.excluding(AhoyDashboard::Assistant::Tools::AppContext).each do |tool|
        filters = tool.to_function.dig("function", "parameters", "properties", "filters")

        expect(filters).to include("type" => "array")
        expect(filters.dig("items", "properties", "operator", "enum")).to eq(AhoyDashboard::Filter::OPERATORS.keys)
        expect(filters.dig("items", "properties", "group")).to include("type" => "integer", "minimum" => 0)
        expect(filters.dig("items", "required")).to eq(%w[dimension value])
        expect(filters["description"]).to include("share a group number")
      end
    end
  end

  describe "saying what actually reached the screen" do
    let(:views) { AhoyDashboard::Assistant::Views.new }

    def series(title)
      AhoyDashboard::Assistant::View.series(title: title, points: [ [ Time.current, 1 ], [ Time.current, 2 ] ])
    end

    it "says drawn false once the screen already holds as many as it takes" do
      AhoyDashboard::Assistant::Views::LIMIT.times { |index| views.push(series("one #{index}")) }

      answer = AhoyDashboard::Assistant::Tools::Trend.new(views: views).execute(metric: "visitors", days: 7)

      expect(answer[:drawn]).to be(false)
      expect(answer[:not_drawn]).to include("not shown")
      expect(views.to_a.size).to eq(AhoyDashboard::Assistant::Views::LIMIT)
    end

    it "says drawn true when it did reach the screen" do
      answer = AhoyDashboard::Assistant::Tools::Trend.new(views: views).execute(metric: "visitors", days: 7)

      expect(answer[:drawn]).to be(true)
      expect(answer).not_to have_key(:not_drawn)
    end

    it "says drawn false when there is nowhere to draw" do
      answer = AhoyDashboard::Assistant::Tools::Trend.new.execute(metric: "visitors", days: 7)

      expect(answer[:drawn]).to be(false)
    end

    it "names the rows of a long breakdown that did not fit on the table" do
      30.times do |index|
        visit = Ahoy::Visit.create!(visitor_token: SecureRandom.uuid, visit_token: SecureRandom.uuid,
                                    started_at: 1.day.ago)
        Ahoy::Event.create!(visit: visit, name: AhoyDashboard::PAGE_VIEW, time: 1.day.ago,
                            properties: { path: "/page-#{index}" })
      end

      answer = AhoyDashboard::Assistant::Tools::Breakdown.new(views: views)
        .execute(dimension: "page", days: 7, limit: 30)

      expect(answer[:rows].size).to eq(30)
      expect(answer[:drawn]).to be(true)
      expect(answer[:not_drawn]).to eq("only the first 25 rows are on the screen. the other 5 are not")
      expect(views.to_a.first.rows.size).to eq(25)
    end
  end

  describe "a trend for a metric it cannot chart" do
    it "refuses rather than drawing visitors under that metric's name" do
      views = AhoyDashboard::Assistant::Views.new

      %w[events revenue_total conversion_rate].each do |metric|
        answer = AhoyDashboard::Assistant::Tools::Trend.new(views: views).execute(metric: metric, days: 7)

        expect(answer[:error]).to include(metric, "can not be charted")
        expect(answer[:metrics]).to include("visitors")
        expect(answer[:metrics]).not_to include(metric)
      end

      expect(views).not_to be_any
    end
  end

  describe "one search's Search Console history" do
    it "leaves position empty on a day with no impressions rather than reading 0.0" do
      views = AhoyDashboard::Assistant::Views.new
      create(:dash_search_console_keyword, query: "visiting hours", date: Date.current - 3,
             clicks: 0, impressions: 0, position: 0)
      create(:dash_search_console_keyword, query: "visiting hours", date: Date.current - 2,
             clicks: 3, impressions: 90, position: 8.4)

      answer = AhoyDashboard::Assistant::Tools::SearchConsole.new(views: views)
        .execute(query: "visiting hours", days: 7)

      empty = answer[:days].find { |day| day[:date] == Date.current - 3 }
      full = answer[:days].find { |day| day[:date] == Date.current - 2 }
      expect(empty[:position]).to be_nil
      expect(full[:position]).to eq(8.4)
      expect(answer[:note]).to include("not a top spot")

      shown = views.to_a.first.rows.find { |row| row[:date] == Date.current - 3 }
      expect(shown[:position]).to eq("None")
    end

    it "leaves the total position empty when there were no impressions at all" do
      create(:dash_search_console_keyword, query: "visiting hours", date: Date.current - 2,
             clicks: 0, impressions: 0, position: 0)

      answer = AhoyDashboard::Assistant::Tools::SearchConsole.new.execute(query: "visiting hours", days: 7)

      expect(answer[:totals][:position]).to be_nil
    end
  end

  describe "rankings with no site that is this one" do
    it "refuses to read a competitor as the site's own ranking" do
      create(:dash_serp_site, domain: "competitor.example.org")

      answer = AhoyDashboard::Assistant::Tools::Rankings.new.execute(days: 7)

      expect(answer[:error]).to include("no tracked site is this one")
      expect(answer[:tracked_sites]).to eq([ "competitor.example.org" ])
      expect(answer).not_to have_key(:searches)
    end
  end

  it "keeps its own thread rather than mixing in the gem's active record integration" do
    expect(AhoyDashboard::Chat.new).not_to respond_to(:ask)
    expect(AhoyDashboard::ChatMessage.new).not_to respond_to(:tool_call)
  end
end
