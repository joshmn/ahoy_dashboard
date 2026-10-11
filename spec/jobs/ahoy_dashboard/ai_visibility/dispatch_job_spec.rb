require "rails_helper"
require "support/ahoy_dashboard/switches"

RSpec.describe AhoyDashboard::AiVisibility::DispatchJob do
  before { switch_on_ahoy_dashboard(:ai_visibility) }

  before do
    create(:dash_ai_assistant, :keyed)
    create(:dash_ai_prompt)
  end

  it "reports into the schedule's row" do
    expect(described_class.schedule_key).to eq("ai_visibility")
    expect(AhoyDashboard::Schedule.find("ai_visibility").job).to eq(described_class.name)
  end

  it "does nothing while switched off" do
    switch_off_ahoy_dashboard(:ai_visibility)

    described_class.perform_now

    expect(AhoyDashboard::AiVisibility::Run.count).to be_zero
  end

  it "starts a run when none has ever run" do
    expect { described_class.perform_now }.to have_enqueued_job(AhoyDashboard::AiVisibility::Prompts::RunJob).once

    expect(AhoyDashboard::AiVisibility::Run.last).to be_triggered_by_schedule
  end

  it "does nothing until the frequency has passed since the last run" do
    create(:dash_ai_run, started_at: 3.days.ago)

    expect { described_class.perform_now }.not_to have_enqueued_job(AhoyDashboard::AiVisibility::Prompts::RunJob)
    expect(AhoyDashboard::AiVisibility::Run.count).to eq(1)
  end

  it "starts the next run once the frequency has passed" do
    create(:dash_ai_run, started_at: 8.days.ago)

    expect { described_class.perform_now }.to have_enqueued_job(AhoyDashboard::AiVisibility::Prompts::RunJob).once
  end

  it "reads the frequency from settings" do
    AhoyDashboard::Setting.write(AhoyDashboard::AiVisibility::FREQUENCY_KEY, "daily")
    create(:dash_ai_run, started_at: 25.hours.ago)

    expect { described_class.perform_now }.to have_enqueued_job(AhoyDashboard::AiVisibility::Prompts::RunJob).once
  end

  it "counts a skipped run as the last run, so a run over the cap is not retried every hour" do
    create(:dash_ai_run, status: "skipped", started_at: 1.hour.ago)

    expect { described_class.perform_now }.not_to have_enqueued_job(AhoyDashboard::AiVisibility::Prompts::RunJob)
  end

  it "does not let a manual run push back the schedule" do
    create(:dash_ai_run, trigger: "manual", started_at: 1.hour.ago)

    expect { described_class.perform_now }.to have_enqueued_job(AhoyDashboard::AiVisibility::Prompts::RunJob)
  end
end
