require "rails_helper"

RSpec.describe "Dashboard alerts", type: :request do
  def headers
    document.css("th").map { |cell| cell.text.squish }
  end

  def rule
    AhoyDashboard::AlertEvent.first.rule
  end

  before do
    sign_in create(:user, :admin)
    allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true)
    create(:dash_alert_event, fired_at: 1.hour.ago)
  end

  it "says the alerts are emailed and leaves out a per alert sent column" do
    alert_settings(digest: %i[daily weekly monthly], recipients: [ "ops@example.com" ]) { get "/telemetry/seo/alert" }

    expect(document.text.squish).to include("Emailing", "daily, weekly, and monthly emails")
    expect(headers).to include("What happened")
    expect(headers).not_to include("Sent")
  end

  it "asks for alert emails when nothing would deliver them" do
    alert_settings(digest: []) { get "/telemetry/seo/alert" }

    expect(document.text.squish).to include("Set up alert emails to hear about alerts", "Not sending")
  end

  it "sends people to Settings, Emails and not to the rules screen for them" do
    alert_settings(digest: []) { get "/telemetry/seo/alert" }

    expect(document.text.squish).to include("pick how often and who gets them under Settings, Emails")
    expect(document.text.squish).not_to include("settings file")
    links = document.css("a")
    expect(links.map { |link| link.text.squish }).not_to include("Alert rules")
    expect(links.find { |link| link.text.squish == "Set up alert emails" }["href"]).to eq("/telemetry/settings/emails/edit")
  end

  it "says nobody gets the emails when the periods are set without recipients" do
    alert_settings(digest: [ :daily ], recipients: []) { get "/telemetry/seo/alert" }

    expect(document.text.squish).to include("set to go out daily, but nobody is set to get them", "Add an address under Settings, Emails")
  end

  it "opens on the period an alert email links to" do
    create(:dash_alert_event, rule: rule, headline: "inside the week",
                              fired_at: AhoyDashboard.time_zone.parse("2026-09-09 10:00"))
    create(:dash_alert_event, rule: rule, headline: "after the week",
                              fired_at: AhoyDashboard.time_zone.parse("2026-09-15 10:00"))

    get "/telemetry/seo/alert", params: { period: "custom", from: "2026-09-07", to: "2026-09-13" }

    expect(document.text.squish).to include("inside the week", "Sep 7 to Sep 13")
    expect(document.text.squish).not_to include("after the week")
  end

  it "pages through every alert in the range" do
    create_list(:dash_alert_event, 45, rule: rule, fired_at: 2.hours.ago)

    get "/telemetry/seo/alert"

    pager = document.at_css("nav[aria-label='Pages of alerts']")
    expect(pager.text.squish).to include("Page 1 of 2")
    following = pager.css("a").find { |link| link.text.squish == "Next" }["href"]

    get following

    expect(document.css("[aria-label='Recent alerts'] tbody tr").size).to eq(6)
  end

  describe "alerts from sample data" do
    it "warns on the page and marks each one" do
      create(:dash_alert_event, rule: rule, headline: "made up drop", fired_at: 1.hour.ago, sample_data: true)

      get "/telemetry/seo/alert"

      expect(document.at_css("#tm-alerts-sample").text.squish).to include("1 of the 2 alerts in this range came from sample data")
      row = document.css("tr").find { |node| node.text.include?("made up drop") }
      expect(row.text.squish).to include("Sample")
    end

    it "says nothing about sample data when none of them came from it" do
      get "/telemetry/seo/alert"

      expect(document.at_css("#tm-alerts-sample")).to be_nil
    end
  end

  it "shows whether each alert went out when a notifier is set" do
    allow(AhoyDashboard::Alerts).to receive(:deliverable?).and_return(true)

    alert_settings(digest: []) { get "/telemetry/seo/alert" }

    expect(headers).to include("Sent")
  end
end
