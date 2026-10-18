# frozen_string_literal: true

module AhoyDashboard

  module SearchConsole

    class PageContextQuery
      class << self
        def call(**options)
          new(**options).call
        end
      end

      def initialize(range:, countries: false, history: false)
        @range = range
        @countries = countries
        @history = history
      end

      def call
        return PageContext.new unless SearchConsole.installed?

        account = GoogleAccount.current
        PageContext.new(account: account, countries: countries ? country_codes : [],
          stored_span: (stored_span if history && !(account && account.ready?)))
      end

      private

      attr_reader :range, :countries, :history

      def country_codes
        SearchConsoleTotal.in_range(range).where.not(country: Slice::UNKNOWN)
          .group(:country).order(Sums::RANKING, :country).pluck(:country)
      end

      def stored_span
        totals = SearchConsoleTotal.reorder(nil).reselect(Arel.sql("min(date) AS first, max(date) AS last"))
        rows = SearchConsoleRow.reorder(nil).reselect(Arel.sql("min(date) AS first, max(date) AS last, count(*) AS count"))
        values = SearchConsoleRow.connection.select_one(<<~SQL)
          SELECT coalesce(t.first, r.first) AS first, coalesce(t.last, r.last) AS last, r.count
          FROM (#{totals.to_sql}) t CROSS JOIN (#{rows.to_sql}) r
        SQL
        type = SearchConsoleTotal.type_for_attribute("date")
        StoredSpan.new(first: type.cast(values.fetch("first")), last: type.cast(values.fetch("last")),
          rows: values.fetch("count").to_i)
      end
    end
  end
end
