module AhoyDashboard
  module SearchConsole
    class PropertyForm < AhoyDashboard::Form
      attribute :property_uri, :string

      validates :property_uri, presence: { message: "Pick the property this site is verified under." }
      validate :one_of_the_choices

      def initialize(choices: [], **attributes)
        @choices = Array(choices)
        super(**attributes)
      end

      attr_reader :choices

      private

      # Search Analytics answers 403 for a property this account cannot read, and
      # a saved 403 is a sync that fails every night with no clue why. The picker
      # already lists only what Google offered, so anything else is a hand typed
      # value and gets refused here.
      def one_of_the_choices
        return if property_uri.blank? || choices.empty?
        return if choices.include?(property_uri)

        errors.add(:property_uri, "That property is not one Google says this account can read.")
      end
    end
  end
end
