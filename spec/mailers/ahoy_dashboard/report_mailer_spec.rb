require "rails_helper"
require "support/ahoy_dashboard/fixtures"
require "support/ahoy_dashboard/reports"

RSpec.describe AhoyDashboard::ReportMailer do
  let(:digest) do
    AhoyDashboard::ReportDigest.create!(period: :daily, starts_on: Date.new(2026, 8, 10), ends_on: Date.new(2026, 8, 10))
  end

  subject(:mail) { described_class.with(digest: digest, recipients: [ "ops@example.com" ]).digest }

  def html
    mail.html_part.body.to_s
  end

  def text
    mail.text_part.body.to_s
  end

  def hrefs
    Nokogiri::HTML5(html).css("a").map { |link| link["href"] }
  end

  before do
    2.times do |n|
      at = dash_time(2026, 8, 10, 9)
      visit = dash_visit(started_at: at, visitor: "v#{n}")
      dash_page_view(visit, path: "/going-to-federal-prison", at: at)
    end

    earlier = dash_time(2026, 8, 9, 9)
    dash_page_view(dash_visit(started_at: earlier, visitor: "older"), path: "/", at: earlier)
  end

  it "goes to the recipients with the period and the visitor count in the subject" do
    expect(mail.to).to eq([ "ops@example.com" ])
    expect(mail.subject).to eq("Traffic for Aug 10: 2 visitors")
  end

  it "prints the four numbers and the lists in both parts" do
    [ html, text ].each do |body|
      expect(body).to include("Visitors", "Pageviews", "Bounce rate", "Top pages", "/going-to-federal-prison")
    end
  end

  it "opens the dashboard on the email's own dates" do
    dates = { "period" => "custom", "from" => "2026-08-10", "to" => "2026-08-10" }
    dashboard = hrefs.find { |href| href.start_with?("http://example.com/telemetry/?") }

    expect(Rack::Utils.parse_query(URI(dashboard).query)).to eq(dates)
    expect(Rack::Utils.parse_query(URI(hrefs.grep(/metric=bounce_rate/).first).query))
      .to eq(dates.merge("metric" => "bounce_rate"))
    expect(Rack::Utils.parse_query(URI(hrefs.grep(%r{/telemetry/explore}).first).query))
      .to eq(dates.merge("dimension" => "page"))
    expect(text).to include("Open the dashboard: http://example.com/telemetry/?")
  end

  it "reads the query itself when nobody hands it one" do
    expect(mail.body.encoded).to include("2 visitors")
  end

  it "prints the result it is handed rather than running the query again" do
    result = AhoyDashboard::Reports::DigestQuery.call(window: digest.window)
    allow(AhoyDashboard::Reports::DigestQuery).to receive(:call).and_call_original

    described_class.with(digest: digest, result: result, recipients: [ "ops@example.com" ]).digest.subject

    expect(AhoyDashboard::Reports::DigestQuery).not_to have_received(:call)
  end

  it "sends from the parent mailer's address unless config names one" do
    expect(mail.from).to eq([ "alerts@example.com" ])
  end

  it "sends from the configured address when there is one" do
    report_settings(from: "Traffic <traffic@example.com>") do
      expect(mail.from).to eq([ "traffic@example.com" ])
    end
  end

  it "still goes out on a quiet day, and says so" do
    quiet = AhoyDashboard::ReportDigest.create!(period: :daily, starts_on: Date.new(2026, 7, 1),
                                                ends_on: Date.new(2026, 7, 1))
    body = described_class.with(digest: quiet, recipients: [ "ops@example.com" ]).digest

    expect(body.subject).to eq("Traffic for Jul 1: 0 visitors")
    expect(body.text_part.body.to_s).to include("Nobody came, so there is nothing to list.")
  end
end
