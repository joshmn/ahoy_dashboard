require "rails_helper"

RSpec.describe AhoyDashboard::Goals::DestroyCommand do
  it "deletes a goal no funnel uses" do
    goal = create(:dash_goal)

    events = described_class.call(goal: goal)

    expect(events[:ok]).to eq(goal)
    expect(AhoyDashboard::Goal.exists?(goal.id)).to be(false)
  end

  it "refuses a goal a funnel is built on, before asking the database" do
    goal = create(:dash_goal)
    create(:dash_funnel, name: "Checkout", goals: [ goal, create(:dash_goal) ])
    expect(goal).not_to receive(:destroy!)

    events = described_class.call(goal: goal)

    expect(events[:in_use]).to eq([ goal, [ "Checkout" ] ])
  end

  it "refuses when a funnel takes the goal between the check and the delete" do
    goal = create(:dash_goal)
    create(:dash_funnel, name: "Checkout", goals: [ goal, create(:dash_goal) ])
    allow(goal.funnel_steps).to receive(:exists?).and_return(false)

    events = described_class.call(goal: goal)

    expect(events[:in_use]).to eq([ goal, [ "Checkout" ] ])
    expect(AhoyDashboard::Goal.exists?(goal.id)).to be(true)
  end

  it "lets any other database error through" do
    goal = create(:dash_goal)
    allow(goal).to receive(:destroy!).and_raise(ActiveRecord::StatementInvalid, "something else broke")

    expect { described_class.call(goal: goal) }.to raise_error(ActiveRecord::StatementInvalid, "something else broke")
  end
end
