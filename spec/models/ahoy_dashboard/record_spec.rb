require "rails_helper"

RSpec.describe AhoyDashboard::Record do
  it "keeps each model on its prefixed table" do
    {
      AhoyDashboard::GoogleAccount => "ahoy_dashboard_google_accounts",
      AhoyDashboard::Property => "ahoy_dashboard_properties",
      AhoyDashboard::SearchConsoleKeyword => "ahoy_dashboard_search_console_keywords",
      AhoyDashboard::SearchConsoleRow => "ahoy_dashboard_search_console_rows",
      AhoyDashboard::SearchConsoleTotal => "ahoy_dashboard_search_console_totals"
    }.each do |model, table|
      expect(model.table_name).to eq(table), "#{model.name} sits on #{model.table_name}"
    end
  end
end
