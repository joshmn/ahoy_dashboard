require "rails_helper"

RSpec.describe "Dashboard render sweep", type: :request do
  RENDERED_PAGES = %w[
    /telemetry
    /telemetry/realtime
    /telemetry/explore
    /telemetry/filter_values
    /telemetry/journey
    /telemetry/chats
    /telemetry/rankings
    /telemetry/search_console_report
    /telemetry/seo
    /telemetry/seo/visibility
    /telemetry/seo/position_change
    /telemetry/seo/keyword_gap
    /telemetry/seo/volatility
    /telemetry/seo/serp_feature
    /telemetry/seo/opportunity
    /telemetry/seo/cannibalization
    /telemetry/seo/brand_split
    /telemetry/seo/conversion
    /telemetry/seo/keyword_research
    /telemetry/seo/backlink
    /telemetry/seo/alert
    /telemetry/settings/goals
    /telemetry/settings/goals/new
    /telemetry/settings/properties
    /telemetry/settings/funnels
    /telemetry/settings/funnels/new
    /telemetry/settings/segments
    /telemetry/settings/segments/new
    /telemetry/settings/exclusions
    /telemetry/settings/exclusions/new
    /telemetry/settings/exclusions/preview
    /telemetry/settings/saved_queries
    /telemetry/settings/page_groups
    /telemetry/settings/page_groups/new
    /telemetry/settings/annotations
    /telemetry/settings/annotations/new
    /telemetry/settings/google_connection
    /telemetry/settings/search_console_rows
    /telemetry/settings/serp_sites
    /telemetry/settings/serp_sites/new
    /telemetry/settings/serp_keywords
    /telemetry/settings/serp_keywords/new
    /telemetry/settings/serp_keyword_import/new
    /telemetry/settings/serp_providers
    /telemetry/settings/assistant_providers
    /telemetry/settings/alert_rules
    /telemetry/settings/job_runs
    /telemetry/styleguide
    /telemetry?filters[][dimension]=country&filters[][operator]=is&filters[][value]=US&filters[][group]=0&filters[][dimension]=country&filters[][operator]=is&filters[][value]=CA&filters[][group]=0&filters[][dimension]=page&filters[][operator]=is&filters[][value]=/
    /telemetry?filters[][dimension]=country&filters[][operator]=is_not&filters[][value]=US&filters[][group]=0&filters[][dimension]=country&filters[][operator]=is_not&filters[][value]=CA&filters[][group]=0
    /telemetry/explore?dimension=browser&filters[][dimension]=country&filters[][operator]=is&filters[][value]=US&filters[][group]=0&filters[][dimension]=os&filters[][operator]=is&filters[][value]=Mac&filters[][group]=0
  ].freeze

  before { sign_in create(:user, :admin) }

  RENDERED_PAGES.each do |path|
    it "renders #{path} with one heading, working references, named buttons and labelled fields" do
      get path

      expect(response).to have_http_status(:ok)

      document = Nokogiri::HTML5(response.body)
      ids = document.css("[id]").map { |node| node["id"] }

      expect(document.css("h1").size).to eq(1)
      expect(ids.group_by { |item| item }.transform_values(&:size).select { |_, count| count > 1 }.keys).to be_empty

      references = document.css("[aria-labelledby], [aria-describedby]").flat_map do |node|
        [ node["aria-labelledby"], node["aria-describedby"] ].compact.flat_map(&:split)
      end
      expect(references - ids).to be_empty

      expect(document.css("label[for]").map { |label| label["for"] } - ids).to be_empty

      unnamed = document.css("button:not([aria-hidden=true])").reject do |button|
        button.text.strip.present? || button["aria-label"].present? || button["aria-labelledby"].present? || button["title"].present?
      end
      expect(unnamed.map(&:to_html)).to be_empty
    end
  end
end
