# frozen_string_literal: true

require "rails_helper"

module AhoyDashboard

  module Spec

    class CompatibilityJobRun < AhoyDashboard::Record
      self.table_name = "ahoy_dashboard_job_runs"

      enum(:status, { unknown: 0, running: 1, ok: 2 }, validate: true, prefix: true)
    end
  end
end

RSpec.describe AhoyDashboard::Compatibility::EnumType do
  let(:model) { AhoyDashboard::Spec::CompatibilityJobRun }

  it "keeps the native mapping for database writes" do
    record = model.create!(key: "compatibility_enum", status: :running)

    expect(record.reload.status).to eq("running")
  end

  it "keeps prefixed enum predicates" do
    expect(model.new(status: :running)).to be_status_running
  end

  it "reports invalid values as validation errors instead of raising on assignment" do
    record = model.new(key: "compatibility_enum", status: :invalid)
    record.valid?

    expect(record.errors[:status]).to include("is not included in the list")
  end

  it "casts stored integer values back to their names" do
    expect(model.new(status: 2).status).to eq("ok")
  end
end
