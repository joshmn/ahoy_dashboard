module AhoyDashboard
  module Settings
    class GoalsController < AhoyDashboard::BaseController
      before_action :set_goal, only: [ :edit, :update, :destroy ]

      helper_method :event_names, :property_keys

      def index
        @goals = AhoyDashboard::Goal.ordered.to_a
        @conversions = conversions
        # Deleting asks in the row rather than in a dialog, so the thing being
        # deleted stays on screen while the question is answered. A parameter on
        # the index rather than a verb of its own, and the link works with the
        # JavaScript off because it is a page.
        @confirming = params[:confirm].presence
      end

      def new
        @form = AhoyDashboard::GoalForm.new
      end

      def create
        @form = AhoyDashboard::GoalForm.new(goal_params)

        AhoyDashboard::Goals::CreateCommand.call(form: @form) do
          on(:ok) { redirect_to settings_goals_path, notice: "Goal saved." }
          on(:invalid) { |form| rejected(form, :new) }
          on(:duplicate) { |form| rejected(form, :new) }
        end
      end

      def edit
        @form = AhoyDashboard::GoalForm.from_record(@goal)
      end

      # A nudge is this goal's position and nothing else, so it is the same
      # update as any other edit to the goal rather than a resource of its own.
      def update
        return move if nudge.present?

        @form = AhoyDashboard::GoalForm.new(goal_params)

        AhoyDashboard::Goals::UpdateCommand.call(goal: @goal, form: @form) do
          on(:ok) { redirect_to settings_goals_path, notice: "Goal saved." }
          on(:invalid) { |form| rejected(form, :edit) }
          on(:duplicate) { |form| rejected(form, :edit) }
        end
      end

      def destroy
        AhoyDashboard::Goals::DestroyCommand.call(goal: @goal) do
          on(:ok) { redirect_to settings_goals_path, notice: "Goal deleted." }
          on(:in_use) do |goal, funnels|
            redirect_to settings_goals_path,
              alert: "#{goal.name} is a step in #{funnels.to_sentence}. Take it out of " \
                     "#{"that funnel".pluralize(funnels.size)} first."
          end
        end
      end

      private

      def set_goal
        @goal = AhoyDashboard::Goal.find(params[:id])
      end

      def move
        AhoyDashboard::Goals::MoveCommand.call(goal: @goal, direction: nudge) do
          on(:ok) { redirect_to settings_goals_path }
          on(:nothing_to_do) { redirect_to settings_goals_path }
        end
      end

      def rejected(form, template)
        @form = form
        render template, status: :unprocessable_entity
      end

      def nudge
        params.dig(:goal, :nudge)
      end

      def goal_params
        params.require(:goal).permit(*AhoyDashboard::GoalForm::FIELDS)
      end

      # How each goal has actually been doing, keyed by name, so the list is not
      # only a set of definitions. A goal that has never fired still gets a row
      # and reads zero, which is an answer rather than an absence.
      def conversions
        rows = AhoyDashboard::GoalsQuery.call(scope: query.scope, limit: @goals.size.clamp(1, 1_000)).rows

        rows.index_by(&:label)
      rescue ActiveRecord::StatementInvalid
        {}
      end

      def event_names
        @event_names ||= AhoyDashboard::EventNamesQuery.call(scope: query.scope)
      end

      # PropertyKeysQuery already unions the allowlist with what it discovers, in
      # the operator's chosen order.
      def property_keys
        @property_keys ||= AhoyDashboard::PropertyKeysQuery.call(scope: query.scope)
      end
    end
  end
end
