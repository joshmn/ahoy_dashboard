module AhoyDashboard
  module Settings
    class GoogleConnectionPresenter
      PICK_PROPERTY = "Pick a property first.".freeze

      attr_reader :callback, :account

      def initialize(callback:, remove: nil)
        @callback = callback
        @remove = remove
        @account = GoogleAccount.current
        @configured = SearchConsole.enabled?
        @unavailable = SearchConsole.unavailable_reason
      end

      def connected?
        account.present? && account.connected?
      end

      def state
        return :credentials unless credentials_ready?
        return :off unless configured?

        connected? ? :connected : :disconnected
      end

      def missing_credentials_label
        return "Client secret missing" if SearchConsole.client_id.present?
        return "Client ID missing" if SearchConsole.client_secret.present?

        "No client ID or secret set"
      end

      def configured?
        @configured
      end

      def broken?
        configured? && account.last_error.present?
      end

      def sync_reason
        @unavailable || (PICK_PROPERTY unless account&.ready?)
      end

      def backfill_reason
        sync_reason || ("Everything Google still keeps is already here." if backfill_done?)
      end

      def fill_reason
        return sync_reason if sync_reason
        return "A fill is already going." if fill.running?

        "Those days are gone. Google stopped serving them." if missing.fillable_days.zero?
      end

      def status
        @status ||= SearchConsoleStatusQuery.call
      end

      def missing
        return unless status.any?

        @missing ||= SearchConsoleMissingDaysQuery.call
      end

      def fill
        @fill ||= SearchConsole::FillQueue.load
      end

      def credential
        @credential ||= SearchConsole.credential || Credential.new(name: SearchConsole::CREDENTIAL_NAME)
      end

      def secrets
        @secrets ||= SearchConsole::CREDENTIAL_KEYS.map do |key|
          [ key, StoredSecretPresenter.google(key, connected: connected?) ]
        end.to_h
      end

      def removing
        secrets.values.find { |secret| secret.removing?(@remove) }
      end

      def redirect_uri
        callback.effective
      end

      def setup_open?
        configured? && !connected?
      end

      def empty_hint
        return "Nothing syncs while Search Console is off." unless configured?

        "Connect an account and pick a property. The first sync brings back a week."
      end

      def summary
        parts = []
        parts << stored_summary if status.any?
        parts << history_summary if connected?
        parts.join(" ").presence
      end

      private

      def credentials_ready?
        SearchConsole.client_id.present? && SearchConsole.client_secret.present?
      end

      def backfill_floor
        @backfill_floor ||= SearchConsole.earliest_available_date
      end

      def backfill_reached
        account&.backfilled_to
      end

      def backfill_done?
        backfill_reached.present? && backfill_reached <= backfill_floor
      end

      def stored_summary
        "#{Display.short_date(status.first_date)} to #{Display.short_date(status.last_date)}" \
          "#{", up to date" if status.current?}."
      end

      def history_summary
        return "History is complete back to #{Display.short_date(backfill_floor)}." if backfill_done?
        return "Older history has not been pulled yet." unless backfill_reached

        short = (backfill_reached - backfill_floor).to_i
        "History reaches back to #{Display.short_date(backfill_reached)}, #{short} #{"day".pluralize(short)} " \
          "short of #{Display.short_date(backfill_floor)}."
      end
    end
  end
end
