# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard funnel pages", type: :request do
  let(:document) { Nokogiri::HTML5(response.body) }
  let(:goals) { create_list(:dash_goal, 2) }
  let!(:funnels) { Array.new(6) { |index| create(:dash_funnel, position: index + 1, goals: goals) } }
  let(:filters) { [{ dimension: "country", operator: "is", value: "CA" }] }

  before { sign_in(create(:user, :admin)) }

  def card_ids
    document.css("tm-frame[id^='report_funnel_']").map { |frame| frame["id"] }
  end

  it "limits the dashboard preview to the first four configured funnels" do
    get("/telemetry")

    expect(card_ids).to eq(funnels.first(4).map { |funnel| "report_funnel_#{funnel.id}" })
  end

  it "makes the remaining configured funnels explicit" do
    get("/telemetry")

    expect(document.at_css("[aria-label='More funnels']").text.squish).to eq("Showing 4 of 6 funnels View all funnels")
  end

  it "preserves filters in the link to all funnels" do
    get("/telemetry", params: { period: "7d", filters: filters })
    link = document.at_css("[aria-label='More funnels'] a")
    get(link["href"])

    expect(request.query_parameters).to include("period" => "7d", "filters" => [filters.first.stringify_keys])
  end

  it "renders a bounded first page with completed frames" do
    get("/telemetry/funnels")

    expect(document.css("tm-frame[id^='report_funnel_'][complete]").length).to eq(4)
  end

  it "reaches the remaining funnels on the next page" do
    get("/telemetry/funnels", params: { page: 2 })

    expect(card_ids).to eq(funnels.last(2).map { |funnel| "report_funnel_#{funnel.id}" })
  end

  it "retains the selected filters across pagination" do
    get("/telemetry/funnels", params: { period: "7d", filters: filters })
    next_link = document.css("nav[aria-label='Pages of funnels'] a").find { |link| link.text.strip == "Next" }
    get(next_link["href"])

    expect(request.query_parameters).to include("page" => "2", "period" => "7d", "filters" => [filters.first.stringify_keys])
  end

  it "keeps existing detail links available on the second page" do
    get("/telemetry/funnels", params: { page: 2 })

    expect(document.css("a[data-dash--modal-key-param]").map { |link| URI.parse(link["href"]).path })
      .to eq(funnels.last(2).map { |funnel| "/telemetry/funnels/#{funnel.id}" })
  end

  context "without configured funnels" do
    let!(:funnels) { [] }

    it "offers to create the first funnel" do
      get("/telemetry/funnels")

      expect(document.at_css(".empty-actions a")["href"]).to eq("/telemetry/settings/funnels/new")
    end
  end
end
