# frozen_string_literal: true

module AhoyDashboard
  module Counted
    class << self
      def call(count, noun:)
        "#{ActiveSupport::NumberHelper.number_to_delimited(count)} #{noun.pluralize(count)}"
      end
    end
  end
end
