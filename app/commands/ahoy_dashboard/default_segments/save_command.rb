module AhoyDashboard
  module DefaultSegments
    class SaveCommand < AhoyDashboard::Command
      NAME = "Default".freeze

      def initialize(filters:)
        @filters = filters
      end

      def call
        return broadcast(:no_filters) if filters.empty?

        segment = nil
        AhoyDashboard::Segment.transaction do
          segment = AhoyDashboard::Segment.find_by(applied_by_default: true) || build
          segment.filters = filters.to_param
          segment.applied_by_default = true
          segment.save!
        end

        broadcast(:ok, segment)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        broadcast(:invalid)
      end

      private

      attr_reader :filters

      def build
        AhoyDashboard::Segment.new(name: free_name, position: next_position)
      end

      def free_name
        taken = AhoyDashboard::Segment.where("name like ?", "#{NAME}%").pluck(:name)
        return NAME unless taken.include?(NAME)

        2.step.lazy.map { |number| "#{NAME} #{number}" }.find { |name| taken.exclude?(name) }
      end

      def next_position
        (AhoyDashboard::Segment.maximum(:position) || 0) + 1
      end
    end
  end
end
