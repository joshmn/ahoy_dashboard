require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::Filter do
  let(:dimension) { AhoyDashboard::Dimension.find("country") }

  it "preserves exact and negated channel filtering including nulls and medium precedence" do
    [ nil, "", "google.com", "WWW.CHATGPT.COM", "claude.ai", "example.com" ].product([ nil, "cpc", "email" ]).each do |domain, medium|
      create(:ahoy_visit, referring_domain: domain, utm_medium: medium)
    end
    channel = AhoyDashboard::Dimension.find("channel")

    AhoyDashboard::Sql::CHANNELS.each do |value|
      [ [ "is", "=" ], [ "is_not", "is distinct from" ] ].each do |operator, sql_operator|
        filter = described_class.new(dimension: channel, operator: operator, value: value)
        expected = Ahoy::Visit.where("#{channel.sql} #{sql_operator} ?", value).order(:id).ids

        expect(filter.apply(Ahoy::Visit.all).order(:id).ids).to eq(expected)
      end
    end
  end

  def matches(operator, value)
    filter = described_class.new(dimension: dimension, operator: operator, value: value)

    filter.apply(Ahoy::Visit.all, sql: dimension.sql).pluck(:visit_token).sort
  end

  describe "the operator set" do
    it "reads the way a chip does" do
      expect(described_class::OPERATORS).to eq(
        "is" => "is",
        "is_not" => "is not",
        "contains" => "contains",
        "not_contains" => "does not contain"
      )
    end

    it "falls back to is for an operator nobody defined" do
      filter = described_class.new(dimension: dimension, operator: "sounds_like", value: "US")

      expect(filter.operator).to eq("is")
    end
  end

  it "labels itself the way the chip reads" do
    filter = described_class.new(dimension: AhoyDashboard::Dimension.find("page"), operator: "is", value: "/pricing")

    expect(filter.label).to eq("Page is /pricing")
  end

  it "round trips through to_param" do
    filter = described_class.new(dimension: dimension, operator: "contains", value: "US")

    expect(filter.to_param).to eq(
      "dimension" => "country", "operator" => "contains", "value" => "US"
    )
  end

  describe "#apply" do
    before do
      create(:ahoy_visit, visit_token: "us", country: "US")
      create(:ahoy_visit, visit_token: "ca", country: "CA")
      create(:ahoy_visit, visit_token: "null", country: nil)
      create(:ahoy_visit, visit_token: "empty", country: "")
    end

    it "matches is" do
      expect(matches("is", "US")).to eq([ "us" ])
    end

    # A NULL is genuinely not the value, so it belongs in an is-not set.
    # Written as `!=` postgres drops every one of those rows on the floor.
    it "keeps unset rows in an is not" do
      expect(matches("is_not", "US")).to eq(%w[ca empty null])
    end

    it "matches contains without minding case" do
      expect(matches("contains", "u")).to eq([ "us" ])
    end

    it "keeps unset rows in a does not contain" do
      expect(matches("not_contains", "u")).to eq(%w[ca empty null])
    end

    it "reads the unknown label as both null and empty" do
      expect(matches("is", dimension.unknown_label)).to eq(%w[empty null])
    end

    # The value is a raw query string parameter and has to arrive as a bound
    # parameter, never as text pasted into the statement.
    it "binds the value instead of interpolating it" do
      page = AhoyDashboard::Dimension.find("page")
      filter = described_class.new(
        dimension: page, operator: "is", value: "x'); drop table ahoy_events; --"
      )

      expect(filter.apply(Ahoy::Event.all, sql: page.sql).count).to eq(0)
      expect(ActiveRecord::Base.connection.table_exists?("ahoy_events")).to be(true)
    end

    it "binds a wildcard value in a contains without letting it escape" do
      filter = described_class.new(dimension: dimension, operator: "contains", value: "'; drop table ahoy_visits; --")

      expect(filter.apply(Ahoy::Visit.all, sql: dimension.sql).count).to eq(0)
      expect(ActiveRecord::Base.connection.table_exists?("ahoy_visits")).to be(true)
    end
  end

  # A filter value is somebody's own text, so % and _ in it are characters rather
  # than LIKE wildcards. FilterOptionsQuery escapes them for the typeahead, and
  # the two disagreeing meant picking a value out of the dropdown matched rows
  # the dropdown had never offered.
  describe "a value that reads as a wildcard" do
    before do
      create(:ahoy_visit, visit_token: "under", country: "a_b")
      create(:ahoy_visit, visit_token: "any", country: "axb")
      create(:ahoy_visit, visit_token: "percent", country: "50%")
      create(:ahoy_visit, visit_token: "plain", country: "5012")
    end

    it "matches an underscore literally in a contains" do
      expect(matches("contains", "a_b")).to eq([ "under" ])
    end

    it "matches a percent literally rather than matching everything" do
      expect(matches("contains", "50%")).to eq([ "percent" ])
    end

    it "reads them the same way in a does not contain" do
      expect(matches("not_contains", "a_b")).to eq(%w[any percent plain])
    end

    it "still matches a value that has neither in it" do
      expect(matches("contains", "axb")).to eq([ "any" ])
    end
  end

  describe "text with a colon in it" do
    it "filters on a goal whose event name carries a colon" do
      create(:dash_goal, event_name: "signup:trial", display_name: "signup:trial")
      visit = dash_visit(started_at: dash_time(2026, 8, 10, 9))
      dash_goal(visit, "signup:trial")
      filter = dash_filter("goal", "is", "signup:trial")

      expect { AhoyDashboard.event.joins(:visit).merge(filter.apply(AhoyDashboard.event.all)).to_a }.not_to raise_error
      expect(filter.apply(AhoyDashboard.event.all).count).to eq(1)
    end

    it "filters on a property whose name carries a colon" do
      visit = dash_visit(started_at: dash_time(2026, 8, 10, 9))
      dash_goal(visit, "clicked", "utm:source" => "news:letter")
      filter = AhoyDashboard::Filter.new(dimension: AhoyDashboard::Dimension.property("utm:source"), value: "news:letter")

      expect(filter.apply(AhoyDashboard.event.all).count).to eq(1)
    end
  end

  describe "#candidate_predicate" do
    it "only counts a page view as seeing a page" do
      visit = dash_visit(started_at: dash_time(2026, 8, 10, 9))
      dash_goal(visit, "clicked", path: "/pricing")
      filter = dash_filter("page", "is", "/pricing")

      expect(AhoyDashboard.event.where(Arel.sql(filter.predicate)).count).to eq(1)
      expect(AhoyDashboard.event.where(Arel.sql(filter.candidate_predicate)).count).to eq(0)
    end

    it "is the plain predicate for anything else" do
      filter = dash_filter("country", "is", "US")

      expect(filter.candidate_predicate).to eq(filter.predicate)
    end
  end
end
