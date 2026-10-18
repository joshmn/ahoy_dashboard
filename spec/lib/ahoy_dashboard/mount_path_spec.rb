require "rails_helper"

RSpec.describe "AhoyDashboard.mount_path" do
  it "says where the engine is mounted" do
    expect(AhoyDashboard.mount_path).to eq("/telemetry")
    expect(AhoyDashboard.mount_path("settings/serp_keywords")).to eq("/telemetry/settings/serp_keywords")
  end
end
