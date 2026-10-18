# frozen_string_literal: true

module AhoyDashboard
  module SearchTerm
    MAX_LENGTH = 100

    class << self
      def clean(value)
        value.to_s.strip[0, MAX_LENGTH].to_s
      end
    end
  end
end
