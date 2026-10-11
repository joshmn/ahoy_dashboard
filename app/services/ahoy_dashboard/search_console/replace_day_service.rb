# frozen_string_literal: true

module AhoyDashboard

  module SearchConsole

    class ReplaceDayService
      def initialize(date:, rows:, keywords:, totals:)
        @date = date
        @rows = rows
        @keywords = keywords
        @totals = totals
        @now = Time.current
      end

      def call
        SearchConsoleRow.transaction(requires_new: true) do
          SearchConsoleDay.absorb([date], now: now)
          SearchConsoleDay.where(date: date).lock.load
          [SearchConsoleRow, SearchConsoleKeyword, SearchConsoleTotal].each do |model|
            model.where(date: date).delete_all
          end
          SnapshotCounts.new(rows: SearchConsoleRow.absorb(rows.map { |row| breakdown_attributes(row) }),
                             keywords: SearchConsoleKeyword.absorb(keywords.map { |row| keyword_attributes(row) }),
                             totals: SearchConsoleTotal.absorb(totals.map { |row| total_attributes(row) }))
        end
      end

      private

      attr_reader :date, :rows, :keywords, :totals, :now

      def breakdown_attributes(row)
        query, page, device, country = row.keys
        metrics(row).merge(query: query.to_s, page: page.to_s, device: device.to_s.downcase,
                           country: country.to_s.downcase)
      end

      def keyword_attributes(row)
        query, device, country = row.keys
        metrics(row).merge(query: query.to_s, device: device.to_s.downcase, country: country.to_s.downcase)
      end

      def total_attributes(row)
        device, country = row.keys
        metrics(row).merge(device: device.to_s.downcase, country: country.to_s.downcase)
      end

      def metrics(row)
        {date: date, clicks: row.clicks.round, impressions: row.impressions.round,
         ctr: row.ctr, position: row.position, created_at: now, updated_at: now}
      end
    end
  end
end
