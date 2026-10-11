require "rails_helper"
require "support/ahoy_dashboard/serp"

RSpec.describe AhoyDashboard::SerpProvider do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 20, 9, 0) }

  around { |example| travel_to(now) { example.run } }

  describe "credentials" do
    it "stores them encrypted and reads them back" do
      provider = create(:dash_serp_provider, :serpapi)

      expect(provider.reload.credential(:api_key)).to eq("stored-key")
      expect(provider.read_attribute(:credentials)).not_to include("stored-key")
    end

    it "drops blanks rather than storing an empty key" do
      provider = create(:dash_serp_provider, :serpapi, credentials: { api_key: "  " })

      expect(provider.credentials).to eq({})
    end

    it "reads as nothing stored when the envelope cannot be opened" do
      provider = create(:dash_serp_provider, :serpapi)
      provider.update_column(:credentials, "not an envelope")

      expect(provider.reload.credentials).to eq({})
    end

    it "knows whether it has everything its adapter needs" do
      expect(create(:dash_serp_provider, :serpapi)).to be_ready
      expect(build(:dash_serp_provider, :serpapi, credentials: {})).not_to be_ready
    end

    it "counts an adapter that needs no credentials as ready" do
      expect(create(:dash_serp_provider)).to be_ready
    end
  end

  describe "the monthly ceiling" do
    it "has room until the ceiling is reached" do
      provider = create(:dash_serp_provider, monthly_cap_units: 10)

      expect(provider.room_for?(10)).to be(true)
      expect(provider.room_for?(11)).to be(false)
    end

    it "counts what has been spent this month" do
      provider = create(:dash_serp_provider, monthly_cap_units: 10)
      provider.record_spend!(4)

      expect(provider.spent_this_month).to eq(4)
      expect(provider.remaining_units).to eq(6)
    end

    it "starts again when the month turns rather than needing a job to reset it" do
      provider = create(:dash_serp_provider, monthly_cap_units: 10)
      provider.record_spend!(10)

      expect(provider.spent_this_month(now: now + 5.days)).to eq(10)
      expect(provider.spent_this_month(now: now.next_month)).to eq(0)
      expect(provider.room_for?(10, now: now.next_month)).to be(true)
    end

    it "treats a zero ceiling as no ceiling" do
      provider = create(:dash_serp_provider, monthly_cap_units: 0)
      provider.record_spend!(9_999)

      expect(provider).to be_room_for(1_000_000)
      expect(provider.remaining_units).to eq(Float::INFINITY)
    end

    it "records what it spent against the month it spent it in" do
      provider = create(:dash_serp_provider)
      provider.record_spend!(3, now: now.next_month)

      expect(provider.reload.units_reset_on).to eq(now.next_month.to_date.beginning_of_month)
      expect(provider.units_spent).to eq(3)
    end

    it "adds spend from two copies of the same row without losing either" do
      provider = create(:dash_serp_provider, monthly_cap_units: 100)
      first = described_class.find(provider.id)
      second = described_class.find(provider.id)

      first.record_spend!(2)
      second.record_spend!(3)

      expect(provider.reload.spent_this_month).to eq(5)
      expect(second.spent_this_month).to eq(5)
    end

    it "lets only one of two stale copies claim the last unit" do
      provider = create(:dash_serp_provider, monthly_cap_units: 5, units_spent: 4,
                                             units_reset_on: now.to_date.beginning_of_month)
      first = described_class.find(provider.id)
      second = described_class.find(provider.id)

      expect(first.reserve!(1)).to be(true)
      expect(second.reserve!(1)).to be(false)
      expect(provider.reload.spent_this_month).to eq(5)
    end

    it "reserves against a fresh month when the stored count is from last month" do
      provider = create(:dash_serp_provider, monthly_cap_units: 5, units_spent: 5,
                                             units_reset_on: now.prev_month.to_date.beginning_of_month)

      expect(provider.reserve!(5)).to be(true)
      expect(provider.reload.spent_this_month).to eq(5)
    end

    it "gives back what a reservation did not spend" do
      provider = create(:dash_serp_provider, monthly_cap_units: 10)

      provider.reserve!(4)
      provider.settle!(4, 1)

      expect(provider.reload.spent_this_month).to eq(1)
      expect(provider.last_used_at).to eq(now)
    end

    it "never reserves past the ceiling but always lets a free request through" do
      provider = create(:dash_serp_provider, :spent, monthly_cap_units: 500)

      expect(provider.reserve!(1)).to be(false)
      expect(provider.reserve!(0)).to be(true)
      expect(provider.reload.spent_this_month).to eq(500)
    end
  end

  describe "#activate!" do
    it "switches every other one off, because only one runs the searches" do
      first = create(:dash_serp_provider, :active)
      second = create(:dash_serp_provider, :serpapi)

      second.activate!

      expect(first.reload).not_to be_active
      expect(second.reload).to be_active
    end
  end

  it "reads back through Serp.credential when it is the active one" do
    create(:dash_serp_provider, :serpapi, :active)

    expect(AhoyDashboard::Serp.credential(:serpapi, :api_key)).to eq("stored-key")
    expect(AhoyDashboard::Serp.provider).to eq(:serpapi)
  end

  it "is the only place a credential comes from" do
    stub_const("ENV", ENV.to_h.merge("SERPAPI_KEY" => "from-env"))

    expect(AhoyDashboard::Serp.credential(:serpapi, :api_key)).to be_nil
    expect(AhoyDashboard::Serp.provider).to eq(:fake)
  end
end
