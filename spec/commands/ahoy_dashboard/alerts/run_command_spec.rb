require "rails_helper"

RSpec.describe AhoyDashboard::Alerts::RunCommand do
  let(:keyword) { create(:dash_serp_keyword) }
  let(:rule) { create(:dash_alert_rule, key: "off_page_one", threshold: 10) }

  before { allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true) }

  def run
    described_class.call(rules: [ rule ])
  end

  def events
    AhoyDashboard::AlertEvent.where(rule: rule)
  end

  describe "the same comparison read by more than one run" do
    before do
      serp_reading(keyword, position: 6, at: 26.hours.ago)
      serp_reading(keyword, position: 14, at: 2.hours.ago)
    end

    it "writes the alert once" do
      3.times { run }

      expect(events.count).to eq(1)
    end

    it "counts the later runs as repeats" do
      run

      expect(run[:ok]).to have_attributes(fired: [], repeats: 1)
    end
  end

  describe "handing an alert to the notifier" do
    before do
      serp_reading(keyword, position: 6, at: 26.hours.ago)
      serp_reading(keyword, position: 14, at: 2.hours.ago)
    end

    it "marks the alert delivered when the notifier takes it" do
      handed = []
      allow(AhoyDashboard::Alerts).to receive(:notifier).and_return(->(event) { handed << event.id })

      expect(run[:ok]).to have_attributes(delivered: 1)
      expect(handed).to eq([ sole_item(events).id ])
      expect(sole_item(events)).to have_attributes(delivered_at: be_present, delivery_error: nil)
    end

    it "keeps the alert and writes the error down when the notifier raises" do
      allow(AhoyDashboard::Alerts).to receive(:notifier).and_return(->(_event) { raise "webhook down" })

      expect(run[:ok]).to have_attributes(delivered: 0)
      expect(sole_item(events)).to have_attributes(delivered_at: nil, delivery_error: "RuntimeError: webhook down")
    end

    it "sends nothing when no notifier is set" do
      expect(run[:ok]).to have_attributes(delivered: 0)
      expect(sole_item(events)).to have_attributes(delivered_at: nil, delivery_error: nil)
    end
  end

  describe "how often a rule has fired" do
    before do
      serp_reading(keyword, position: 6, at: 26.hours.ago)
      serp_reading(keyword, position: 14, at: 2.hours.ago)
    end

    it "counts the run's own alerts when the run crosses a minute" do
      travel_to(Time.current.change(sec: 59)) do
        allow(AhoyDashboard::Alerts).to receive(:deliverable?) do
          travel 2.seconds
          false
        end

        run
      end

      expect(rule.reload).to have_attributes(fired_count: 1, last_fired_at: sole_item(events).fired_at)
    end

    it "does not count an earlier run's alerts again in the same minute" do
      travel_to(Time.current.change(sec: 10)) do
        run
        travel 5.seconds
        run
      end

      expect(rule.reload.fired_count).to eq(1)
    end

    it "still records that a quiet run checked" do
      run

      travel_to(1.hour.from_now) { run }

      expect(rule.reload).to have_attributes(fired_count: 1, last_fired_at: sole_item(events).fired_at)
      expect(rule.last_checked_at).to be > sole_item(events).fired_at
    end
  end

  it "records the two checks it compared" do
    older = serp_reading(keyword, position: 6, at: 26.hours.ago)
    newer = serp_reading(keyword, position: 14, at: 2.hours.ago)

    run

    expect(sole_item(events)).to have_attributes(check_id: newer.id, previous_check_id: older.id)
  end

  it "reports a new comparison once a newer check comes in" do
    drop = create(:dash_alert_rule, key: "big_drop", threshold: 5)
    serp_reading(keyword, position: 6, at: 50.hours.ago)
    serp_reading(keyword, position: 14, at: 26.hours.ago)
    described_class.call(rules: [ drop ])

    serp_reading(keyword, position: 21, at: 2.hours.ago)
    described_class.call(rules: [ drop ])

    expect(AhoyDashboard::AlertEvent.where(rule: drop).pluck(:detail))
      .to contain_exactly("6 to 14 between checks.", "14 to 21 between checks.")
  end

  describe "a keyword checked less often than daily" do
    let(:keyword) { create(:dash_serp_keyword, frequency: :weekly) }

    it "compares its newest reading against the one before, however old" do
      serp_reading(keyword, position: 6, at: 8.days.ago)
      serp_reading(keyword, position: 14, at: 2.hours.ago)

      run

      expect(sole_item(events)).to have_attributes(headline: "#{keyword.query} fell to 14",
                                             detail: "Was 6 on the previous check.")
    end

    it "leaves it alone when its newest reading is older than two days" do
      serp_reading(keyword, position: 6, at: 10.days.ago)
      serp_reading(keyword, position: 14, at: 3.days.ago)

      run

      expect(events).to be_empty
    end
  end
end
