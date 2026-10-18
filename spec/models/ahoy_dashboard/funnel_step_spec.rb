require "rails_helper"

RSpec.describe AhoyDashboard::FunnelStep do
  let(:funnel) { create(:dash_funnel) }

  it "answers to its goal's name" do
    goal = create(:dash_goal, display_name: "Consult booked")
    step = create(:dash_funnel_step, funnel: funnel, goal: goal, position: 9)

    expect(step.name).to eq("Consult booked")
  end

  it "reads by position, then by id" do
    expect(funnel.funnel_steps.ordered.pluck(:position)).to eq([ 1, 2 ])
  end

  describe "the same goal twice" do
    it "is refused by the database" do
      repeat = build(:dash_funnel_step, funnel: funnel, goal: funnel.goals.first, position: 9)

      expect { repeat.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "is fine in a different funnel" do
      other = create(:dash_funnel, goals: [ funnel.goals.first, create(:dash_goal) ])

      expect(other.goals).to include(funnel.goals.first)
    end
  end

  describe "two steps in one slot" do
    it "refuses a duplicate slot immediately" do
      expect { create(:dash_funnel_step, funnel: funnel, goal: create(:dash_goal), position: 1) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "moves through unused slots without weakening uniqueness" do
      first, second = funnel.funnel_steps.to_a

      AhoyDashboard::FunnelSteps::MoveCommand.call(funnel: funnel, step_id: first.id, direction: "down")

      expect(funnel.funnel_steps.reload.pluck(:id)).to eq([second.id, first.id])
    end

    it "moves a later step up while preserving contiguous positions" do
      second = funnel.funnel_steps.last

      AhoyDashboard::FunnelSteps::MoveCommand.call(funnel: funnel, step_id: second.id, direction: "up")

      expect(funnel.funnel_steps.reload.pluck(:id, :position)).to eq([[second.id, 1], [funnel.funnel_steps.last.id, 2]])
    end
  end

  describe "deleting the goal underneath" do
    it "is refused while the goal is still a step" do
      goal = funnel.goals.first

      expect { goal.destroy }.to raise_error(ActiveRecord::StatementInvalid) { |error|
        expect(error.cause).to be_a(PG::ForeignKeyViolation).or be_a(PG::RestrictViolation)
      }
    end

    it "is fine for a goal no funnel uses" do
      spare = create(:dash_goal)

      expect { spare.destroy }.to change(AhoyDashboard::Goal, :count).by(-1)
    end
  end
end
