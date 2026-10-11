require "rails_helper"
require "support/ahoy_dashboard/assistant"

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
    AhoyDashboard::Property.create!(key: "team_size", enabled: true)

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
