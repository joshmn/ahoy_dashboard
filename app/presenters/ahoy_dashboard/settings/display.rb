module AhoyDashboard
  module Settings
    module Display
      SERP_LABELS = {
        "fake" => "Sample data",
        "serpapi" => "SerpApi",
        "dataforseo" => "DataForSEO",
        "searchapi" => "SearchApi"
      }.freeze

      ASSISTANT_OFF = "The assistant is off. Turn it on under Settings, Features.".freeze
      AI_VISIBILITY_OFF = "AI visibility is off. Turn it on under Settings, Features.".freeze

      module_function

      def short_date(value, today: Time.current.in_time_zone(AhoyDashboard.time_zone).to_date)
        return nil if value.nil?

        date = value.to_date
        date.year == today.year ? date.strftime("%b %-d") : date.strftime("%b %-d, %Y")
      end

      # One day reads as one day. "Jun 3 to Jun 3" is a range nobody wrote on
      # purpose and it makes a single missing day look like an interval.
      def date_span(first, last)
        return short_date(first) if first == last

        "#{short_date(first)} to #{short_date(last)}"
      end

      def serp_label(name)
        SERP_LABELS.fetch(name.to_s) { AhoyDashboard::Serp.adapter_class(name).label }
      end

      def adapter_label(adapter)
        SERP_LABELS.fetch(adapter.label.to_s, adapter.label)
      end

      def serp_cost_note(adapter = AhoyDashboard::Serp.adapter_class)
        return "Sample results are free." if adapter.cost_units(pages: 1).zero?
        return "Each check is one search per place, however deep." if adapter.cost_units(pages: AhoyDashboard::Serp::MAX_PAGES) == 1

        "Each check is one search per place, per page of results."
      end

      def credential_label(key)
        key.to_s.humanize.gsub(/\bApi\b/, "API").gsub(/\bId\b/, "ID")
      end

      def time_zone_label
        zone = AhoyDashboard.time_zone
        abbreviation = zone.now.strftime("%Z")

        abbreviation == zone.name ? zone.name : "#{zone.name} (#{abbreviation})"
      end

      def assistant_notice
        return ASSISTANT_OFF unless AhoyDashboard::Assistant.enabled?

        AhoyDashboard::Assistant.unavailable_reason
      end
    end
  end
end
