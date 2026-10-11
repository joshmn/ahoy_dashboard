require "rails_helper"
require "support/ahoy_dashboard/search_console"

RSpec.describe AhoyDashboard::SearchConsole::BackfillJob do
  it "runs on the low queue, behind the fresh window rather than in front of it" do
    expect(described_class.new.queue_name).to eq("low")
  end

  it "does nothing with nothing connected" do
    expect(AhoyDashboard::SearchConsole::BackfillCommand).not_to receive(:call)

    described_class.perform_now
  end

  it "does nothing while the integration is off" do
    search_console_disabled!
    create(:dash_google_account, :with_property)

    expect(AhoyDashboard::SearchConsole::BackfillCommand).not_to receive(:call)

    described_class.perform_now
  end

  it "does nothing without a property" do
    search_console_enabled!
    create(:dash_google_account)

    expect(AhoyDashboard::SearchConsole::BackfillCommand).not_to receive(:call)

    described_class.perform_now
  end

  it "hands a ready account to the command" do
    search_console_enabled!
    account = create(:dash_google_account, :with_property)

    expect(AhoyDashboard::SearchConsole::BackfillCommand).to receive(:call).with(account: account)

    described_class.perform_now
  end
end
