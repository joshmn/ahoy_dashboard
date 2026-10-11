module AhoyDashboard
  module Assistant
    class WithheldDimensionsForm < AhoyDashboard::Form
      Choice = Data.define(:key, :label, :group)

      attribute :keys, default: -> { [] }

      validate :keys_are_offered

      def self.current
        new(keys: Assistant.withheld_keys)
      end

      def self.choices
        properties = begin
          AhoyDashboard::Property.surfaced.map(&:dimension)
        rescue ActiveRecord::ActiveRecordError
          []
        end

        (AhoyDashboard::Dimension.all + properties).uniq(&:key)
          .map { |dimension| Choice.new(key: dimension.key, label: dimension.label, group: dimension.group) }
      end

      def choices
        @choices ||= self.class.choices
      end

      def groups
        choices.group_by(&:group)
      end

      def chosen
        Array(keys).map(&:to_s).reject(&:blank?).uniq
      end

      # A property that has since been taken off the surfaced list is not
      # offered, so it cannot be ticked, and a save that dropped it would hand
      # it back to the assistant without anybody having chosen that.
      def to_store
        offered = choices.map(&:key)

        (chosen + (Assistant.withheld_keys - offered)).uniq.sort
      end

      private

      def keys_are_offered
        unknown = chosen - choices.map(&:key)
        return if unknown.empty?

        errors.add(:keys, "include #{unknown.to_sentence}, which the dashboard does not have")
      end
    end
  end
end
