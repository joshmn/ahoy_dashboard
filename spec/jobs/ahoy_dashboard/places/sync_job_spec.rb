require "rails_helper"

RSpec.describe AhoyDashboard::Places::SyncJob do
  it "reports into the jobs screen under its own key" do
    expect(described_class.schedule_key).to eq("places")
  end

  it "runs on the quiet queue, because it is sixteen megabytes and nobody is waiting" do
    expect(described_class.queue_name).to eq("low")
  end

  it "lets a failed download fail the run rather than swallowing it" do
    switch_on_ahoy_dashboard(:places)
    source = instance_double(AhoyDashboard::Places::Source, month: nil)
    allow(source).to receive(:each_slice).and_raise(AhoyDashboard::Places::Error, "no list published")
    allow(AhoyDashboard::Places::Source).to receive(:new).and_return(source)

    expect { described_class.perform_now }.to raise_error(AhoyDashboard::Places::Error, "no list published")
  end
end
