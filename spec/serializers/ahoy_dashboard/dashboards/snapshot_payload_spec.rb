# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::Dashboards::SnapshotPayload do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }
  let(:query) { AhoyDashboard::QueryForm.from_params({ period: "30d", filters: "none" }) }
  let(:reading) { AhoyDashboard::Dashboards::ShowQuery.call(query: query) }
  let(:payload) { JSON.parse(JSON.generate(described_class.dump(reading: reading))) }
  let(:restored) { described_class.load(payload: payload, computed_at: now, realtime: 42) }
  let!(:annotation) { create(:dash_annotation, happened_at: now - 1.day) }
  let!(:question) { create(:dash_saved_query, pinned: true) }
  let!(:funnel) { create(:dash_funnel) }

  around { |example| travel_to(now) { example.run } }

  before do
    visit = dash_landing("/start", at: now - 1.day, visitor: "snapshot visitor", country: "US", browser: "Firefox")
    dash_page_view(visit, path: "/finish", at: now - 1.day + 2.minutes)
    funnel.funnel_steps.each_with_index do |step, index|
      dash_goal(visit, step.goal.event_name, at: now - 1.day + (index + 3).minutes)
    end
    create(:dash_search_console_row, date: now.to_date - 2, query: "snapshot query")
    create(:dash_search_console_keyword, date: now.to_date - 2, query: "snapshot query")
    create(:dash_search_console_total, date: now.to_date - 2)
    create(:dash_search_console_day, date: now.to_date - 2)
  end

  def primitive?(value)
    case value
    when Hash then value.keys.all? { |key| key.is_a?(String) } && value.values.all? { |item| primitive?(item) }
    when Array then value.all? { |item| primitive?(item) }
    else [String, Integer, Float, TrueClass, FalseClass, NilClass].any? { |type| value.is_a?(type) }
    end
  end

  it "contains only JSON primitives before serialization" do
    expect(primitive?(described_class.dump(reading: reading))).to eq(true)
  end

  it "round trips every populated analytical panel through JSON" do
    expect(described_class.dump(reading: restored)).to eq(payload)
  end

  it "retains the exact numerical chart readings" do
    expect(restored.readings).to eq(reading.readings)
  end

  it "retains all funnel step readings" do
    expect(restored.funnels).to eq(reading.funnels)
  end

  it "retains the typed journey and its exit rows" do
    expect(restored.journey).to eq(reading.journey)
  end

  it "retains Search Console readings and precise inclusive time boundaries" do
    expect(reading.search_console.queries.map(&:label)).to eq([ "snapshot query" ])
    expect(restored.search_console).to eq(reading.search_console)
  end

  it "still loads a Search Console reading stored with the live dates it no longer writes" do
    stored = payload.deep_dup
    stored["search_console"]["live_dates"] = []

    expect(described_class.load(payload: stored, computed_at: now, realtime: 42).search_console)
      .to eq(reading.search_console)
  end

  it "retains pinned numeric sparklines and precise inclusive time boundaries" do
    expect(restored.pinned_cards).to eq(reading.pinned_cards)
  end

  it "uses the supplied live realtime count" do
    expect(restored.realtime).to eq(42)
  end

  it "keeps the completed snapshot timestamp separate from its analytical values" do
    expect(restored.computed_at).to eq(now)
  end

  it "reloads current annotation labels" do
    payload
    annotation.update!(label: "Corrected deployment")

    expect(restored.annotations.first.label).to eq("Corrected deployment")
  end

  it "reloads current question labels" do
    payload
    question.update!(name: "Renamed question")

    expect(restored.pinned_cards.first.question.name).to eq("Renamed question")
  end

  it "reloads current funnel labels" do
    payload
    funnel.update!(name: "Renamed funnel")

    expect(restored.funnels.first.funnel.name).to eq("Renamed funnel")
  end

  it "loads current goal currencies separately from cached numerical readings" do
    payload
    goal = funnel.funnel_steps.first.goal
    goal.update!(currency: "USD")

    expect(restored.goals.find { |definition| definition.id == goal.id }.currency).to eq("USD")
  end

  it "rejects annotations deleted between the cache lookup and hydration" do
    payload
    annotation.destroy!

    expect { restored }.to raise_error(described_class::MissingDefinition)
  end

  it "rejects pinned questions deleted between the cache lookup and hydration" do
    payload
    question.destroy!

    expect { restored }.to raise_error(described_class::MissingDefinition)
  end

  it "rejects funnels deleted between the cache lookup and hydration" do
    payload
    funnel.destroy!

    expect { restored }.to raise_error(described_class::MissingDefinition)
  end

  it "does not hide database errors while hydrating a snapshot" do
    payload
    connection = AhoyDashboard::Annotation.connection
    connection.transaction(requires_new: true) do
      connection.execute("ALTER TABLE ahoy_dashboard_annotations RENAME COLUMN id TO unavailable_id")

      expect { restored }.to raise_error(ActiveRecord::StatementInvalid)
      raise ActiveRecord::Rollback
    end
  end

  it "retains empty optional panels for a chart-only reading" do
    empty = AhoyDashboard::Dashboards::ShowQuery.call(query: query, cards: false)
    serialized = described_class.dump(reading: empty)
    loaded = described_class.load(payload: serialized, computed_at: now, realtime: 0)

    expect(described_class.dump(reading: loaded)).to eq(serialized)
  end

  it "retains exclusive time ranges across a daylight-saving transition" do
    range = Time.iso8601("2026-11-01T01:30:00-04:00")...Time.iso8601("2026-11-01T01:30:00-05:00")

    expect(described_class.load_range(payload: described_class.dump_range(range: range))).to eq(range)
  end
end
