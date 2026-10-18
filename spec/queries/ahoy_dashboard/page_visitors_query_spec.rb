# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::PageVisitorsQuery do
  let(:now) { dash_time(2026, 8, 10, 12) }
  let(:query) { AhoyDashboard::QueryForm.from_params({ period: "day" }) }
  let(:report) { AhoyDashboard::Report.find("pages") }

  around { |example| travel_to(now) { example.run } }

  before do
    12.times do |index|
      visit = dash_landing("/page-#{index}", at: now - 1.hour, visitor: "visitor-#{index % 3}", country: "US")
      dash_page_view(visit, path: "/shared", at: now + 1.day)
    end
    visitor = dash_visit(started_at: now, visitor: "only-goal", country: "CA")
    dash_goal(visitor, "signup")
    blank = dash_visit(started_at: now, visitor: "blanks")
    [nil, "", " ", "\t"].each { |path| dash_page_view(blank, path: path) }
    bot = dash_visit(started_at: now, visitor: "crawler", country: "CA")
    dash_page_view(bot, path: "/crawler", crawler: "GPTBot")
  end

  def result(form: query, **options)
    AhoyDashboard::ReportQuery.call(query: form, report: report, **options).result
  end

  def shared(form: query)
    AhoyDashboard::JourneyQuery.new(scope: form.scope).page_visitors
  end

  it "preserves exact ranking, pagination, blanks, returning visitors and the report denominator" do
    expect(result(page_visitors: shared)).to eq(result)
  end

  it "preserves crawler-inclusive counts" do
    form = AhoyDashboard::QueryForm.from_params({ period: "day", crawlers: "1" })

    expect(result(form: form, page_visitors: shared(form: form))).to eq(result(form: form))
  end

  it "shares a visit-filtered population without changing its counts" do
    form = AhoyDashboard::QueryForm.from_params({ period: "day", filters: dash_filters(["country", "is", "US"]).to_param })

    expect(result(form: form, page_visitors: shared(form: form))).to eq(result(form: form))
  end

  it "keeps page-filtered reports separate from the full session journey" do
    form = AhoyDashboard::QueryForm.from_params({ period: "day", filters: dash_filters(["page", "is", "/shared"]).to_param })

    expect(result(form: form, page_visitors: shared(form: form)).rows.map(&:value)).to eq(["/shared"])
  end

  it "rejects a prepared population from another date range" do
    yesterday = AhoyDashboard::QueryForm.from_params({ period: "yesterday" })

    expect(result(form: yesterday, page_visitors: shared)).to eq(result(form: yesterday))
  end

  it "preserves fresh custom page labels" do
    previous = AhoyDashboard::ValueLabels.registry["page"]
    prepared = shared
    prepared.call
    AhoyDashboard::ValueLabels.register("page") { |_values| {"/shared" => "Current title"} }

    expect(result(page_visitors: prepared).rows.first.label).to eq("Current title")
  ensure
    previous ? AhoyDashboard::ValueLabels.registry["page"] = previous : AhoyDashboard::ValueLabels.registry.delete("page")
  end

  it "rejects a prepared population after the host changes schemas" do
    connection = AhoyDashboard.visit.connection
    previous = connection.schema_search_path
    prepared = shared
    prepared.call
    connection.schema_search_path = "pg_catalog, public"

    expect(prepared.report_result(scope: query.scope, dimension: AhoyDashboard::Dimension.find("page"), limit: 9)).to be_nil
  ensure
    connection.schema_search_path = previous
  end

  it "does not replace detail metrics with the visitors-only reading" do
    expect(result(details: true, page_visitors: shared)).to eq(result(details: true))
  end

  it "does not replace another breakdown with page counts" do
    expect(result(tab: "entries", page_visitors: shared)).to eq(result(tab: "entries"))
  end

  it "reads the page grouping once for the report and initial journey" do
    journey = AhoyDashboard::JourneyQuery.new(scope: query.scope)
    statements = captured_sql("ahoy_events") do
      AhoyDashboard.visit.uncached do
        result(page_visitors: journey.page_visitors)
        journey.call
      end
    end

    expect(statements.count { |sql| sql.include?("GROUP BY") }).to eq(1)
  end

  it "does not offer prepared counts for a chosen journey path" do
    expect(AhoyDashboard::JourneyQuery.new(scope: query.scope, chain: ["/shared"]).page_visitors).to be_nil
  end

  it "does not offer prepared counts for a searched journey" do
    expect(AhoyDashboard::JourneyQuery.new(scope: query.scope, searches: ["shared"]).page_visitors).to be_nil
  end
end
