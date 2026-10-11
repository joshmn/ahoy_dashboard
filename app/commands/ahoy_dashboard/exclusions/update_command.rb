module AhoyDashboard
  module Exclusions
    class UpdateCommand < AhoyDashboard::Command
      def initialize(exclusion:, form:)
        @exclusion = exclusion
        @form = form
      end

      def call
        return broadcast(:invalid, form) if form.invalid?

        exclusion.assign_attributes(form.record_attributes)
        return copy_errors unless exclusion.save

        broadcast(:ok, exclusion)
      rescue ActiveRecord::RecordNotUnique
        duplicate
      end

      private

      attr_reader :exclusion, :form

      def copy_errors
        return duplicate if exclusion.errors.of_kind?(:name, :taken)

        exclusion.errors.messages.each do |attribute, messages|
          messages.each { |message| form.errors.add(attribute, message) }
        end

        broadcast(:invalid, form)
      end

      def duplicate
        form.errors.add(:base, AhoyDashboard::ExclusionForm::DUPLICATE_MESSAGE)
        broadcast(:duplicate, form)
      end
    end
  end
end
