require "rails_helper"

RSpec.describe "Dashboard with features not installed", type: :request do
  seo = %i[search_console serp keywords backlinks alerts ai_visibility].freeze

  owners = {
    "ahoy_dashboard/asks" => %i[assistant],
    "ahoy_dashboard/chats" => %i[assistant],
    "ahoy_dashboard/rankings" => %i[serp],
    "ahoy_dashboard/rank_keywords" => %i[serp],
    "ahoy_dashboard/search_console" => %i[search_console],
    "ahoy_dashboard/search_console_reports" => %i[search_console],
    "ahoy_dashboard/search_console_keywords" => %i[search_console],
    "ahoy_dashboard/seo" => seo,
    "ahoy_dashboard/seo/opportunities" => %i[search_console],
    "ahoy_dashboard/seo/cannibalizations" => %i[search_console],
    "ahoy_dashboard/seo/brand_splits" => %i[search_console],
    "ahoy_dashboard/seo/conversions" => %i[search_console],
    "ahoy_dashboard/seo/visibilities" => %i[serp],
    "ahoy_dashboard/seo/position_changes" => %i[serp],
    "ahoy_dashboard/seo/landing_pages" => %i[serp],
    "ahoy_dashboard/seo/keyword_gaps" => %i[serp],
    "ahoy_dashboard/seo/volatilities" => %i[serp],
    "ahoy_dashboard/seo/serp_features" => %i[serp],
    "ahoy_dashboard/seo/keyword_researches" => %i[keywords],
    "ahoy_dashboard/seo/backlinks" => %i[backlinks],
    "ahoy_dashboard/seo/alerts" => %i[alerts],
    "ahoy_dashboard/seo/ai_visibilities" => %i[ai_visibility],
    "ahoy_dashboard/settings/alert_rules" => %i[alerts],
    "ahoy_dashboard/settings/assistant_dimensions" => %i[assistant],
    "ahoy_dashboard/settings/assistant_providers" => %i[assistant],
    "ahoy_dashboard/settings/ai_visibilities" => %i[ai_visibility],
    "ahoy_dashboard/settings/google_authorizations" => %i[search_console],
    "ahoy_dashboard/settings/google_connections" => %i[search_console],
    "ahoy_dashboard/settings/search_console_properties" => %i[search_console],
    "ahoy_dashboard/settings/search_console_rows" => %i[search_console],
    "ahoy_dashboard/settings/places" => %i[places],
    "ahoy_dashboard/settings/serp_keywords" => %i[serp],
    "ahoy_dashboard/settings/serp_keyword_imports" => %i[serp],
    "ahoy_dashboard/settings/serp_sites" => %i[serp],
    "ahoy_dashboard/settings/serp_providers" => %i[serp keywords backlinks]
  }.freeze

  skipped = %w[
    ahoy_dashboard/assets ahoy_dashboard/exports ahoy_dashboard/favicons ahoy_dashboard/reports
    ahoy_dashboard/settings/google_callbacks
  ].freeze

  pages = AhoyDashboardRequestRoutes.pages.reject { |route| skipped.include?(route.controller) }.freeze

  scenarios = { "core only" => AhoyDashboard::Installation.names }
    .merge(AhoyDashboard::Installation.names.map { |name| [ "without #{name}", [ name ] ] }.to_h)
    .freeze

  before { sign_in create(:user, :admin) }

  it "names only controllers that draw a page" do
    expect(owners.keys - pages.map(&:controller)).to be_empty
  end

  scenarios.each do |scenario, missing|
    it "renders every page #{scenario}, explaining how to install what is missing" do
      uninstall_ahoy_dashboard(*missing)

      failures = pages.map do |page|
        needs = owners[page.controller]
        gone = needs.present? && (needs - missing).empty?

        begin
          AhoyDashboard::Record.transaction(requires_new: true) do
            get page.path
            raise ActiveRecord::Rollback
          end
        rescue StandardError => error
          next "#{page.path} raised #{error.class}: #{error.message.lines.first&.strip}"
        end

        status = response.status
        commands = gone ? needs.map { |name| "bin/rails generate ahoy_dashboard:install --only #{name}" } : []
        unexplained = commands.reject { |command| response.body.include?(command) }
        if gone && (status != 200 || unexplained.any?)
          "#{page.path} answered #{status} without saying how to install it: #{unexplained.join(', ')}"
        elsif !gone && !status.in?([ 200, 302, 303 ])
          "#{page.path} answered #{status}"
        end
      end.compact

      expect(failures).to be_empty, failures.join("\n")
    end
  end
end
