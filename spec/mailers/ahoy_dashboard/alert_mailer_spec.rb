require "rails_helper"

RSpec.describe AhoyDashboard::AlertMailer do
  let(:zone) { AhoyDashboard.time_zone }
  let(:rule) { create(:dash_alert_rule, key: "off_page_one", severity: :high) }
  let(:digest) do
    AhoyDashboard::AlertDigest.create!(period: :daily, starts_on: Date.new(2026, 9, 18), ends_on: Date.new(2026, 9, 18))
  end

  subject(:mail) { described_class.with(digest: digest, recipients: [ "ops@example.com" ]).digest }

  def html
    mail.html_part.body.to_s
  end

  def text
    mail.text_part.body.to_s
  end

  context "with an alert in the period" do
    before do
      create(:dash_alert_event, rule: rule, headline: "visiting rules fell to 14",
                                detail: "Was 6 on the previous check.", subject: "visiting rules (us)",
                                fired_at: zone.parse("2026-09-18 04:15"))
    end

    it "goes to the recipients with the period and the counts in the subject" do
      expect(mail.to).to eq([ "ops@example.com" ])
      expect(mail.subject).to eq("Alerts for Sep 18: 1 alert")
    end

    it "lists the alert and the rule that fired it in both parts" do
      [ html, text ].each do |body|
        expect(body).to include("visiting rules fell to 14", "Was 6 on the previous check.", "Fell off page one")
      end
    end

    it "links into the dashboard where it is mounted" do
      hrefs = Nokogiri::HTML5(html).css("a").map { |link| link["href"] }

      expect(hrefs).to include("http://example.com/telemetry/seo/alert?from=2026-09-18&period=custom&to=2026-09-18",
                               "http://example.com/telemetry/rankings",
                               "http://example.com/telemetry/settings/alert_rules")
      expect(text).to include("Open alerts: http://example.com/telemetry/seo/alert?from=2026-09-18&period=custom&to=2026-09-18")
    end

    it "opens the alerts page on the email's own period" do
      weekly = AhoyDashboard::AlertDigest.create!(period: :weekly, starts_on: Date.new(2026, 9, 7),
                                                  ends_on: Date.new(2026, 9, 13))
      body = described_class.with(digest: weekly, recipients: [ "ops@example.com" ]).digest.html_part.body.to_s
      link = Nokogiri::HTML5(body).css("a").find { |node| node.text.squish == "Open alerts" }

      expect(Rack::Utils.parse_query(URI(link["href"]).query))
        .to eq("period" => "custom", "from" => "2026-09-07", "to" => "2026-09-13")
    end

    it "sends from the parent mailer's address unless config names one" do
      expect(mail.from).to eq([ "alerts@example.com" ])
    end

    it "sends from the configured address when there is one" do
      alert_settings(from: "SEO <seo@example.com>") do
        expect(mail.from).to eq([ "seo@example.com" ])
      end
    end
  end

  it "warns when the positions behind an alert were invented" do
    keyword = create(:dash_serp_keyword)
    older = serp_reading(keyword, position: 6, at: zone.parse("2026-09-17 06:00"), provider: "fake")
    newer = serp_reading(keyword, position: 14, at: zone.parse("2026-09-18 06:00"), provider: "fake")
    create(:dash_alert_event, rule: rule, check: newer, previous_check: older, fired_at: zone.parse("2026-09-18 07:00"))

    expect(html).to include("These came from sample data")
  end

  it "still goes out when there was nothing to check, and says so" do
    rule

    expect(mail.subject).to eq("Alerts for Sep 18: no available data")
    expect(text).to include("No rankings were checked on Sep 18, so there was nothing to compare.")
  end

  context "with rank tracking not installed" do
    let(:rule) { create(:dash_alert_rule, key: "job_failed", severity: :high) }

    before do
      create(:dash_alert_event, rule: rule, headline: "Rank checks failed", subject: "Rank checks",
                                fired_at: zone.parse("2026-09-18 04:15"))
      uninstall_ahoy_dashboard(:serp)
    end

    it "still sends the alerts that fired" do
      expect(mail.subject).to eq("Alerts for Sep 18: 1 alert")
      expect(text).to include("Rank checks failed")
    end

    it "names the rules that are on but could not run, and how to install what they need" do
      create(:dash_alert_rule, key: "off_page_one")
      create(:dash_alert_rule, key: "big_drop")

      note = "Dropped several places and Fell off page one are on but did not run, because rank tracking is not installed. " \
             "Run bin/rails generate ahoy_dashboard:install --only serp, then bin/rails db:migrate."

      expect(text).to include(note)
      expect(html).to include(note)
    end
  end

  context "with only rules on that cannot run" do
    before do
      create(:dash_alert_rule, key: "spend_near_cap", threshold: 80)
      uninstall_ahoy_dashboard(:serp, :keywords, :backlinks)
    end

    it "says nothing could run rather than that no rules are on" do
      expect(mail.subject).to eq("Alerts for Sep 18: nothing could run")
      expect(text).to include("Every rule that is on needs something that is not installed")
      expect(text).to include("Nearing the monthly cap is on but did not run, because none of rank tracking, " \
                              "keyword research, or backlinks is installed. Run one of bin/rails generate " \
                              "ahoy_dashboard:install --only serp, bin/rails generate ahoy_dashboard:install " \
                              "--only keywords, or bin/rails generate ahoy_dashboard:install --only backlinks, " \
                              "then bin/rails db:migrate.")
    end
  end
end
