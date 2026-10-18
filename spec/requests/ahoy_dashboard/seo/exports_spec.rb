require "rails_helper"

RSpec.describe "Dashboard seo exports", type: :request do
  let(:now) { dash_time(2026, 8, 20, 9, 0) }
  let(:today) { now.to_date }
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }
  let(:rival) { create(:dash_serp_site, name: "Them", domain: "rival.test") }

  around { |example| travel_to(now) { example.run } }

  before do
    sign_in create(:user, :admin)
    allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(true)
    allow(AhoyDashboard::Keywords).to receive(:enabled?).and_return(true)
    allow(AhoyDashboard::Backlinks).to receive(:enabled?).and_return(true)
    allow(AhoyDashboard::Backlinks).to receive(:provider).and_return(:dataforseo)
    allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true)
    allow(AhoyDashboard::AiVisibility).to receive(:enabled?).and_return(true)
  end

  def reading(keyword, position:, url: "https://example.com/a", days_ago: 1, on: site, location: "us",
              overview: nil, cited: nil, rivals: [], run: nil)
    at = now - days_ago.days
    run ||= create(:dash_serp_run, keyword: keyword, location: location, checked_at: at)
    target = AhoyDashboard::SerpKeywordTarget.find_or_create_by!(keyword: keyword, site: on)
    create(:dash_serp_check, run: run, keyword: keyword, site: on, target: target, location: location,
           checked_at: at, position: position, url: position && url,
           ai_overview_present: overview, ai_overview_cited: cited)
    rivals.each_with_index do |domain, index|
      create(:dash_serp_result, run: run, position: index + 1, link: "https://#{domain}/x",
             domain: domain, checked_at: at)
    end
    run
  end

  def tracked_keywords
    @tracked_keywords ||= begin
      site
      visiting = create(:dash_serp_keyword, query: "visiting hours")
      consult = create(:dash_serp_keyword, query: "prison consultant")
      money = create(:dash_serp_keyword, query: "commissary money")

      reading(visiting, position: 9, url: "https://example.com/visiting", days_ago: 6, rivals: %w[bop.gov rival.test])
      cited = reading(visiting, position: 3, url: "https://example.com/visiting", days_ago: 1,
                      overview: true, cited: true, rivals: %w[bop.gov example.com rival.test])
      create(:dash_serp_ai_citation, run: cited, slot: 1, link: "https://example.com/visiting", domain: "example.com")
      create(:dash_serp_ai_citation, run: cited, slot: 2, link: "https://bop.gov/visiting", domain: "bop.gov")
      reading(consult, position: 12, url: "https://example.com/consult", days_ago: 6)
      reading(consult, position: 4, url: "https://example.com/consult", days_ago: 1, overview: true)
      reading(money, position: 7, url: "https://example.com/money", days_ago: 6)
      reading(money, position: nil, days_ago: 1)

      [ visiting, consult, money ]
    end
  end

  def competitor_readings
    tracked_keywords.each_with_index do |keyword, index|
      reading(keyword, position: index + 2, url: "https://rival.test/a", days_ago: 1, on: rival)
    end
  end

  def search_console_rows
    AhoyDashboard::SearchConsoleKeyword.absorb([
      { date: today - 2, query: "federal prison consultant", clicks: 40, impressions: 900, ctr: 0.044, position: 4.2 },
      { date: today - 2, query: "halfway house rules", clicks: 2, impressions: 400, ctr: 0.005, position: 14.0 },
      { date: today - 2, query: "example prison guide", clicks: 30, impressions: 200, ctr: 0.15, position: 1.4 },
      { date: today - 3, query: "federal prison consultant", clicks: 30, impressions: 700, ctr: 0.043, position: 5.1 }
    ])
    AhoyDashboard::SearchConsoleTotal.create!(date: today - 2, clicks: 80, impressions: 1600, ctr: 0.05, position: 6.1)

    [ [ "https://example.com/consult", 5.0, 30 ], [ "https://example.com/guide", 9.0, 12 ] ].each do |page, position, clicks|
      3.times do |day|
        create(:dash_search_console_row, date: today - (day + 2), query: "federal prison consultant",
               page: page, clicks: clicks, impressions: clicks * 12, ctr: 0.08, position: position)
      end
    end
  end

  def converting_visits
    create(:dash_goal, display_name: "Consult booked", event_name: "consult_booked")

    2.times do |index|
      visit = dash_visit(started_at: now - 2.days - index.minutes, visitor: "v#{index}",
                         landing_page: "https://example.com/consult", referrer: "https://www.google.com/")
      dash_page_view(visit, path: "/consult", at: now - 2.days - index.minutes)
      dash_goal(visit, "consult_booked", at: now - 2.days - index.minutes) if index.zero?
    end
  end

  def keyword_ideas
    [ [ "visiting hours federal prison", 1200, 20 ], [ "how long are prison visits", 400, 30 ],
      [ "visiting hours rules", 90, 70 ] ].each do |query, volume, difficulty|
      create(:dash_keyword_idea, seed: "visiting", query: query, location: "us", language: "en",
             volume: volume, difficulty: difficulty, cpc: 1.25, intent: "informational",
             provider: "fake", fetched_at: now - 1.day)
    end
  end

  def backlink_rows
    create(:dash_backlink_domain, domain: "press.test", authority: 55, links: 4, follow: true,
           first_seen_on: today - 200, last_seen_on: today, provider: "dataforseo")
    create(:dash_backlink_domain, domain: "fresh.test", authority: 20, links: 1, follow: true,
           first_seen_on: today - 1, last_seen_on: today, provider: "dataforseo")
    create(:dash_backlink_domain, domain: "gone.test", authority: 10, links: 1, follow: true,
           first_seen_on: today - 90, last_seen_on: today - 2, lost_on: today - 1,
           provider: "dataforseo")
    create(:dash_backlink_domain, domain: "forum.test", authority: 15, links: 7, follow: false,
           first_seen_on: today - 30, last_seen_on: today, provider: "dataforseo")
    create(:dash_backlink_anchor, text: "prison consultant", domains: 2, links: 5, seen_on: today)
    create(:dash_backlink_sample, on: today - 1, domains: 3, links: 12, provider: "dataforseo")
  end

  def answered_prompts
    create(:dash_ai_assistant, :keyed, name: "openai")
    prompt = create(:dash_ai_prompt, text: "who helps with federal prison prep")
    create(:dash_ai_answer, prompt: prompt, model: "gpt-5", mentioned: true, cited: true, position: 2)
    create(:dash_ai_answer, prompt: prompt, model: "gpt-5", assistant: "anthropic")
    create(:dash_ai_source, answer: AhoyDashboard::AiVisibility::Answer.first, domain: "rival.test")
  end

  def serp_feature_pages
    tracked_keywords.each do |keyword|
      run = create(:dash_serp_run, keyword: keyword, checked_at: now - 1.day)
      create(:dash_serp_run_page, run: run, response: {
        "tasks" => [ { "result" => [ { "items" => [
          { "type" => "featured_snippet", "domain" => "example.com", "title" => "A snippet" },
          { "type" => "people_also_ask", "items" => [ { "title" => "Who qualifies?" }, { "title" => "How long?" } ] },
          { "type" => "related_searches", "items" => [ "first step act", "halfway house" ] }
        ] } ] } ]
      })
    end
  end

  describe "the rank tracking screens" do
    before { tracked_keywords }

    it "exports every table on Rankings" do
      expect_csv_downloads("/telemetry/rankings", at_least: 3)
    end

    it "exports every table on one keyword" do
      expect_csv_downloads("/telemetry/rank_keyword?keyword=#{tracked_keywords.first.id}", at_least: 2)
    end

    it "exports every table on Visibility" do
      expect_csv_downloads("/telemetry/seo/visibility")
    end

    it "exports every table on Position changes" do
      expect_csv_downloads("/telemetry/seo/position_change")
    end

    it "exports every table on Landing pages" do
      expect_csv_downloads("/telemetry/seo/landing_page")
    end

    it "exports every table on Keyword gap" do
      competitor_readings

      expect_csv_downloads("/telemetry/seo/keyword_gap", at_least: 2)
    end

    it "exports every table on Volatility" do
      expect_csv_downloads("/telemetry/seo/volatility")
    end

    it "exports every table on SERP features" do
      serp_feature_pages

      expect_csv_downloads("/telemetry/seo/serp_feature", at_least: 2)
    end
  end

  describe "the search console screens" do
    before { search_console_rows }

    it "exports the rows on Performance" do
      expect_csv_downloads("/telemetry/search_console_report")
    end

    it "exports every table on Opportunities" do
      expect_csv_downloads("/telemetry/seo/opportunity", at_least: 2)
    end

    it "exports the searches on Cannibalization" do
      expect_csv_downloads("/telemetry/seo/cannibalization")
    end

    it "exports both sides of Brand vs. non-brand" do
      expect_csv_downloads("/telemetry/seo/brand_split", at_least: 2)
    end

    it "exports every table on Search to conversion" do
      converting_visits

      expect_csv_downloads("/telemetry/seo/conversion")
    end
  end

  describe "the research and monitoring screens" do
    it "exports every table on Keyword research" do
      keyword_ideas

      expect_csv_downloads("/telemetry/seo/keyword_research?seed=visiting&location=us&language=en", at_least: 2)
    end

    it "exports every table on Backlinks" do
      backlink_rows

      expect_csv_downloads("/telemetry/seo/backlink", at_least: 3)
    end

    it "exports the feed and the rules on Alerts" do
      create(:dash_alert_event, fired_at: now - 1.hour)

      expect_csv_downloads("/telemetry/seo/alert", at_least: 2)
    end

    it "exports every table on AI visibility" do
      answered_prompts

      expect_csv_downloads("/telemetry/seo/ai_visibility", at_least: 2)
    end
  end

  describe "what a download holds" do
    it "carries the headings the table shows, and the rows in the order it shows them" do
      tracked_keywords

      rows = fetch_csv("/telemetry/rankings.csv?table=tracked_searches&site=#{site.id}")

      expect(rows.first).to eq([ "Search", "Position", "Change", "Best", "AI", "URL" ])
      expect(rows.drop(1).map(&:first)).to eq([ "visiting hours", "prison consultant", "commissary money" ])
      expect(rows[1]).to eq([ "visiting hours", "3", "6", "3", "Cited", "/visiting" ])
    end

    it "splits a rate the page tucks into another cell into its own column" do
      backlink_rows

      rows = fetch_csv("/telemetry/seo/backlink.csv?table=domains")

      expect(rows.first).to eq([ "Domain", "Authority", "Links", "First seen", "Follow" ])
      expect(rows).to include([ "forum.test", "15", "7", (today - 30).iso8601, "Nofollow" ])
    end

    it "writes a timestamp where the page says how long ago" do
      create(:dash_alert_event, fired_at: now - 1.hour, headline: "Fell off page one", detail: "Was 8, now 14")

      rows = fetch_csv("/telemetry/seo/alert.csv?table=recent")

      expect(rows.first).to eq([ "When", "Severity", "What happened", "Detail", "Rule", "Sample data" ])
      expect(rows.second.first).to eq((now - 1.hour).iso8601)
    end

    it "leaves an unknown number as an empty cell rather than a dash" do
      tracked_keywords

      rows = fetch_csv("/telemetry/seo/visibility.csv?table=not_ranking&site=#{site.id}")

      expect(rows).to eq([ [ "Search" ], [ "commissary money" ] ])
    end
  end

  describe "the shape of a download" do
    before { tracked_keywords }

    it "names a single table screen after the report alone" do
      get "/telemetry/seo/volatility.csv"

      expect(csv_filename).to eq("ahoy-dashboard-seo-volatility-#{today.iso8601}.csv")
    end

    it "names a screen with several tables after the table too" do
      get "/telemetry/rankings.csv", params: { table: "page_one" }

      expect(csv_filename).to eq("ahoy-dashboard-seo-rankings-page-one-#{today.iso8601}.csv")
    end

    it "is a 404 for a table that does not exist" do
      get "/telemetry/rankings.csv", params: { table: "nonsense" }

      expect(response).to have_http_status(:not_found)
    end

    it "is a 404 for a screen with nothing to export" do
      get "/telemetry/seo.csv"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "a range with nothing in it" do
    it "carries the header row and nothing else" do
      rows = fetch_csv("/telemetry/seo/visibility.csv")

      expect(rows.size).to eq(1)
    end
  end
end
