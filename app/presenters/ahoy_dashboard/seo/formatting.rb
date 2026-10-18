module AhoyDashboard
  module Seo
    module Formatting
      DASH = "&mdash;".html_safe
      HOST = %r{\Ahttps?://[^/]+}

      class << self
        def url_path(url)
          return nil if url.blank?

          url.to_s.sub(HOST, "").presence || "/"
        end
      end

      def percent(value, places: 0)
        "#{(value.to_f * 100).round(places)}%"
      end

      def percentage(value)
        percent(value, places: 1)
      end

      def number(value)
        ActiveSupport::NumberHelper.number_to_delimited(value.to_i)
      end

      def decimal(value, places: 1)
        value.nil? ? DASH : value.to_f.round(places).to_s
      end

      def place(value)
        value.to_f.round(1)
      end

      def money(value)
        ActiveSupport::NumberHelper.number_to_currency(value.to_f)
      end

      def signed(value, places: 0)
        return DASH if value.nil?

        rounded = places.zero? ? value.to_i : value.to_f.round(places)
        return "level" if rounded.zero?

        "#{rounded.positive? ? "+" : ""}#{rounded}"
      end

      def tone_for(value)
        return nil if value.nil? || value.to_f.zero?

        value.to_f.positive? ? :good : :bad
      end

      def truncate(value, length: 60)
        value.to_s.truncate(length)
      end

      def path_of(url)
        Formatting.url_path(url) || DASH
      end

      def pluralize(count, word)
        helpers.pluralize(count, word)
      end

      def when_label(time)
        AhoyDashboard::DateFormat.ago(time)
      end

      def on_label(date)
        AhoyDashboard::DateFormat.short(date, zone: time_zone)
      end

      def local_date(value)
        AhoyDashboard::DateFormat.local(value, zone: time_zone)
      end

      private

      def time_zone
        @time_zone ||= AhoyDashboard.time_zone
      end

      def helpers
        ActionController::Base.helpers
      end
    end
  end
end
