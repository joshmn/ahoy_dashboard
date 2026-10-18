module AhoyDashboard
  module Seo
    class AlertPresenter < BasePresenter
      delegate :rules, :live, :sample_data?, :enabled?, :deliverable?, :emailing?, to: :result

      def tiles
        [
          Tile.new(label: "Rules", value: number(rules.size), note: "#{live.size} on", tone: nil),
          Tile.new(label: "Alerts", value: number(result.total), note: range_label, tone: nil),
          Tile.new(label: "Serious", value: number(result.firing), note: "high severity", tone: nil),
          Tile.new(label: "Quiet rules", value: number(result.quiet), note: "never fired", tone: nil),
          Tile.new(label: "Delivery", value: delivery_value, note: delivery_note, tone: nil, kind: :status),
          Tile.new(label: "Failed to send", value: number(result.undelivered), note: nil, tone: nil)
        ]
      end

      def events
        @events ||= AhoyDashboard::AlertEventDecorator.wrap(result.events)
      end

      def sample_notice
        return nil unless result.sample?

        if result.sample >= result.total
          { title: "These alerts are from sample data.",
            detail: "No search provider was set up when they fired, so they are made up. Choose a real one before you trust them." }
        else
          { title: "Some alerts are from sample data.",
            detail: "#{number(result.sample)} of the #{number(result.total)} alerts in this range came from sample data, " \
                    "so they are made up. They are marked Sample below." }
        end
      end

      def paged?
        result.pages > 1
      end

      def page_label
        "Page #{result.page} of #{result.pages}"
      end

      def previous_page_path
        result.page > 1 ? page_path(result.page - 1) : nil
      end

      def next_page_path
        result.more? ? page_path(result.page + 1) : nil
      end

      def page_path(page)
        routes.seo_alert_path(query.to_query.merge(page: page))
      end

      def delivery_value
        return "Emailing" if emailing?

        deliverable? ? "Sending" : "Not sending"
      end

      def delivery_note
        return "#{result.emails.to_sentence} emails" if emailing?

        deliverable? ? "through your notifier" : "shown on this page only"
      end

      def notice
        return AhoyDashboard::SetupNotice.call(:alerts, url: features_path) unless enabled?

        unless deliverable? || emailing?
          return AhoyDashboard::SetupNotice.call(:alert_emails, url: emails_path, hint: email_setup_hint)
        end

        return nil if live.any?

        AhoyDashboard::SetupNotice.call(:alert_rule, url: rules_path)
      end

      def email_setup_hint
        periods = ::AhoyDashboard::Alerts::Digests.periods

        if periods.any?
          "Alerts still show on this page. Alert emails are set to go out #{periods.to_sentence}, but nobody is set " \
            "to get them. Add an address under Settings, Emails."
        else
          "Alerts still show on this page. To get them by email, pick how often and who gets them under Settings, Emails."
        end
      end

      def rules_path
        routes.settings_alert_rules_path
      end

      def emails_path
        routes.edit_settings_emails_path
      end

      def features_path
        routes.settings_features_path(anchor: "feature-alerts")
      end

      def edit_rule_path(rule)
        routes.edit_settings_alert_rule_path(rule)
      end

      def run_path
        routes.seo_alert_runs_path
      end

      def run_reason
        enabled? ? nil : "Alerts are off. Turn them on under Settings, Features."
      end

      def condition_for(rule)
        rule.condition
      end

      def csv_tables
        [
          CsvTable.new(key: "recent", label: "Recent alerts", headers: alerts_headers) do
            events.map do |event|
              values = [ csv_time(event.fired_at), event.severity_label, event.headline, event.detail,
                         event.rule.name, ("Sample" if sample_data?(event)) ]
              values << event.sent_label if deliverable?
              values
            end
          end,
          CsvTable.new(key: "rules", label: "Rules that are on",
                       headers: [ "Rule", "Fires when", "Fired", "Last fired" ]) do
            live.map do |rule|
              [ rule.name, condition_for(rule), rule.fired_count, csv_time(rule.last_fired_at) ]
            end
          end
        ]
      end

      def subject_note
        "A rule reports each change once, so a ranking that stays down or a job that keeps failing alerts once."
      end

      private

      def carried
        result.page > 1 ? { page: result.page } : {}
      end

      def alerts_headers
        [ "When", "Severity", "What happened", "Detail", "Rule", "Sample data", *("Sent" if deliverable?) ]
      end
    end
  end
end
