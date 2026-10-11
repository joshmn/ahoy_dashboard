module AhoyDashboard
  module Segments
    class UpdateCommand < AhoyDashboard::Command
      def initialize(segment:, form:)
        @segment = segment
        @form = form
      end

      def call
        return broadcast(:invalid, form) if form.invalid?

        segment.assign_attributes(form.record_attributes)
        return copy_errors unless segment.save

        broadcast(:ok, segment)
      rescue ActiveRecord::RecordNotUnique
        form.errors.add(:base, AhoyDashboard::SegmentForm::DUPLICATE_MESSAGE)
        broadcast(:duplicate, form)
      end

      private

      attr_reader :segment, :form

      def copy_errors
        segment.errors.messages.each do |attribute, messages|
          messages.each { |message| form.errors.add(attribute, message) }
        end

        broadcast(:invalid, form)
      end
    end
  end
end
