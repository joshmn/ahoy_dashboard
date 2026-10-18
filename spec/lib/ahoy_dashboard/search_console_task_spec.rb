require "rails_helper"

RSpec.describe "ahoy_dashboard:search_console" do
  def report
    run_dashboard_task("ahoy_dashboard:search_console")
  end

  it "reports a missing host instead of raising" do
    allow(AhoyDashboard).to receive_messages(host: nil, canonical_host: nil)
    allow(AhoyDashboard::SearchConsole).to receive_messages(enabled?: true, client_id: "cid", client_secret: "secret")

    output = report

    expect(output).to include("redirect uri: not set, the dashboard has no host")
    expect(output).to include("set the host under settings, general, or the redirect url under settings, search console")
    expect(output).not_to include("config.")
  end

  it "reads the client id and secret off the stored credential only" do
    stub_const("ENV", ENV.to_h.merge("SEARCH_CONSOLE_CLIENT_ID" => "from-env", "SEARCH_CONSOLE_CLIENT_SECRET" => "from-env"))
    store_google_client(client_id: "cid", client_secret: nil)

    output = report

    expect(output).to include("client id: stored", "client secret: missing")
    expect(output).to include("set the client id and secret under settings, search console, at /telemetry/settings/google_connection")
    expect(output).not_to include("config.")
  end

  it "names screens where the engine is actually mounted" do
    allow(AhoyDashboard::SearchConsole).to receive_messages(client_id: nil, client_secret: nil)

    output = report

    expect(output).to include("/telemetry/settings/google_connection")
    expect(output).not_to include("/ahoy_dashboard/")
  end

  it "says the switch is off when the credentials are there" do
    search_console_switched_off!

    expect(report).to include("turn it on under settings, features")
  end

  it "points at the property picker under the mount path" do
    allow(AhoyDashboard::SearchConsole).to receive_messages(enabled?: true, client_id: "cid", client_secret: "secret")
    create(:dash_google_account)

    expect(report).to include("pick a property at /telemetry/settings/search_console_property/edit")
  end

  it "prints one line saying how to install it when its tables are missing" do
    uninstall_ahoy_dashboard(:search_console)

    expect(report).to eq("search console is not installed. run bin/rails generate " \
                         "ahoy_dashboard:install --only search_console, then bin/rails db:migrate\n")
  end
end
