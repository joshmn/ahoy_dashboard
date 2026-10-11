module AhoyDashboard
  module Segments
    class CreateCommand < AhoyDashboard::Command
      def initialize(form:)
        @form = form
      end

      def call
        return broadcast(:invalid, form) if form.invalid?

        segment = AhoyDashboard::Segment.new(form.record_attributes.merge(position: next_position))
        return copy_errors(segment) unless segment.save

        broadcast(:ok, segment)
      rescue ActiveRecord::RecordNotUnique
        form.errors.add(:base, AhoyDashboard::SegmentForm::DUPLICATE_MESSAGE)
        broadcast(:duplicate, form)
      end

      private

      attr_reader :form

      def next_position
        (AhoyDashboard::Segment.maximum(:position) || 0) + 1
      end

      def copy_errors(segment)
        segment.errors.messages.each do |attribute, messages|
          messages.each { |message| form.errors.add(attribute, message) }
        end

        broadcast(:invalid, form)
      end
    end
  end
end
