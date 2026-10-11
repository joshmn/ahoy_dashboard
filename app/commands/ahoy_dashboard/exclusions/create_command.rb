module AhoyDashboard
  module Exclusions
    class CreateCommand < AhoyDashboard::Command
      def initialize(form:)
        @form = form
      end

      def call
        return broadcast(:invalid, form) if form.invalid?

        exclusion = AhoyDashboard::Exclusion.new(form.record_attributes)
        return copy_errors(exclusion) unless exclusion.save

        broadcast(:ok, exclusion)
      rescue ActiveRecord::RecordNotUnique
        duplicate
      end

      private

      attr_reader :form

      def copy_errors(exclusion)
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
