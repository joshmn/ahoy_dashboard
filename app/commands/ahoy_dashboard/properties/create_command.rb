module AhoyDashboard
  module Properties
    # Nothing about adding a key changes what gets recorded. It only puts the key on
    # the list the dashboard offers, at the end of it, because the order the keys
    # were added in is the only order the operator gets to choose.
    class CreateCommand < AhoyDashboard::Command
      DUPLICATE_MESSAGE = "is already on the list".freeze

      def initialize(form:)
        @form = form
      end

      def call
        return broadcast(:invalid, form) if form.invalid?

        property = AhoyDashboard::Property.new(key: form.key, label: form.label, position: next_position)
        return copy_errors(property) unless property.save

        broadcast(:ok, property)
      rescue ActiveRecord::RecordNotUnique
        form.errors.add(:key, DUPLICATE_MESSAGE)
        broadcast(:duplicate, form)
      end

      private

      attr_reader :form

      def next_position
        (AhoyDashboard::Property.maximum(:position) || 0) + 1
      end

      def copy_errors(property)
        property.errors.messages.each do |attribute, messages|
          messages.each { |message| form.errors.add(attribute, message) }
        end

        broadcast(:invalid, form)
      end
    end
  end
end
