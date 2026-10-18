require "rails_helper"

RSpec.describe AhoyDashboard::GoalDecorator, type: :decorator do
  it "names the kind the way the goal form offers it" do
    expect(decorate(build(:dash_goal)).kind_label).to eq("Custom event")
    expect(decorate(build(:dash_goal, :pageview)).kind_label).to eq("Pageview")
    expect(AhoyDashboard::GoalForm.new.kind_options).to eq(described_class::KIND_LABELS.to_a)
  end

  it "shows what the goal matches on: the event name, or the path for a pageview" do
    expect(decorate(build(:dash_goal, event_name: "signed_up")).matcher).to eq("signed_up")
    expect(decorate(build(:dash_goal, :pageview, path_pattern: "/pricing")).matcher).to eq("/pricing")
  end
end
