require "rails_helper"

RSpec.describe "Complete dashboard rendering", type: :request do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  before do
    sign_in create(:user, :admin)
    dash_landing("/rendered-initially", at: now - 1.hour, visitor: "reader", country: "US", browser: "Firefox")
  end

  it "completes every source frame in the initial response" do
    get "/telemetry?loading=complete"

    expect(document.css("tm-frame[src]").all? { |frame| frame.key?("complete") }).to be(true)
  end

  it "does not label live analytical results as a snapshot" do
    get "/telemetry?loading=complete"

    expect(document.at_css("#dash-snapshot-freshness")).to be_nil
  end

  it "includes the ranked report rows without waiting for a frame request" do
    get "/telemetry?loading=complete"

    expect(document.at_css("tm-frame#report_pages .p-list").text).to include("/rendered-initially")
  end

  it "includes the page journey in the initial response" do
    get "/telemetry?loading=complete"

    expect(document.at_css("tm-frame#dash_journey .j-cols").text).to include("/rendered-initially")
  end

  it "keeps detail dialogs empty until they are opened" do
    get "/telemetry?loading=complete"

    expect(document.at_css("tm-frame#report_details_pages").text).to include("Loading the full list")
  end

  it "renders an uninstalled Search Console card without reading its optional tables" do
    table = AhoyDashboard::GoogleAccount.table_name
    connection = ActiveRecord::Base.connection
    connection.execute("ALTER TABLE #{connection.quote_table_name(table)} RENAME TO dashboard_missing_google_accounts")
    AhoyDashboard::Record.connection.schema_cache.clear!

    get "/telemetry?loading=complete"

    expect(document.at_css("tm-frame#report_search_console").text).to include("Not installed yet")
  ensure
    connection.schema_cache.clear! if connection
  end
end
