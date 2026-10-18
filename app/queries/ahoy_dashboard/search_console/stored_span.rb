# frozen_string_literal: true

module AhoyDashboard

  module SearchConsole

    StoredSpan = Data.define(:first, :last, :rows) do
      def any?
        first.present?
      end

      def days
        (last - first).to_i + 1
      end
    end
  end
end
