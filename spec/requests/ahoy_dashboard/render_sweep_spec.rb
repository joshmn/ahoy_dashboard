require "rails_helper"

RSpec.describe "Dashboard render sweep", type: :request do
  not_pages = {
    "ahoy_dashboard/dashboards/summaries" => "a frame inside the dashboard",
    "ahoy_dashboard/search_console" => "a frame inside the dashboard",
    "ahoy_dashboard/goal_conversions" => "a frame inside the dashboard",
    "ahoy_dashboard/pinned_questions" => "a frame inside the dashboard",
    "ahoy_dashboard/facet_searches" => "a frame inside the filter popover",
    "ahoy_dashboard/pickers" => "a frame inside the settings forms",
    "ahoy_dashboard/settings/places" => "a frame inside the keyword forms",
    "ahoy_dashboard/filter_options" => "answers json",
    "ahoy_dashboard/filter_dialogs" => "redirects to the filter values page",
    "ahoy_dashboard/asks" => "redirects back to the screen it opened over",
    "ahoy_dashboard/visitors/lookups" => "redirects to the visitor, visit or user it finds",
    "ahoy_dashboard/search_console_keywords" => "redirects without a keyword",
    "ahoy_dashboard/rank_keywords" => "redirects without a keyword",
    "ahoy_dashboard/settings/google_authorizations" => "redirects to Google",
    "ahoy_dashboard/settings/google_callbacks" => "redirects without a Google state",
    "ahoy_dashboard/settings/search_console_properties" => "redirects without a Google connection"
  }.freeze

  filtered = %w[
    /telemetry?filters[][dimension]=country&filters[][operator]=is&filters[][value]=US&filters[][group]=0&filters[][dimension]=country&filters[][operator]=is&filters[][value]=CA&filters[][group]=0&filters[][dimension]=page&filters[][operator]=is&filters[][value]=/
    /telemetry?filters[][dimension]=country&filters[][operator]=is_not&filters[][value]=US&filters[][group]=0&filters[][dimension]=country&filters[][operator]=is_not&filters[][value]=CA&filters[][group]=0
    /telemetry/explore?dimension=browser&filters[][dimension]=country&filters[][operator]=is&filters[][value]=US&filters[][group]=0&filters[][dimension]=os&filters[][operator]=is&filters[][value]=Mac&filters[][group]=0
  ].freeze

  pages = AhoyDashboardRequestRoutes.pages.reject { |route| not_pages.key?(route.controller) }.map(&:path) + filtered

  before { sign_in create(:user, :admin) }

  it "only sets aside controllers that have a page route" do
    expect(not_pages.keys - AhoyDashboardRequestRoutes.pages.map(&:controller)).to be_empty
  end

  pages.each do |path|
    it "renders #{path} with one heading, working references, named buttons and labelled fields" do
      get path

      expect_sound_markup
    end
  end
end
