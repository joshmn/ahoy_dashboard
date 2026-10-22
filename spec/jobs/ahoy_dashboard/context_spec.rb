# frozen_string_literal: true

require "rails_helper"

class DashboardContextJob < AhoyDashboard::Job
  def perform(setting)
    AhoyDashboard::Setting.write("job.result", setting.value)
  end
end

RSpec.describe "Dashboard job context" do
  include_context "with dashboard sites"

  before do
    %w[first second].each do |site|
      within_site(site) { AhoyDashboard::Setting.create!(id: 42, key: "example", value: site) }
    end
  end

  it "resolves serialized records and writes results in the originating site" do
    payload = within_site("first") do
      job = DashboardContextJob.perform_later(AhoyDashboard::Setting.find(42))
      job.serialize
    end
    within_site("second") { ActiveJob::Base.execute(payload) }

    expect(within_site("first") { AhoyDashboard::Setting.read("job.result") }).to eq("first")
  end

  it "does not write to the worker's previous site" do
    payload = within_site("first") do
      DashboardContextJob.perform_later(AhoyDashboard::Setting.find(42)).serialize
    end
    within_site("second") { ActiveJob::Base.execute(payload) }

    expect(within_site("second") { AhoyDashboard::Setting.read("job.result") }).to be_nil
  end

  it "runs scheduled job bookkeeping in its site" do
    payload = within_site("first") { AhoyDashboard::Alerts::RunJob.perform_later.serialize }
    within_site("second") { ActiveJob::Base.execute(payload) }

    expect(within_site("first") { AhoyDashboard::JobRun.for("alerts").status }).to eq("ok")
  end

  it "supports a tick invoked directly inside a site" do
    within_site("first") { AhoyDashboard::TickJob.perform_now }

    expect(within_site("second") { AhoyDashboard::JobRun.count }).to eq(0)
  end

  it "refuses queued work whose site identity is missing" do
    payload = within_site("first") { DashboardContextJob.new(AhoyDashboard::Setting.find(42)).serialize }
    payload.delete("dashboard_context")

    expect { within_site("second") { ActiveJob::Base.execute(payload) } }.to raise_error(AhoyDashboard::Context::Missing)
  end

  it "restores the previous context after a failed job" do
    payload = within_site("first") { DashboardContextJob.new(nil).serialize }
    current = within_site("second") do
      begin
        ActiveJob::Base.deserialize(payload).perform_now
      rescue NoMethodError
        AhoyDashboard::Context.current
      end
    end

    expect(current).to eq("second")
  end

  it "refuses enqueueing without a site" do
    expect { AhoyDashboard::Alerts::RunJob.perform_later }.to raise_error(AhoyDashboard::Context::Missing)
  end

  it "keeps the original context when a job is queued again" do
    job = within_site("first") { DashboardContextJob.perform_later(AhoyDashboard::Setting.find(42)) }
    within_site("second") { job.enqueue }

    expect(job.serialize.fetch("dashboard_context")).to eq("first")
  end

  it "refuses site-specific jobs after context support is removed" do
    payload = within_site("first") { DashboardContextJob.new(AhoyDashboard::Setting.find(42)).serialize }
    AhoyDashboard.config.context = nil

    expect { ActiveJob::Base.execute(payload) }.to raise_error(AhoyDashboard::Context::Missing)
  end
end
