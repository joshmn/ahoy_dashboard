# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard command palette", type: :request do
  let(:links) { document.css("a.ck-item") }

  before { sign_in(create(:user, :admin)) }

  it "keeps every command within the engine mount" do
    get("/telemetry/settings/goals")
    open_palette

    expect(links.map { |link| link["href"] }).to all(start_with("/telemetry"))
  end

  it "offers the chart grouping and comparison controls on the dashboard" do
    get("/telemetry")
    open_palette

    expect(document.css(".ck-g").map(&:text)).to include("Group by", "Compare to")
  end

  it "carries the current filters when changing the selected metric" do
    get("/telemetry", params: { period: "7d", filters: [{ dimension: "country", operator: "is", value: "CA" }] })
    open_palette
    metric = links.find { |link| link.text.strip == "Total pageviews" }
    params = link_query(metric["href"])

    expect(params.fetch("filters")).to include("dimension" => "country", "operator" => "is", "value" => "CA")
  end

  it "offers to stop comparison when a comparison is selected" do
    get("/telemetry", params: { comparison: "previous_period" })
    open_palette

    expect(links.map { |link| link.text.strip }).to include("Stop comparing")
  end

  context "with punctuation and HTML in a registered report name" do
    let(:title) { '"><img src=x onerror=alert(1)>' }

    before do
      AhoyDashboard::Report.register(key: "quoted", title: title, tabs: AhoyDashboard::Report.find("pages").tabs)
      get("/telemetry/settings/goals")
      open_palette
    end

    it "keeps the complete report name searchable as plain text" do
      command = links.find { |link| link.text.strip == "#{title} as CSV" }

      expect(command["data-term"]).to eq("export #{title} as csv")
    end

    it "does not interpret a report name as markup" do
      expect(document.css("img")).to be_empty
    end
  end
end
