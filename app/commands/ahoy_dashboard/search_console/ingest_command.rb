# frozen_string_literal: true

module AhoyDashboard
  module SearchConsole
    class IngestCommand < AhoyDashboard::Command
      Result = Data.define(:dates, :rows, :keywords, :totals)

      QUOTA_MESSAGE = "Google's Search Console quota is used up. The next run picks up where this one left off.".freeze
      UNREACHABLE_MESSAGE = "Search Console did not answer. Nothing was lost; the next run covers the same days.".freeze
      REFUSED_MESSAGE = "Some days came back with rows the database would not store, and those days were " \
                        "skipped. Everything else in the window was saved.".freeze
      PERMISSION_MESSAGE = "This Google account can no longer read %<property>s in Search Console. Give it " \
                           "access again there, or pick another property.".freeze

      def initialize(account: nil, dates: nil, data_state: SearchConsole::DATA_STATE_FINAL, stamp: true)
        @account = account
        @dates = dates || SearchConsole.ingest_dates
        @data_state = data_state
        @stamp = stamp
        @refused = []
      end

      def call
        return broadcast(:skipped, "search console is not configured") unless SearchConsole.enabled?
        return broadcast(:skipped, "google is not connected") unless account&.connected?
        return broadcast(:skipped, "no search console property is selected") unless account.property_selected?

        Properties::AdoptCommand.call(account: account, property_uri: account.property_uri)

        result = absorb_snapshots
        return refused! if refused.any?

        finish
        broadcast(:ok, result)
      rescue QuotaError => e
        account.record_error!(QUOTA_MESSAGE)
        broadcast(:rate_limited, e.message)
      rescue AuthError => e
        account.record_error!(RefreshTokenService::REFUSED_MESSAGE) if account.last_error.blank?
        broadcast(:failed, e.message)
      rescue PermissionError => e
        account.record_error!(format(PERMISSION_MESSAGE, property: account.property_label))
        broadcast(:failed, e.message)
      rescue Error => e
        account.record_error!(UNREACHABLE_MESSAGE)
        broadcast(:failed, e.message)
      end

      private

      attr_reader :dates, :data_state, :stamp, :refused

      def account
        @account ||= GoogleAccount.current
      end

      def absorb_snapshots
        counts = dates.map { |date| absorb_snapshot(date) }
        Result.new(dates: dates, rows: counts.sum(&:rows),
                   keywords: counts.sum(&:keywords), totals: counts.sum(&:totals))
      end

      def absorb_snapshot(date)
        rows = fetch(date, SearchConsole::QUERY_DIMENSIONS + SearchConsole::SLICE_DIMENSIONS)
        keywords = fetch(date, SearchConsole::KEYWORD_DIMENSIONS + SearchConsole::SLICE_DIMENSIONS)
        totals = fetch(date, SearchConsole::SLICE_DIMENSIONS)
        absorb_day(date, rows, keywords, totals)
      end

      def absorb_day(date, rows, keywords, totals)
        ReplaceDayService.new(date: date, rows: rows, keywords: keywords, totals: totals).call
      rescue ActiveRecord::StatementInvalid, ActiveModel::RangeError => e
        refused << date
        Rails.logger.warn("search console could not store #{date}: #{e.message.lines.first.to_s.strip}")
        SnapshotCounts.new
      end

      def fetch(date, dimensions)
        AnalyticsService.call(
          account: account, dates: [date], dimensions: dimensions, data_state: data_state
        ).fetch(date)
      end

      def finish
        return unless stamp

        account.update_columns(synced_at: Time.current)
        account.clear_error!
      end

      def refused!
        account.update_columns(synced_at: Time.current) if stamp
        account.record_error!(REFUSED_MESSAGE)
        broadcast(:failed, "the database refused rows for #{refused.uniq.sort.join(", ")}")
      end
    end
  end
end
