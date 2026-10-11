# frozen_string_literal: true

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require File.expand_path("dummy/config/environment", __dir__)
abort("The Rails environment is running in production mode!") if Rails.env.production?
Rails.application.reload_routes!
require "rspec/rails"
require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: true)

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => error
  abort(error.to_s.strip)
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true

  config.include(FactoryBot::Syntax::Methods)
  config.include(Devise::Test::IntegrationHelpers, type: :request)

  config.before(:each, type: :view) do |example|
    next unless example.metadata[:file_path].to_s.include?("/ahoy_dashboard/")

    view.extend(AhoyDashboard::DashboardHelper)
    view.extend(AhoyDashboard::ComponentsHelper)
    view.extend(AhoyDashboard::Engine.routes.url_helpers)
  end

  config.before { AhoyDashboard::Current.reset }
  config.before do
    AhoyDashboard::Preferences.write(:site, host: Rails.application.config.x.main_host)
  end

  config.filter_rails_from_backtrace!
end
