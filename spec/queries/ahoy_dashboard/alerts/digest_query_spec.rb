require "rails_helper"
require "support/ahoy_dashboard/alerts"
require "support/ahoy_dashboard/installation"

RSpec.describe AhoyDashboard::Alerts::DigestQuery do
  let(:zone) { AhoyDashboard.time_zone }
  let(:window) { AhoyDashboard::Alerts::Digests::Window.new(period: :daily, starts_on: Date.new(2026, 9, 18), ends_on: Date.new(2026, 9, 18)) }
  let(:rule) { create(:dash_alert_rule, key: "off_page_one", name: "Fell off page one", severity: :high) }

  def result(limit: AhoyDashboard::Alerts::Digests::ROW_LIMIT)
    described_class.call(window: window, limit: limit)
  end

  def fired(at:, rule: self.rule, subject: "visiting rules (us)", severity: rule.severity, **attributes)
    create(:dash_alert_event, rule: rule, subject: subject, severity: severity, fired_at: zone.parse(at), **attributes)
  end

  it "takes the events inside the window's local days and nothing either side" do
    fired(at: "2026-09-17 23:59", subject: "before (us)")
    inside = fired(at: "2026-09-18 00:00", subject: "first (us)")
    last = fired(at: "2026-09-18 23:59", subject: "last (us)")
    fired(at: "2026-09-19 00:00", subject: "after (us)")

    expect(result.events).to contain_exactly(inside, last)
  end

  it "keeps one row per rule per search, with the newest wording" do
    fired(at: "2026-09-18 04:00", headline: "visiting rules fell to 12")
    newest = fired(at: "2026-09-18 09:00", headline: "visiting rules fell to 14")

    expect(result).to have_attributes(events: [ newest ], total: 1)
  end

  it "breaks equal-time duplicates by id and only hydrates the retained events" do
    fired(at: "2026-09-18 09:00", headline: "Earlier wording")
    newest = fired(at: "2026-09-18 09:00", headline: "Latest wording")
    loaded = []
    subscriber = ->(_name, _started, _finished, _id, payload) { loaded << payload[:record_count] if payload[:class_name] == "AhoyDashboard::AlertEvent" }

    digest = ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") { result }

    expect(digest).to have_attributes(events: [ newest ], total: 1)
    expect(loaded.sum).to eq(1)
  end

  it "keeps two rules that fired on the same search" do
    lost = create(:dash_alert_rule, key: "lost_from_results", name: "Lost from the results", severity: :high)
    fired(at: "2026-09-18 04:00")
    fired(at: "2026-09-18 04:00", rule: lost)

    expect(result).to have_attributes(total: 2)
  end

  it "puts high severity first" do
    overtaken = create(:dash_alert_rule, key: "overtaken", name: "Overtaken by a rival", severity: :medium)
    medium = fired(at: "2026-09-18 09:00", rule: overtaken, subject: "a medium one (us)")
    high = fired(at: "2026-09-18 04:00", subject: "z high one (us)")

    expect(result.events).to eq([ high, medium ])
    expect(result.severities).to eq("high" => 1, "medium" => 1)
  end

  it "caps the rows but still counts everything" do
    3.times { |n| fired(at: "2026-09-18 0#{n + 1}:00", subject: "search #{n} (us)") }

    expect(result(limit: 2)).to have_attributes(total: 3, more: 1)
    expect(result(limit: 2).events.size).to eq(2)
  end

  it "counts the searches checked in the window" do
    keyword = create(:dash_serp_keyword)
    serp_reading(keyword, position: 4, at: zone.parse("2026-09-18 06:00"))
    serp_reading(keyword, position: 5, at: zone.parse("2026-09-18 18:00"))
    serp_reading(create(:dash_serp_keyword), position: 4, at: zone.parse("2026-09-17 06:00"))

    expect(result.checked).to eq(1)
  end

  describe "positions from the fake provider" do
    let(:keyword) { create(:dash_serp_keyword) }

    it "counts an alert whose newer check was invented" do
      older = serp_reading(keyword, position: 6, at: zone.parse("2026-09-17 06:00"), provider: "serpapi")
      newer = serp_reading(keyword, position: 14, at: zone.parse("2026-09-18 06:00"), provider: "fake")
      fired(at: "2026-09-18 07:00", check: newer, previous_check: older)

      expect(result.invented).to eq(1)
    end

    it "counts an alert compared against an invented check, the first real check after switching" do
      older = serp_reading(keyword, position: 6, at: zone.parse("2026-09-17 06:00"), provider: "fake")
      newer = serp_reading(keyword, position: 14, at: zone.parse("2026-09-18 06:00"), provider: "serpapi")
      fired(at: "2026-09-18 07:00", check: newer, previous_check: older)

      expect(result.invented).to eq(1)
    end

    it "counts nothing when both checks were real" do
      older = serp_reading(keyword, position: 6, at: zone.parse("2026-09-17 06:00"), provider: "serpapi")
      newer = serp_reading(keyword, position: 14, at: zone.parse("2026-09-18 06:00"), provider: "serpapi")
      fired(at: "2026-09-18 07:00", check: newer, previous_check: older)

      expect(result.invented).to eq(0)
    end
  end

  it "counts an alert that came off sample data without any checks behind it" do
    backlinks = create(:dash_alert_rule, key: "backlinks_lost", name: "Referring domains lost")
    fired(at: "2026-09-18 07:00", rule: backlinks, subject: "example.com", sample_data: true)
    fired(at: "2026-09-18 08:00", rule: backlinks, subject: "example.org")

    expect(result.invented).to eq(1)
  end

  it "counts the rank tracking rules that are on apart from the rest" do
    rule
    create(:dash_alert_rule, key: "job_failed", name: "A job failed")
    create(:dash_alert_rule, key: "big_drop", name: "Dropped several places", enabled: false)

    expect(result).to have_attributes(rules_on: 2, rank_rules_on: 1)
  end

  describe "without rank tracking installed" do
    let(:jobs) { create(:dash_alert_rule, key: "job_failed", name: "A job failed", severity: :high) }

    before do
      rule
      jobs
      uninstall_ahoy_dashboard(:serp)
    end

    it "still reads the events, counts no checks and no rank rules, and names the rules that could not run" do
      event = fired(at: "2026-09-18 07:00", rule: jobs, subject: "Rank checks")

      expect(result).to have_attributes(events: [ event ], total: 1, checked: 0, rules_on: 2, rank_rules_on: 0,
                                        waiting: [ rule ], rules_ran: 1)
    end

    it "counts only the sample data flag towards invented, whatever check ids are left on the rows" do
      fired(at: "2026-09-18 07:00", rule: jobs, subject: "Rank checks", check_id: 41, previous_check_id: 40)
      fired(at: "2026-09-18 08:00", rule: jobs, subject: "Alert rules", sample_data: true)

      expect(result.invented).to eq(1)
    end
  end
end
