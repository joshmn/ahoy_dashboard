# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class SummariesController < BaseController
      FRAME = "dash_summary".freeze

      def show
        reading = SnapshotReadQuery.call(query: query, section: :summary) || ShowQuery.call(query: query, cards: false)
        @presenter = ShowPresenter.new(query: query, result: reading)
        @realtime = @presenter.realtime
      end
    end
  end
end
