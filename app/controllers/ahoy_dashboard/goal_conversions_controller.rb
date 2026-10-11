module AhoyDashboard
  # The goal conversions card.
  #
  # Its own resource rather than a report, because it is not one: a report is a
  # card with tabs in a half-width column, and this is a full-width section with
  # three numbers per row. Singular, because there is one of it.
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
