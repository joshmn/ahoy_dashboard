# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::SavedQuerySentence do
  [nil, ""].each do |dimension|
    it "avoids exception-driven lookup for an absent #{dimension.inspect} grouping" do
      errors = []
      tracer = TracePoint.new(:raise) do |event|
        errors << event.raised_exception.class if event.raised_exception.is_a?(ActiveRecord::RecordNotFound)
      end
      tracer.enable { described_class.call(period: "30d", dimension: dimension) }

      expect(errors).to be_empty
    end
  end

  it "retains the sentence when no grouping was saved" do
    expect(described_class.call(period: "30d")).to eq("Unique visitors · last 30 days")
  end

  it "still ignores a retired grouping" do
    expect(described_class.call(period: "30d", dimension: "retired")).to eq("Unique visitors · last 30 days")
  end
end
