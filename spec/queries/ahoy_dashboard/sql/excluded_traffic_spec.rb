require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::Sql::ExcludedTraffic do
  def exclude(name, *entries)
    AhoyDashboard::Exclusion.create!(name: name, filters: entries.map { |dimension, operator, value, group|
      { "dimension" => dimension, "operator" => operator, "value" => value, "group" => group }.compact
    })
  end

  let(:start) { dash_time(2026, 8, 10) }

  def visit(token, **attributes)
    dash_visit(started_at: start + 1.hour, visitor: token, **attributes).tap do |created|
      dash_page_view(created, path: attributes.delete(:path) || "/", at: created.started_at)
    end
  end

  before { AhoyDashboard::Preferences.write(:site, internal_ips: []) }

  it "does nothing when nothing is excluded" do
    visit("one")

    expect(described_class).not_to be_enabled
    expect(described_class.condition).to be_nil
    expect(described_class.exclude(Ahoy::Visit.all).count).to eq(1)
    expect(described_class.only(Ahoy::Visit.all)).to be_empty
  end

  it "hides a visit a visit rule matches and keeps one with nothing recorded" do
    exclude("Data centers", [ "asn", "contains", "amazon" ])
    visit("aws", asn: "AMAZON-02")
    visit("unknown", asn: nil)

    expect(described_class).to be_enabled
    expect(described_class.exclude(Ahoy::Visit.all).pluck(:visitor_token)).to eq([ "unknown" ])
    expect(described_class.only(Ahoy::Visit.all).pluck(:visitor_token)).to eq([ "aws" ])
  end

  it "hides a visit with any event an event rule matches, crawler events included" do
    exclude("Scanners", [ "page", "contains", "wp-login" ])
    scanner = visit("scanner")
    dash_page_view(scanner, path: "/wp-login.php", crawler: "Bad Bot")
    visit("reader")

    expect(described_class.exclude(Ahoy::Visit.all).pluck(:visitor_token)).to eq([ "reader" ])
  end

  it "hides a visit that matches every filter in any one set of an exclusion" do
    AhoyDashboard::Exclusion.create!(name: "Sets", filters: [
      { "dimension" => "country", "operator" => "is", "value" => "US", "block" => 0 },
      { "dimension" => "browser", "operator" => "is", "value" => "Chrome", "block" => 0 },
      { "dimension" => "country", "operator" => "is", "value" => "DE", "block" => 1 }
    ])
    visit("us_chrome", country: "US", browser: "Chrome")
    visit("us_firefox", country: "US", browser: "Firefox")
    visit("de_firefox", country: "DE", browser: "Firefox")

    expect(described_class.exclude(Ahoy::Visit.all).pluck(:visitor_token)).to eq([ "us_firefox" ])
  end

  it "reads the groups inside one exclusion the same way the filter bar does" do
    exclude("Chrome in the US or CA", [ "country", "is", "US", 0 ], [ "country", "is", "CA", 0 ], [ "browser", "is", "Chrome" ])
    visit("us_chrome", country: "US", browser: "Chrome")
    visit("ca_chrome", country: "CA", browser: "Chrome")
    visit("us_firefox", country: "US", browser: "Firefox")
    visit("de_chrome", country: "DE", browser: "Chrome")

    expect(described_class.exclude(Ahoy::Visit.all).pluck(:visitor_token).sort).to eq(%w[de_chrome us_firefox])
  end

  it "hides a visit that matches any one of several exclusions" do
    exclude("One", [ "country", "is", "US" ])
    exclude("Two", [ "browser", "is", "Firefox" ])
    visit("us", country: "US")
    visit("firefox", country: "CA", browser: "Firefox")
    visit("left", country: "CA")

    expect(described_class.exclude(Ahoy::Visit.all).pluck(:visitor_token)).to eq([ "left" ])
  end

  it "works on events joined to their visits" do
    exclude("Data centers", [ "asn", "contains", "AMAZON" ])
    visit("aws", asn: "AMAZON-02")
    visit("person")

    events = described_class.exclude(Ahoy::Event.joins(:visit))

    expect(events.map { |event| event.visit.visitor_token }).to eq([ "person" ])
  end

  it "includes the internal addresses" do
    AhoyDashboard::Preferences.write(:site, internal_ips: [ "10.0.0.0/8" ])
    visit("office", ip: "10.1.2.3")
    visit("outside", ip: "203.0.113.9")

    expect(described_class).to be_enabled
    expect(described_class.exclude(Ahoy::Visit.all).pluck(:visitor_token)).to eq([ "outside" ])
  end

  it "reads an exclusion saved after the first question in the same request" do
    visit("aws", asn: "AMAZON-02")
    expect(described_class.exclude(Ahoy::Visit.all).count).to eq(1)

    exclude("Data centers", [ "asn", "contains", "AMAZON" ])

    expect(described_class.exclude(Ahoy::Visit.all).count).to eq(0)
  end

  it "floors the event lookup when given a start" do
    exclude("Scanners", [ "page", "contains", "wp-login" ])

    expect(described_class.condition(floor: start)).to include("ahoy_events.time >=")
    expect(described_class.condition).not_to include("ahoy_events.time >=")
  end
end
