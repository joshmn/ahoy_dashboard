module AhoyDashboard
  module PageGroups
    class CreateCommand < AhoyDashboard::Command
      DUPLICATE_MESSAGE = "is already taken".freeze

      def initialize(form:)
        @form = form
      end

      def call
        return broadcast(:invalid, form) if form.invalid?

        record = AhoyDashboard::PageGroup.new(**form.record_attributes, position: next_position)
        return copy_errors(record) unless record.save

        broadcast(:ok, record)
      rescue ActiveRecord::RecordNotUnique
        form.errors.add(:name, DUPLICATE_MESSAGE)
        broadcast(:duplicate, form)
      end

      private

      attr_reader :form

      def copy_errors(record)
        record.errors.messages.each do |attribute, messages|
          messages.each { |message| form.errors.add(attribute, message) }
        end

        broadcast(:invalid, form)
      end

      def next_position
        (AhoyDashboard::PageGroup.maximum(:position) || 0) + 1
      end
    end
  end
end
