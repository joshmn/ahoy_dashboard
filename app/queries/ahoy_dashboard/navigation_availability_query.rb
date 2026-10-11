# frozen_string_literal: true

module AhoyDashboard

  class NavigationAvailabilityQuery
    class << self
      def call
        new.call
      end
    end

    def call
      checks = sources.map do |key, relation|
        "EXISTS (#{relation.select("1").limit(1).to_sql}) AS #{key}"
      end
      return [] if checks.empty?

      Record.connection.select_one("SELECT #{checks.join(", ")}")
        .select { |_key, available| available }.keys.map(&:to_sym)
    end

    private

    def sources
      found = {}
      if Installation.installed?(:search_console)
        found[:search_console] = SearchConsoleTotal.all
        found[:keywords] = SearchConsoleKeyword.all
        found[:page_rows] = SearchConsoleRow.all
      end
      if Installation.installed?(:serp)
        found[:checks] = SerpCheck.all
        found[:results] = SerpResult.all
        found[:run_pages] = SerpRunPage.where(status: SerpRunPage.statuses.fetch("success")).where.not(response: nil)
        found[:rivals] = SerpSite.offset(1)
      end
      found[:ideas] = KeywordIdea.all if Installation.installed?(:keywords)
      found[:backlinks] = BacklinkDomain.all if Installation.installed?(:backlinks)
      found[:alerts] = AlertRule.live.available if Alerts.installed?
      found[:ai_answers] = AiVisibility::Answer.completed if Installation.installed?(:ai_visibility)
      found
    end
  end
end
