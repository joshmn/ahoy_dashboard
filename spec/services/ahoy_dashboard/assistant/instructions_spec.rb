require "rails_helper"

RSpec.describe AhoyDashboard::Assistant::Instructions do
  it "tells the model the three things about this data that are easy to get wrong" do
    expect(described_class.fixed).to include("impression weighted daily average")
    expect(described_class.fixed).to include("reads the entire history")
    expect(described_class.fixed).to include("Crawlers are hidden from the dashboard by default")
  end

  it "tells the model only about dimensions this host actually registered" do
    allow(AhoyDashboard::Dimension).to receive(:registry).and_return({})

    prompt = described_class.prompt

    expect(prompt).not_to include("IP address", "network", "mirror")
  end

  it "names the dimensions and custom properties the host added" do
    registered = AhoyDashboard::Dimension.new(key: "plan", label: "Billing plan", group: "Behaviour",
                                              scope: :visit, sql: "null::text")
    allow(AhoyDashboard::Dimension).to receive(:registry).and_return({ "plan" => registered })
    create(:dash_property, key: "team_size", enabled: true)

    prompt = described_class.prompt

    expect(prompt).to include("Billing plan", "prop:team_size")
  end

  it "keeps what changes day to day out of the part of the prompt that is cached" do
    registered = AhoyDashboard::Dimension.new(key: "plan", label: "Billing plan", group: "Behaviour",
                                              scope: :visit, sql: "null::text")
    allow(AhoyDashboard::Dimension).to receive(:registry).and_return({ "plan" => registered })

    expect(described_class.fixed).not_to include("Today is", "Billing plan", "They asked this from")
    expect(described_class.notes(page: "dashboard")).to include("Today is", "Billing plan", "They asked this from")
  end

  describe "the dates it is given" do
    before { AhoyDashboard::Setting.write(AhoyDashboard::Setting::TIME_ZONE, "America/Los_Angeles") }

    it "says what day it is where the dashboard is, not where the server is" do
      travel_to(Time.utc(2026, 3, 16, 4)) do
        expect(described_class.notes).to include(
          "Today is Sunday, March 15, 2026.",
          "Last week is from 2026-03-02 to 2026-03-08."
        )
      end
    end

    it "starts last week on a Monday whatever the host's week starts on" do
      previous = Date.beginning_of_week
      Date.beginning_of_week = :sunday

      travel_to(Time.utc(2026, 3, 18, 18)) do
        expect(described_class.notes).to include("Last week is from 2026-03-09 to 2026-03-15.")
      end
    ensure
      Date.beginning_of_week = previous
    end
  end

  it "says nothing about a dimension kept from the assistant on the settings screen" do
    registered = AhoyDashboard::Dimension.new(key: "ip", label: "IP address", group: "Location",
                                              scope: :visit, sql: "null::text")
    allow(AhoyDashboard::Dimension).to receive(:registry).and_return({ "ip" => registered })
    AhoyDashboard::Setting.write(AhoyDashboard::Assistant::WITHHELD_KEY, %w[ip])

    expect(described_class.prompt).not_to include("IP address")
    expect(AhoyDashboard::Assistant).to be_withheld("ip")
  end

  it "tells the model what drawn false and not_drawn mean" do
    expect(described_class.fixed).to include("When drawn is false", "not_drawn")
  end

  it "tells the model the tools read the conversation's filters and how to change them" do
    expect(described_class.fixed).to include("an empty list for the whole site")
    expect(described_class.fixed).to include("filters_not_applied")
    expect(described_class.prompt(page: "dashboard")).to include("do not pass them again")
  end
end
