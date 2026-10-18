module AhoyDashboard
  module Settings
    class GoalsController < AhoyDashboard::Settings::BaseController
      before_action :set_goal, only: [ :edit, :update, :destroy ]

      helper_method :event_names, :property_keys

      def index
        @goals = AhoyDashboard::GoalDecorator.wrap(AhoyDashboard::Goal.ordered.to_a)
        @conversions = conversions
      end

      def new
        @form = AhoyDashboard::GoalForm.new
      end

      def create
        @form = AhoyDashboard::GoalForm.new(goal_params)

        AhoyDashboard::Records::SaveCommand.call(record: AhoyDashboard::Goal.new, form: @form, append: true) do
          on(:ok) { redirect_to settings_goals_path, notice: "Goal saved." }
          on(:invalid) { |form| rejected(form, :new) }
        end
      end

      def edit
        @form = AhoyDashboard::GoalForm.from_record(@goal)
      end

      def update
        return move if nudge.present?

        @form = AhoyDashboard::GoalForm.new(goal_params)

        AhoyDashboard::Records::SaveCommand.call(record: @goal, form: @form) do
          on(:ok) { redirect_to settings_goals_path, notice: "Goal saved." }
          on(:invalid) { |form| rejected(form) }
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
        AhoyDashboard::Records::MoveCommand.call(record: @goal, direction: nudge)
        redirect_to settings_goals_path
      end

      def nudge
        params.dig(:goal, :nudge)
      end

      def goal_params
        params.require(:goal).permit(*AhoyDashboard::GoalForm::FIELDS)
      end

      def conversions
        rows = AhoyDashboard::GoalsQuery.call(scope: query.scope, limit: @goals.size.clamp(1, 1_000)).rows

        rows.index_by(&:label)
      rescue ActiveRecord::StatementInvalid
        {}
      end

      def event_names
        @event_names ||= AhoyDashboard::EventNamesQuery.call(scope: query.scope)
      end

      def property_keys
        @property_keys ||= AhoyDashboard::PropertyKeysQuery.call(scope: query.scope)
      end
    end
  end
end
