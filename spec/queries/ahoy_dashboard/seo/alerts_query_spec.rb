require "rails_helper"

RSpec.describe AhoyDashboard::Seo::AlertsQuery do
  let(:range) { 7.days.ago..Time.current }
  let(:rule) { create(:dash_alert_rule) }

  def result(page: 1)
    described_class.call(range: range, page: page)
  end

  it "returns zero counters and the first page when no alerts exist" do
    expect(result(page: 9)).to have_attributes(total: 0, firing: 0, failed_alerts: 0, page: 1, events: [])
  end

  it "reads total, high-severity and non-null delivery errors together without changing their populations" do
    create(:dash_alert_event, rule: rule, fired_at: range.begin, severity: :high, delivery_error: nil)
    create(:dash_alert_event, rule: rule, fired_at: range.end, severity: :medium, delivery_error: "")
    create(:dash_alert_event, rule: rule, fired_at: 1.day.ago, severity: :low, delivery_error: "failed")
    create(:dash_alert_event, rule: rule, fired_at: range.begin - 1.second, severity: :high, delivery_error: "outside")
    found = nil
    reads = captured_sql('FROM "ahoy_dashboard_alert_events"', cached: true) { found = result }

    expect(found).to have_attributes(total: 3, firing: 1, failed_alerts: 2)
    expect(reads.grep(/count\(/i).size).to eq(1)
  end

  describe "counts past one page of alerts" do
    before do
      create_list(:dash_alert_event, 45, rule: rule, severity: :high, fired_at: 1.day.ago)
      create_list(:dash_alert_event, 5, rule: rule, severity: :low, fired_at: 1.day.ago, delivery_error: "RuntimeError: down")
      create(:dash_alert_event, rule: rule, severity: :high, fired_at: 30.days.ago)
    end

    it "counts every alert in the range, not only the ones listed" do
      expect(result).to have_attributes(total: 50, firing: 45)
      expect(result.events.size).to eq(described_class::LIMIT)
    end

    it "counts every alert that failed to send" do
      expect(result.undelivered).to eq(5)
    end

    it "lists the rest on the next page" do
      expect(result.pages).to eq(2)
      expect(result(page: 2).events.size).to eq(10)
      expect(result.events.map(&:id) & result(page: 2).events.map(&:id)).to be_empty
    end

    it "holds a page past the end to the last one" do
      expect(result(page: 9)).to have_attributes(page: 2)
    end
  end

  describe "alerts from sample data" do
    let(:keyword) { create(:dash_serp_keyword) }

    it "finds alerts flagged as sample and alerts that compared sample rank checks" do
      flagged = create(:dash_alert_event, rule: rule, fired_at: 1.hour.ago, sample_data: true)
      invented = serp_reading(keyword, position: 14, at: 2.hours.ago, provider: "fake")
      compared = create(:dash_alert_event, rule: rule, fired_at: 1.hour.ago, check_id: invented.id)
      previous = create(:dash_alert_event, rule: rule, fired_at: 1.hour.ago, previous_check_id: invented.id)
      other_invented = serp_reading(keyword, position: 15, at: 1.hour.ago, provider: "fake")
      both = create(:dash_alert_event, rule: rule, fired_at: 1.hour.ago, sample_data: true,
                                     check_id: other_invented.id, previous_check_id: invented.id)
      real = create(:dash_alert_event, rule: rule, fired_at: 1.hour.ago,
                                       check_id: serp_reading(keyword, position: 9, at: 3.hours.ago, provider: "serper").id)

      expect(result.sample).to eq(4)
      expect(result.sample_data?(flagged)).to be(true)
      expect(result.sample_data?(compared)).to be(true)
      expect(result.sample_data?(previous)).to be(true)
      expect(result.sample_data?(both)).to be(true)
      expect(result.sample_data?(real)).to be(false)
    end
  end
end
