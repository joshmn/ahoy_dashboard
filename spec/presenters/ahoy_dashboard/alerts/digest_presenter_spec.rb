require "rails_helper"

RSpec.describe AhoyDashboard::Alerts::DigestPresenter do
  let(:zone) { AhoyDashboard.time_zone }
  let(:rule) { build(:dash_alert_rule, name: "Fell off page one") }

  def window(period, starts_on, ends_on = starts_on)
    AhoyDashboard::Alerts::Digests::Window.new(period: period, starts_on: starts_on, ends_on: ends_on)
  end

  def event(headline, severity: "high", at: "2026-09-18 04:15")
    build(:dash_alert_event, rule: rule, headline: headline, detail: "Was 6 on the previous check.",
                             severity: severity, fired_at: zone.parse(at))
  end

  def presenter(window: window(:daily, Date.new(2026, 9, 18)), events: [], total: events.size,
                checked: 12, rules_on: 3, rank_rules_on: rules_on, invented: 0)
    result = AhoyDashboard::Alerts::DigestQuery::Result.new(
      window: window, events: events, total: total, severities: events.map(&:severity).group_by { |item| item }.transform_values(&:size),
      checked: checked, rules_on: rules_on, rank_rules_on: rank_rules_on, invented: invented
    )
    described_class.new(result, host: "example.com")
  end

  describe "with alerts" do
    let(:events) { [ event("visiting rules fell to 14"), event("Overtaken on rdap", severity: "medium", at: "2026-09-18 21:30") ] }

    it "puts the period and the counts in the subject" do
      expect(presenter(events: events).subject).to eq("Alerts for Sep 18: 2 alerts")
    end

    it "says one alert rather than one alerts" do
      expect(presenter(events: events.first(1)).headline).to eq("1 alert")
    end

    it "groups the thousands in a big count, the way the traffic email does" do
      expect(presenter(events: events, total: 1_204).subject).to eq("Alerts for Sep 18: 1,204 alerts")
    end

    it "sums up the severities" do
      expect(presenter(events: events).summary).to eq("1 high, 1 medium.")
    end

    it "groups the rows by severity with the time they fired" do
      groups = presenter(events: events).groups

      expect(groups.map(&:label)).to eq(%w[High Medium])
      expect(sole_item(groups.first.rows)).to have_attributes(headline: "visiting rules fell to 14",
                                                        rule: "Fell off page one", at: "4:15 AM")
    end

    it "reads the time-zone setting once for all email rows" do
      daily = presenter(events: events)
      AhoyDashboard::Preferences.forget
      groups = nil
      reads = setting_reads { groups = daily.groups }

      expect(groups.flat_map(&:rows).map(&:at)).to eq([ "4:15 AM", "9:30 PM" ])
      expect(reads).to eq(1)
    end

    it "dates the rows rather than timing them on a weekly email" do
      weekly = presenter(window: window(:weekly, Date.new(2026, 9, 14), Date.new(2026, 9, 20)), events: events)

      expect(sole_item(weekly.groups.first.rows).at).to eq("Sep 18")
    end

    it "says how many are left out past the cap" do
      capped = presenter(events: events, total: 23)

      expect([ capped.more?, capped.more_label, capped.more_link_label ])
        .to eq([ true, "Showing 2 of 23.", "See the other 21 in the dashboard" ])
    end

    it "warns when every alert came off invented positions" do
      expect(presenter(events: events, invented: 2).invented_note).to start_with("These came from sample data")
    end

    it "says how many when only some did" do
      expect(presenter(events: events, invented: 1).invented_note).to start_with("1 of these came from sample data")
    end
  end

  describe "naming the period" do
    it "spans a week inside one month" do
      weekly = presenter(window: window(:weekly, Date.new(2026, 9, 7), Date.new(2026, 9, 13)))

      expect(weekly.subject).to start_with("Alerts for Sep 7 to 13:")
      expect(weekly.period_heading).to eq("Mon, Sep 7 to Sun, Sep 13")
    end

    it "spans a week across two months" do
      weekly = presenter(window: window(:weekly, Date.new(2026, 8, 31), Date.new(2026, 9, 6)))

      expect(weekly.subject).to start_with("Alerts for Aug 31 to Sep 6:")
    end

    it "names the month" do
      monthly = presenter(window: window(:monthly, Date.new(2026, 8, 1), Date.new(2026, 8, 31)))

      expect(monthly.subject).to start_with("Alerts for August 2026:")
      expect(monthly.footer).to eq("You get this monthly because alert emails are on for example.com.")
    end
  end

  describe "with nothing to report" do
    it "says nothing fired when searches were checked" do
      quiet = presenter(checked: 12)

      expect([ quiet.subject, quiet.headline, quiet.summary ]).to eq([
        "Alerts for Sep 18: nothing fired",
        "Nothing fired",
        "12 searches were checked on Sep 18, and none of them crossed a rule."
      ])
    end

    it "says there is no available data when nothing was checked" do
      blank = presenter(checked: 0)

      expect([ blank.subject, blank.headline, blank.summary ]).to eq([
        "Alerts for Sep 18: no available data",
        "No available data",
        "No rankings were checked on Sep 18, so there was nothing to compare."
      ])
    end

    it "says no rules are on before anything else" do
      off = presenter(checked: 0, rules_on: 0)

      expect([ off.subject, off.headline ]).to eq([ "Alerts for Sep 18: no rules are on", "No alert rules are on" ])
    end

    it "says the rules ran when none of them read rankings" do
      quiet = presenter(checked: 0, rules_on: 2, rank_rules_on: 0)

      expect([ quiet.subject, quiet.summary ]).to eq([
        "Alerts for Sep 18: nothing fired", "The rules ran on Sep 18, and nothing crossed a rule."
      ])
    end

    it "says no rankings were checked without calling the whole email empty of data" do
      mixed = presenter(checked: 0, rules_on: 3, rank_rules_on: 1)

      expect([ mixed.subject, mixed.summary ]).to eq([
        "Alerts for Sep 18: nothing fired", "No rankings were checked on Sep 18, and nothing else crossed a rule."
      ])
    end

    it "has no rows" do
      expect(presenter.groups).to be_empty
    end
  end
end
