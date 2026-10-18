require "rails_helper"

RSpec.describe AhoyDashboard::FunnelForm do
  describe "#goal_options" do
    it "offers every goal by name, in the order the goals screen lists them" do
      second = create(:dash_goal, event_name: "paid", position: 2)
      first = create(:dash_goal, :pageview, path_pattern: "/pricing", position: 1)

      expect(described_class.new.goal_options).to eq([ [ "/pricing", first.id ], [ "paid", second.id ] ])
    end

    it "reads the goals once however many step slots draw them" do
      create(:dash_goal)
      form = described_class.new
      queries = captured_sql("ahoy_dashboard_goals", cached: true) { 3.times { form.goal_options } }

      expect(queries.size).to eq(1)
    end
  end
end
