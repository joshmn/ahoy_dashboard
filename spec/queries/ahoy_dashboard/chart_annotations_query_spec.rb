# frozen_string_literal: true

require "rails_helper"
require "support/ahoy_dashboard/installation"
require "support/ahoy_dashboard/switches"

RSpec.describe AhoyDashboard::ChartAnnotationsQuery do
  let(:morning) { AhoyDashboard.time_zone.local(2026, 8, 10, 9) }
  let(:range) { morning.beginning_of_day..(morning + 1.day).end_of_day }

  it "returns the first two notes in each chart bucket in time and id order" do
    second = create(:dash_annotation, happened_at: morning + 1.hour)
    first = create(:dash_annotation, happened_at: morning)
    create(:dash_annotation, happened_at: morning + 1.hour)
    next_day = create(:dash_annotation, happened_at: morning + 1.day)

    expect(described_class.call(range: range).map(&:id)).to eq([first.id, second.id, next_day.id])
  end

  it "uses the requested chart interval for the annotation cap" do
    notes = 3.times.map { |hour| create(:dash_annotation, happened_at: morning + hour.hours) }

    expect(described_class.call(range: range, bucket: :hour).map(&:id)).to eq(notes.map(&:id))
  end

  it "ignores notes outside the requested range" do
    inside = create(:dash_annotation, happened_at: morning)
    create(:dash_annotation, happened_at: range.begin - 1.second)
    create(:dash_annotation, happened_at: range.end + 1.second)

    expect(described_class.call(range: range).map(&:id)).to eq([inside.id])
  end

  it "preserves the grouped model API" do
    note = create(:dash_annotation, happened_at: morning)

    expect(AhoyDashboard::Annotation.for_range(range)).to eq(morning.beginning_of_day => [note])
  end

  it "only instantiates the capped annotations for calendar buckets" do
    create_list(:dash_annotation, 8, happened_at: morning)
    loaded = []
    subscriber = lambda do |*, payload|
      loaded << payload[:record_count] if payload[:class_name] == "AhoyDashboard::Annotation"
    end

    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      described_class.call(range: range)
    end

    expect(loaded.sum).to eq(2)
  end

  it "starts weekly buckets on the dashboard's local Sunday" do
    saturday = create(:dash_annotation, happened_at: morning - 2.days)
    sunday = create(:dash_annotation, happened_at: morning - 1.day)
    monday = create(:dash_annotation, happened_at: morning)
    create(:dash_annotation, happened_at: morning + 1.day)

    expect(described_class.call(range: (morning - 2.days)..(morning + 2.days), bucket: :week).map(&:id))
      .to eq([saturday.id, sunday.id, monday.id])
  end

  it "keeps the repeated daylight-saving hour as two distinct buckets" do
    with_ahoy_dashboard_settings(:site, time_zone: "America/New_York") do
      zone = AhoyDashboard.time_zone
      times = %w[2026-11-01T01:10:00-04:00 2026-11-01T01:20:00-04:00
                 2026-11-01T01:10:00-05:00 2026-11-01T01:20:00-05:00]
      notes = times.map { |time| create(:dash_annotation, happened_at: zone.parse(time)) }

      expect(described_class.call(range: zone.local(2026, 11, 1).all_day, bucket: :hour).map(&:id))
        .to eq(notes.map(&:id))
    end
  end

  it "returns no annotations when the table has not been installed" do
    connection = AhoyDashboard::Annotation.connection
    connection.transaction(requires_new: true) do
      connection.execute("ALTER TABLE ahoy_dashboard_annotations RENAME TO unavailable_annotations")
      AhoyDashboardInstallation.forget_schema!

      expect(described_class.call(range: range)).to eq([])
      raise ActiveRecord::Rollback
    end
  ensure
    AhoyDashboardInstallation.forget_schema!
  end

  it "propagates an invalid query when the annotation table exists" do
    connection = AhoyDashboard::Annotation.connection
    connection.transaction(requires_new: true) do
      connection.execute("ALTER TABLE ahoy_dashboard_annotations RENAME COLUMN happened_at TO unavailable_happened_at")

      expect { described_class.call(range: range) }.to raise_error(ActiveRecord::StatementInvalid)
      raise ActiveRecord::Rollback
    end
  end
end
