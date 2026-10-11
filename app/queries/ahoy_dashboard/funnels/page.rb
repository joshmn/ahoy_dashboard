# frozen_string_literal: true

module AhoyDashboard

  module Funnels

    class Page
      attr_reader :readings, :total, :page, :pages

      def initialize(readings:, total:, page:, pages:)
        @readings = readings
        @total = total
        @page = page
        @pages = pages
      end
    end
  end
end
