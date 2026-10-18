# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Facet search caching" do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:scope) { dash_scope(range: range) }
  let!(:visit) { dash_visit(started_at: range.begin, city: "faq city", browser: "faq browser") }
  let!(:first) { dash_page_view(visit, path: "/faq/first") }
  let!(:second) { dash_page_view(visit, path: "/faq/second") }

  around do |example|
    original_cache = Rails.cache
    Dir.mktmpdir("dashboard-facets") do |directory|
      Rails.cache = ActiveSupport::Cache::FileStore.new(directory)
      example.run
    end
  ensure
    travel_back
    Rails.cache = original_cache
  end

  def register(sql:, label: "Custom city")
    AhoyDashboard::Dimension.register(key: "cached_city", label: label,
      group: "Location", scope: :visit, sql: sql)
  end

  def search(source: scope)
    AhoyDashboard::FacetSearchQuery.call(scope: source, term: "faq")
  end

  def values(groups, key: "cached_city")
    groups.find { |group| group.key == key }.values.map(&:label)
  end

  it "round trips callable dimensions through a serializing cache store" do
    register(sql: -> { "ahoy_visits.city" })
    search

    expect(values(search)).to eq(["faq city"])
  end

  it "invalidates counts when the resolved callable SQL changes" do
    expression = "ahoy_visits.city"
    register(sql: -> { expression })
    search
    expression = "ahoy_visits.browser"

    expect(values(search)).to eq(["faq browser"])
  end

  it "invalidates counts when a static dimension is redefined" do
    register(sql: "ahoy_visits.city")
    search
    register(sql: "ahoy_visits.browser")

    expect(values(search)).to eq(["faq browser"])
  end

  it "hydrates labels from current dimension definitions on a cache hit" do
    register(sql: "ahoy_visits.city")
    search
    register(sql: "ahoy_visits.city", label: "Renamed city")

    expect(search.find { |group| group.key == "cached_city" }.label).to eq("Renamed city")
  end

  it "does not return a cached dimension after its registration is removed" do
    register(sql: "ahoy_visits.city")
    search
    AhoyDashboard::Dimension.registry.delete("cached_city")

    expect(search.map(&:key)).not_to include("cached_city")
  end

  it "isolates event scopes even when their visit population is identical" do
    search(source: scope.with(visit_events: scope.visit_events.where(id: first.id)))
    groups = search(source: scope.with(visit_events: scope.visit_events.where(id: second.id)))

    expect(values(groups, key: "page")).to eq(["/faq/second"])
  end

  it "preserves native fixed-width values across cache reads" do
    register(sql: "ahoy_visits.city::char(24) collate \"C\"")
    search

    expect(values(search)).to eq(["faq city".ljust(24)])
  end

  it "retains the two minute count freshness contract" do
    register(sql: "ahoy_visits.city")
    search
    visit.update!(city: "faq changed")

    expect(values(search)).to eq(["faq city"])
  end

  it "refreshes the numeric payload when its cache expires" do
    register(sql: "ahoy_visits.city")
    search
    visit.update!(city: "faq changed")
    travel(121.seconds)

    expect(values(search)).to eq(["faq changed"])
  end
end
