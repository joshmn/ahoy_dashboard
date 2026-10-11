module AhoyDashboard
  module Serp
    class CheckNowPresenter
      attr_reader :keyword

      def self.confirm_for(keyword, adapter_class = Serp.adapter_class)
        units = keyword.cost_units(adapter_class)

        "Check #{keyword.query} now? That is about #{helpers.pluralize(units, 'unit')} off the plan."
      end

      def self.helpers
        ActionController::Base.helpers
      end

      def initialize(keyword: nil)
        @keyword = keyword
      end

      def path
        keyword ? routes.settings_serp_keyword_check_path(keyword) : routes.rank_check_path
      end

      def available?
        blocker.nil?
      end

      def blocker
        return @blocker if defined?(@blocker)

        @blocker = sweep.refusal
      end

      def reason
        case blocker
        when :off then "Rank tracking is off. Turn it on under Settings, Features."
        when :credentials then "#{sweep.adapter_label} has no credentials yet."
        when :nothing then "Track a keyword first."
        when :capped then "This month's search limit is used up."
        when :paused then "This keyword is paused."
        when :no_sites then "Pick a site to look for first."
        when :queued then keyword ? "Sent for checking a moment ago." : "Everything was sent for checking a moment ago."
        end
      end

      # A queued sweep is what the last click did, not a thing that is wrong, so
      # it stays on the disabled button and never becomes a banner. Otherwise
      # every use of the button would answer with a warning.
      def notice_reason
        reason unless blocker == :queued
      end

      def reason_for(row_keyword, sites:)
        return reason if %i[off credentials capped].include?(blocker)
        return "This keyword is paused." unless row_keyword.enabled?
        return "Pick a site to look for first." if sites.zero?

        "Sent for checking a moment ago." if SweepCommand.queued?(row_keyword)
      end

      def fix
        case blocker
        when :credentials, :capped then { label: "Search provider", url: routes.settings_serp_providers_path }
        when :nothing then { label: "Track keyword", url: routes.new_settings_serp_keyword_path }
        when :paused, :no_sites then { label: "Edit keyword", url: routes.edit_settings_serp_keyword_path(keyword) }
        end
      end

      def confirm
        return nil unless available?

        units = self.class.helpers.pluralize(sweep.units, "unit")
        subject = keyword ? keyword.query : self.class.helpers.pluralize(sweep.searches, "search")

        "Check #{subject} now? That is about #{units} off the plan."
      end

      private

      def sweep
        @sweep ||= SweepCommand.new(keyword: keyword)
      end

      def routes
        AhoyDashboard::Engine.routes.url_helpers
      end
    end
  end
end
