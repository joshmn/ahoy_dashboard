require "rails_helper"

RSpec.describe AhoyDashboard::Places::SyncJob do
  it "reports into the jobs screen under its own key" do
    expect(described_class.schedule_key).to eq("places")
  end

  it "runs on the quiet queue, because it is sixteen megabytes and nobody is waiting" do
    expect(described_class.queue_name).to eq("low")
  end

  # A job that swallowed the failure would land on the jobs screen as "Ran" and
  # the place list would go on being however stale it already was.
  it "lets a failed download fail the run rather than swallowing it" do
    allow(AhoyDashboard::Places::SyncCommand).to receive(:call) do |&block|
      router = AhoyDashboard::Command::Router.new(eval("self", block.binding))
      router.instance_eval(&block)
      router.fire(:failed, AhoyDashboard::Places::Error.new("no list published"))
    end

    expect { described_class.perform_now }.to raise_error(AhoyDashboard::Places::Error, "no list published")
  end
end
