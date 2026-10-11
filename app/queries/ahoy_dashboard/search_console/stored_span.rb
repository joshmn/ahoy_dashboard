# frozen_string_literal: true

module AhoyDashboard

  module SearchConsole

    class StoredSpan
      attr_reader :first, :last, :rows

      def initialize(first:, last:, rows:)
        @first = first
        @last = last
        @rows = rows
      end

      def any?
        first.present?
      end

      def days
        (last - first).to_i + 1
      end
    end
  end
end
