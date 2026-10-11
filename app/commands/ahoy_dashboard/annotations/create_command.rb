module AhoyDashboard
  module Annotations
    class CreateCommand < AhoyDashboard::Command
      DUPLICATE_MESSAGE = "is already taken".freeze

      def initialize(form:)
        @form = form
      end

      def call
        return broadcast(:invalid, form) if form.invalid?

        record = AhoyDashboard::Annotation.new(**form.record_attributes)
        return copy_errors(record) unless record.save

        broadcast(:ok, record)
      rescue ActiveRecord::RecordNotUnique
        form.errors.add(:label, DUPLICATE_MESSAGE)
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
    end
  end
end
