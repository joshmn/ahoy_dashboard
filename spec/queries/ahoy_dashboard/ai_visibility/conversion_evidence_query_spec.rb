require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::ConversionEvidenceQuery do
  let(:today) { dash_time(2026, 8, 10, 12) }
  let(:range) { (today - 6.days).beginning_of_day..today.end_of_day }

  around { |example| travel_to(today) { example.run } }

  def scope(**options)
    AhoyDashboard::ScopeQuery.call(range: range, **options)
  end

  def evidence(**options)
    described_class.call(scope: scope, **options)
  end

  def visit!(token, at:, landing: "https://example.com/", **attributes)
    create(:ahoy_visit, visitor_token: token, started_at: at, landing_page: landing, **attributes)
  end

  def view!(visit, path, at: visit.started_at)
    create(:page_view_event, visit: visit, time: at,
                             properties: { "path" => path, "controller" => "pages", "action" => "show" })
  end

  def signup!(visit, at: visit.started_at + 5.minutes)
    create(:ahoy_event, visit: visit, name: "signed_up", time: at, properties: {})
  end

  context "with a goal" do
    let!(:goal) { create(:dash_goal, event_name: "signed_up") }

    it "walks back to the first visit, even one from before the window" do
      first = visit!("converter", at: today - 20.days, landing: "https://example.com/compare?ref=x",
                                  referrer: "https://www.google.com/", referring_domain: "google.com")
      view!(first, "/compare")
      later = visit!("converter", at: today - 1.day, landing: "https://example.com/pricing")
      view!(later, "/pricing")
      signup!(later)

      result = evidence

      expect(result.anchor).to eq(:goal)
      expect(result.converters).to eq(1)
      expect(result.channels.map(&:label)).to eq([ "Organic Search" ])
      expect(result.entry_pages.map(&:path)).to eq(%w[/compare /pricing])
      expect(result.entry_pages.first.first_touch).to eq(1)
      expect(result.entry_pages.second.first_touch).to eq(0)
      expect(result.entry_pages.second.any_touch).to eq(1)
    end

    it "ignores visits from past the lookback" do
      old = visit!("converter", at: today - 100.days, landing: "https://example.com/ancient")
      view!(old, "/ancient")
      recent = visit!("converter", at: today - 1.day, landing: "https://example.com/pricing")
      signup!(recent)

      expect(evidence.entry_pages.map(&:path)).to eq([ "/pricing" ])
    end

    it "only counts conversions inside the window" do
      before = visit!("early", at: today - 30.days)
      signup!(before)

      expect(evidence.converters).to eq(0)
    end

    it "ranks the pages converters viewed before converting against everyone else" do
      3.times do |n|
        visit = visit!("converter-#{n}", at: today - 1.day)
        view!(visit, "/vs-rival")
        view!(visit, "/")
        signup!(visit, at: visit.started_at + 10.minutes)
        view!(visit, "/welcome", at: visit.started_at + 20.minutes)
      end
      6.times do |n|
        visit = visit!("browser-#{n}", at: today - 1.day)
        view!(visit, "/")
      end
      visit = visit!("browser-rival", at: today - 1.day)
      view!(visit, "/vs-rival")

      rows = evidence.before_conversion.index_by(&:path)

      expect(rows.keys).to eq(%w[/vs-rival /])
      expect(rows["/vs-rival"].converters).to eq(3)
      expect(rows["/vs-rival"].others).to eq(1)
      expect(rows["/vs-rival"].lift).to be_within(0.01).of(7.0)
      expect(rows["/"].lift).to be_within(0.01).of(7.0 / 6)
    end

    it "lists the paid search terms converters arrived on" do
      visit = visit!("converter", at: today - 1.day, utm_source: "google", utm_medium: "cpc",
                                  utm_term: "Prison Consultant")
      signup!(visit)

      expect(evidence.paid_terms.map(&:label)).to eq([ "prison consultant" ])
    end

    it "lists where AI assistants send visitors and how many of them converted" do
      sent = visit!("from-ai", at: today - 1.day, landing: "https://example.com/guide",
                               referrer: "https://chatgpt.com/", referring_domain: "chatgpt.com")
      view!(sent, "/guide")
      signup!(sent)
      other = visit!("from-ai-too", at: today - 2.days, landing: "https://example.com/guide",
                                    referrer: "https://www.perplexity.ai/", referring_domain: "www.perplexity.ai")
      view!(other, "/guide")

      landing = sole_item(evidence.ai_landings)

      expect(landing.path).to eq("/guide")
      expect(landing.visitors).to eq(2)
      expect(landing.converters).to eq(1)
      expect(landing.assistants).to eq(%w[chatgpt.com perplexity.ai])
    end

    it "names the Google searches that land on a converter's entry page" do
      visit = visit!("converter", at: today - 1.day, landing: "https://example.com/compare/")
      signup!(visit)
      AhoyDashboard::SearchConsoleRow.absorb([
        { date: (today - 1.day).to_date, query: "best tool", page: "https://example.com/compare", device: "mobile",
          country: "usa", clicks: 9, impressions: 90, ctr: 0.1, position: 4.0 },
        { date: (today - 1.day).to_date, query: "tool vs rival", page: "https://example.com/compare", device: "mobile",
          country: "usa", clicks: 3, impressions: 40, ctr: 0.1, position: 6.0 }
      ])

      page = sole_item(evidence.entry_pages)

      expect(page.searches.map(&:query)).to eq([ "best tool", "tool vs rival" ])
    end

    it "reads one goal when it is asked to" do
      other = create(:dash_goal, event_name: "bought")
      visit = visit!("converter", at: today - 1.day)
      signup!(visit)

      expect(evidence(goal: other).converters).to eq(0)
      expect(evidence(goal: goal).converters).to eq(1)
    end

    it "reads through the dashboard's filters" do
      here = visit!("in-canada", at: today - 1.day, country: "CA")
      view!(here, "/pricing")
      signup!(here)
      there = visit!("in-us", at: today - 1.day, country: "US")
      view!(there, "/pricing")
      signup!(there)

      by_country = described_class.call(scope: scope(filters: dash_filters([ "country", "is", "CA" ])))
      by_page = described_class.call(scope: scope(filters: dash_filters([ "page", "is", "/pricing" ])))
      by_exit = described_class.call(scope: scope(filters: dash_filters([ "exit_page", "is", "/pricing" ])))

      expect(by_country.converters).to eq(1)
      expect(by_page.converters).to eq(2)
      expect(by_exit.converters).to eq(2)
    end

    it "leaves out excluded traffic unless it is shown" do
      create(:dash_exclusion, filters: [ { "dimension" => "country", "operator" => "is", "value" => "CA" } ])
      first = visit!("converter", at: today - 3.days, country: "CA", landing: "https://example.com/hidden")
      view!(first, "/hidden")
      visit = visit!("converter", at: today - 1.day, country: "US")
      signup!(visit)

      expect(evidence.converters).to eq(1)
      expect(evidence.entry_pages.map(&:path)).to eq([ "/" ])
      expect(described_class.call(scope: scope(include_internal: true)).entry_pages.map(&:path)).to eq(%w[/hidden /])

      converted_hidden = visit!("hidden-converter", at: today - 1.day, country: "CA")
      signup!(converted_hidden)

      expect(evidence.converters).to eq(1)
      expect(described_class.call(scope: scope(include_internal: true)).converters).to eq(2)
    end

    it "says the evidence is thin under twenty converters" do
      visit = visit!("converter", at: today - 1.day)
      signup!(visit)

      expect(evidence).to be_thin
    end
  end

  context "without a goal" do
    it "anchors on the first visit a user signed in on" do
      first = visit!("laptop", at: today - 3.days, landing: "https://example.com/docs")
      view!(first, "/docs")
      signed = visit!("laptop", at: today - 1.day, landing: "https://example.com/login", user_id: 7)
      view!(signed, "/login")
      visit!("laptop", at: today - 1.hour, user_id: 7)

      result = evidence

      expect(result.anchor).to eq(:sign_in)
      expect(result.converters).to eq(1)
      expect(result.entry_pages.map(&:path)).to eq(%w[/docs /login])
    end

    it "does not count a user who first signed in before the window" do
      visit!("laptop", at: today - 30.days, user_id: 7)
      visit!("laptop", at: today - 1.day, user_id: 7)

      expect(evidence.converters).to eq(0)
    end
  end
end
