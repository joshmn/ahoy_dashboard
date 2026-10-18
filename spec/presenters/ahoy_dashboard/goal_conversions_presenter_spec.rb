# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::GoalConversionsPresenter do
  let(:query) { AhoyDashboard::QueryForm.from_params({ period: "30d" }) }
  let!(:goal) { create(:dash_goal, event_name: "purchase", display_name: "Purchased", currency: "USD") }
  let(:goals) { AhoyDashboard::Goal.ordered.to_a }
  let(:result) { AhoyDashboard::GoalsQuery.call(scope: query.scope, goals: goals) }
  let(:presenter) { described_class.new(query: query, result: result, goals: goals) }

  it "uses supplied definitions for revenue labels" do
    expect(presenter.rows.first.revenue).to eq("$0.00")
  end

  it "keeps the empty state tied to the supplied definitions" do
    empty = described_class.new(query: query, result: result, goals: [])

    expect(empty.any_goals?).to eq(false)
  end

  it "presents prepared goal rows without database reads" do
    presenter
    statements = captured_sql(/\ASELECT/i, cached: true) do
      presenter.any_goals?
      presenter.rows.each do |row|
        row.goal
        row.revenue
        row.uniques
        row.total
        row.rate
      end
    end

    expect(statements).to be_empty
  end
end
