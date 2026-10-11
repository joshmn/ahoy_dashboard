module AhoyDashboard
  module SavedQueries
    class UpdateCommand < AhoyDashboard::Command
      DUPLICATE_MESSAGE = "is already taken".freeze

      def initialize(record:, form:)
        @record = record
        @form = form
      end

      def call
        return broadcast(:invalid, form) if form.invalid?
        return copy_errors unless record.update(form.record_attributes)

        broadcast(:ok, record)
      rescue ActiveRecord::RecordNotUnique
        form.errors.add(:name, DUPLICATE_MESSAGE)
        broadcast(:duplicate, form)
      end

      private

      attr_reader :record, :form

      def copy_errors
        record.errors.messages.each do |attribute, messages|
          messages.each { |message| form.errors.add(attribute, message) }
        end

        broadcast(:invalid, form)
      end
    end
  end
end
