# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard SEO overview", type: :request do
  let!(:check) { create(:dash_serp_check) }

  before { sign_in(create(:user, :admin)) }

  def rank_title
    Nokogiri::HTML5(response.body).css(".card-title").find { |node| node.text.include?("Rank tracking") }.text.squish
  end

  it "renders populated rank tracking with the sample-data badge for the fake provider" do
    get "/telemetry/seo", params: { site: check.site_id }

    expect([response.status, rank_title]).to eq([200, "Rank tracking Sample data"])
  end

  it "renders populated rank tracking without the sample-data badge for a real provider" do
    create(:dash_serp_provider, :serpapi, :active)

    get "/telemetry/seo", params: { site: check.site_id }

    expect([response.status, rank_title]).to eq([200, "Rank tracking"])
  end
end
