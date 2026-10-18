require "rails_helper"

RSpec.describe AhoyDashboard::FacetSearchQuery do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:scope) { dash_scope(range: range) }

  def clock(hour, minute = 0)
    dash_time(2026, 8, 10, hour, minute)
  end

  def search(term, **options)
    described_class.call(scope: scope, term: term, **options)
  end

  def keys(groups)
    groups.map(&:key)
  end

  def values_for(groups, key)
    groups.find { |group| group.key == key }&.values&.map(&:label)
  end

  before do
    first = dash_landing("/going-in/faq", at: clock(9), visitor: "a", country: "US", browser: "Chrome")
    dash_page_view(first, path: "/going-in/faq/visits", at: clock(9, 5))

    dash_landing("/going-in/faq", at: clock(10), visitor: "b", country: "CA", browser: "Firefox")

    dash_landing("/resources", at: clock(11), visitor: "c", country: "US", browser: "Safari")
  end

  it "finds a value without being told which dimension holds it" do
    expect(values_for(search("faq"), "page")).to include("/going-in/faq", "/going-in/faq/visits")
  end

  it "answers across dimensions at once" do
    expect(keys(search("faq"))).to include("page", "entry_page", "exit_page")
  end

  it "says nothing at all under the minimum term" do
    expect(search("f")).to eq([])
    expect(search("")).to eq([])
    expect(search(" ")).to eq([])
  end

  it "counts visitors rather than rows" do
    group = search("faq").find { |candidate| candidate.key == "page" }
    faq = group.values.find { |value| value.label == "/going-in/faq" }

    expect(faq.visitors).to eq(2)
  end

  it "leaves out a dimension that matches nothing" do
    expect(keys(search("faq"))).not_to include("browser", "country")
  end

  it "caps the values per dimension and says there are more" do
    group = search("faq", limit: 1).find { |candidate| candidate.key == "page" }

    expect(group.values.size).to eq(1)
    expect(group).to be_more
  end

  it "does not say there are more when the cap was not reached" do
    group = search("resources").find { |candidate| candidate.key == "page" }

    expect(group).not_to be_more
  end

  it "leaves the goal and crawler dimensions out" do
    create(:dash_goal, :pageview, path_pattern: "/going-in/*", display_name: "faq reader")

    expect(keys(search("faq"))).not_to include("goal", "crawler")
  end

  it "treats a percent sign in the term as a character rather than a wildcard" do
    expect(search("%%")).to eq([])
  end

  it "does not raise on a term full of sql metacharacters" do
    expect(search("'; drop table ahoy_events --")).to eq([])
    expect(Ahoy::Event.count).to eq(4)
  end

  it "reads only the sessions the filters left" do
    scope = dash_scope(range: range, filters: dash_filters([ "country", "is", "CA" ]))
    groups = described_class.call(scope: scope, term: "faq")

    expect(values_for(groups, "page")).to eq([ "/going-in/faq" ])
  end

  it "keeps custom dimensions, event grains and escaped property keys in the same search" do
    AhoyDashboard::Dimension.register(key: "custom_city", label: "Custom city", group: "Location", scope: :visit,
                                     sql: "ahoy_visits.city")
    create(:dash_property, key: "question?'s", enabled: true)
    visit = dash_landing("/faq-page", at: clock(12), visitor: "custom", city: "faq city")
    dash_goal(visit, "custom", at: clock(12, 1), path: "/faq-goal", "question?'s" => "faq answer")
    dash_goal(visit, "custom", at: clock(12, 2), "question?'s" => "faq answer")

    groups = search("faq")

    expect(values_for(groups, "custom_city")).to eq([ "faq city" ])
    expect(values_for(groups, "page")).to include("/faq-page")
    expect(values_for(groups, "page")).not_to include("/faq-goal")
    property = groups.find { |group| group.key == "prop:question?'s" }
    expect(property.values.map { |value| [ value.label, value.visitors ] }).to eq([ [ "faq answer", 1 ] ])
  end

  it "keeps visitor ranking, tie ordering and the more flag independent for every dimension" do
    %w[zeta alpha beta].each_with_index do |label, index|
      visit = dash_visit(started_at: clock(12, index), visitor: "rank-#{index}", city: "faq #{label}")
      2.times { dash_page_view(visit, path: "/faq/#{label}", at: clock(12, index)) }
    end
    dash_landing("/faq/zeta", at: clock(13), visitor: "another", city: "faq zeta")

    group = search("faq ", limit: 2).find { |candidate| candidate.key == "city" }

    expect(group.values.map { |value| [ value.label, value.visitors ] }).to eq([ [ "faq zeta", 2 ], [ "faq alpha", 1 ] ])
    expect(group).to be_more
  end

  it "preserves each custom dimension's SQL type and collation when combining results" do
    %w[C POSIX].each_with_index do |collation, index|
      AhoyDashboard::Dimension.register(key: "padded_city_#{index}", label: "Padded city #{index}",
                                       group: "Location", scope: :visit,
                                       sql: %(ahoy_visits.city::char(24) collate "#{collation}"))
    end
    groups = search("Chicago")

    2.times do |index|
      found = groups.find { |group| group.key == "padded_city_#{index}" }
      expect(sole_item(found.values).label).to eq("Chicago".ljust(24))
    end
  end

  it "does all cross-dimension analytics in one statement" do
    built_scope = scope
    statements = []
    statements = captured_sql(/(?:from|join) "?ahoy_(?:visits|events)/i, cached: true) do
      described_class.call(scope: built_scope, term: "faq")
    end

    expect(statements.size).to eq(1)
  end
end
