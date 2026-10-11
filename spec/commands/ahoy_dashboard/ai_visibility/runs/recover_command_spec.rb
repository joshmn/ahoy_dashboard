require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::Runs::RecoverCommand do
  it "requeues stale reservations that have not started an external request" do
    answer = create(:dash_ai_answer, status: :pending, updated_at: 7.hours.ago)

    expect { described_class.call }
      .to have_enqueued_job(AhoyDashboard::AiVisibility::Prompts::RunJob)
      .with(answer.run_id, answer.prompt_id, answer.assistant, answer.model)
  end

  it "marks interrupted requests failed without sending an uncertain request twice" do
    answer = create(:dash_ai_answer, status: :processing, updated_at: 7.hours.ago)

    described_class.call

    expect(answer.reload).to have_attributes(status: "failed", error: described_class::INTERRUPTED)
  end

  it "does not requeue interrupted external requests" do
    create(:dash_ai_answer, status: :processing, updated_at: 7.hours.ago)

    expect { described_class.call }.not_to have_enqueued_job(AhoyDashboard::AiVisibility::Prompts::RunJob)
  end

  it "leaves recent claims with their current worker" do
    answer = create(:dash_ai_answer, status: :processing)

    described_class.call

    expect(answer.reload).to be_processing
  end
end
