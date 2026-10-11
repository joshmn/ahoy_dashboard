# frozen_string_literal: true

module AhoyDashboard

  module Compatibility

    class EnumType < ActiveRecord::Enum::EnumType
      def assert_valid_value(value)
        value
      end
    end
  end
end
