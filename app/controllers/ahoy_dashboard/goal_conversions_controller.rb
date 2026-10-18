module AhoyDashboard
  class GoalConversionsController < AhoyDashboard::BaseController
    def show
      snapshot = Dashboards::SnapshotReadQuery.call(query: query, section: :goals)
      goals = snapshot ? snapshot.goals : AhoyDashboard::Goal.ordered.to_a
      result = snapshot ? snapshot.goal_conversions : AhoyDashboard::GoalsQuery.call(
        scope: query.scope, limit: AhoyDashboard::GoalConversionsPresenter::ROWS, goals: goals)
      @presenter = AhoyDashboard::GoalConversionsPresenter.new(
        query: query,
        goals: goals,
        result: result
      )
    end
  end
end
