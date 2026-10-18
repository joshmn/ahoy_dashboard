require "rails_helper"

RSpec.describe "Dashboard excluded traffic, everywhere it reaches" do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def exclude_datacenters!
    dash_exclusion("Datacenters", [ "asn", "contains", "DATACENTER" ])
  end

  def someone(token, at:, path: "/", **attributes)
    visit = dash_visit(started_at: at, visitor: token, **attributes)
    dash_page_view(visit, path: path, at: at)
    visit
  end

  it "leaves it out of the numbers in the traffic email" do
    window = AhoyDashboard::Reports::Digests::Window.new(period: :daily, starts_on: Date.new(2026, 8, 10),
                                                          ends_on: Date.new(2026, 8, 10))
    someone("bot", at: dash_time(2026, 8, 10, 9), path: "/bot", asn: "BIG DATACENTER LLC")
    someone("reader", at: dash_time(2026, 8, 10, 9), path: "/reader", asn: nil)
    someone("neighbor", at: dash_time(2026, 8, 10, 9), path: "/reader", asn: "HOME BROADBAND")

    expect(dash_value(AhoyDashboard::Reports::DigestQuery.call(window: window).stats, "visitors")).to eq(3)

    exclude_datacenters!
    result = AhoyDashboard::Reports::DigestQuery.call(window: window)

    expect(dash_value(result.stats, "visitors")).to eq(2)
    expect(result.list(:pages).rows.map(&:label)).to eq([ "/reader" ])
  end

  it "leaves it out of the traffic the alerts watch" do
    finish = now.beginning_of_hour
    someone("history", at: finish - 40.days)
    someone("bot", at: finish - 30.minutes, asn: "BIG DATACENTER LLC")
    someone("reader", at: finish - 30.minutes, asn: nil)

    expect(AhoyDashboard::Alerts::TrafficQuery.call(now: now).hour.visitors).to eq(2)

    exclude_datacenters!

    expect(AhoyDashboard::Alerts::TrafficQuery.call(now: now).hour.visitors).to eq(1)
  end

  describe "the assistant" do
    before do
      someone("bot", at: now - 1.day, asn: "BIG DATACENTER LLC")
      someone("reader", at: now - 1.day, asn: nil)
      exclude_datacenters!
    end

    def visitors(answer)
      answer[:figures]["visitors"][:value]
    end

    it "reads around it and says what hid it" do
      answer = AhoyDashboard::Assistant::Tools::TrafficSummary.new.execute(days: 7)

      expect(visitors(answer)).to eq(1)
      expect(answer[:hidden_traffic]).to eq("excluded")
      expect(answer[:hidden_by]).to include("Datacenters")
    end

    it "reads it when the screen the question came from was showing it" do
      slice = AhoyDashboard::Assistant::Slice.from_context("slice" => { "filters" => "none", "internal" => true })
      answer = AhoyDashboard::Assistant::Tools::TrafficSummary.new(slice: slice).execute(days: 7)

      expect(visitors(answer)).to eq(2)
      expect(answer[:hidden_traffic]).to eq("shown")
      expect(answer).not_to have_key(:hidden_by)
    end
  end
end
