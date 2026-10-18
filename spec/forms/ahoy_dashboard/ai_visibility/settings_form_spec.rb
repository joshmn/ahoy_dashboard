require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::SettingsForm do
  it "offers every frequency a run can be asked at, with its label" do
    expect(described_class.new.frequency_options).to eq([ %w[daily Daily], %w[weekly Weekly], %w[monthly Monthly] ])
  end
end
