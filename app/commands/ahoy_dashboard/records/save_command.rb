module AhoyDashboard
  module Records
    class SaveCommand < AhoyDashboard::Command
      def initialize(record:, form:, append: false)
        @record = record
        @form = form
        @append = append
      end

      def call
        return broadcast(:invalid, form) if form.invalid?

        record.assign_attributes(form.record_attributes)
        record.position = record.class.next_position if append && record.new_record?
        return broadcast(:ok, record) if record.save

        broadcast(:invalid, form.copy_errors_from(record))
      rescue ActiveRecord::RecordNotUnique
        form.add_duplicate_error
        broadcast(:invalid, form)
      end

      private

      attr_reader :record, :form, :append
    end
  end
end
