require "rails_helper"

RSpec.describe AhoyDashboard::Funnel do
  describe "validations" do
    it "needs a name" do
      funnel = build(:dash_funnel, name: " ")

      expect(funnel).not_to be_valid
      expect(funnel.errors[:name]).to be_present
    end

    it "refuses a name another funnel already has" do
      create(:dash_funnel, name: "Consults")
      funnel = build(:dash_funnel, name: "Consults")

      expect(funnel).not_to be_valid
      expect(funnel.errors[:name]).to be_present
    end

    it "holds the name unique at the database too" do
      create(:dash_funnel, name: "Consults")
      second = build(:dash_funnel, name: "Consults")

      expect { second.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "refuses a funnel with one step" do
      funnel = build(:dash_funnel, steps: 1)

      expect(funnel).not_to be_valid
      expect(funnel.errors[:funnel_steps].to_sentence).to include("at least 2 steps")
    end

    it "refuses a funnel with no steps at all" do
      funnel = build(:dash_funnel, steps: 0)

      expect(funnel).not_to be_valid
    end

    it "takes two steps" do
      expect(build(:dash_funnel)).to be_valid
    end

    it "strips a name down to what was typed" do
      funnel = create(:dash_funnel, name: "  Consults  ")

      expect(funnel.name).to eq("Consults")
    end
  end

  describe "the steps" do
    it "reads them in position order whatever order they were written in" do
      first = create(:dash_goal, event_name: "landed")
      second = create(:dash_goal, event_name: "asked")
      third = create(:dash_goal, event_name: "booked")

      funnel = create(:dash_funnel, goals: [ first, second, third ])
      funnel.funnel_steps.last.update!(position: 0)

      expect(funnel.reload.step_names).to eq([ "booked", "landed", "asked" ])
    end

    it "takes its steps with it when it goes" do
      funnel = create(:dash_funnel)

      expect { funnel.destroy! }.to change(AhoyDashboard::FunnelStep, :count).by(-2)
    end

    # The database says so as well, so a delete that never loads the record still
    # cannot leave orphaned steps behind.
    it "takes its steps with it on a delete that skips the callbacks" do
      funnel = create(:dash_funnel)

      expect { described_class.where(id: funnel.id).delete_all }
        .to change(AhoyDashboard::FunnelStep, :count).by(-2)
    end
  end

  describe "ordering" do
    it "reads by position, then by id" do
      second = create(:dash_funnel, position: 2)
      first = create(:dash_funnel, position: 1)

      expect(described_class.ordered.pluck(:id)).to eq([ first.id, second.id ])
    end
  end

  it "is its own id in a url" do
    funnel = create(:dash_funnel)

    expect(funnel.to_param).to eq(funnel.id.to_s)
  end
end
