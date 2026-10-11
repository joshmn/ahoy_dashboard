module AhoyDashboard
  module SearchConsoleScreen
    private

    def load_search_console_screen
      @account = GoogleAccount.current
      @status = SearchConsoleStatusQuery.call
      @credential = SearchConsole.credential || Credential.new(name: SearchConsole::CREDENTIAL_NAME)
      # enabled? is credentials AND the config switch, and the two need
      # separate messages: an operator who has not flipped
      # Search Console on under Settings, Features should not be told their client
      # secret is missing when it is sitting right there.
      @credentials_ready = SearchConsole.client_id.present? && SearchConsole.client_secret.present?
      @configured = SearchConsole.enabled?
      @unavailable = SearchConsole.unavailable_reason
      # Shown so it can be copied into the Google Cloud client rather than
      # typed from memory. Google compares it character for character, and a
      # mismatch is the most common way this setup fails, so the page also
      # works out what this request's own origin would produce and says so
      # when the two disagree.
      @callback = SearchConsoleCallbackQuery.call(request: request)
      @redirect_uri = @callback.effective
      @scope = SearchConsole::SCOPE
      # The disconnect step. A param rather than a dialog, so the confirmation
      # is a page that works with the JavaScript off.
      @confirming = params[:confirm].present?
      set_secrets
      set_backfill
      set_missing
      @redirect_form ||= SearchConsole::RedirectForm.current
    end

    def set_secrets
      connected = @account&.connected?
      @secrets = %i[client_id client_secret]
        .map { |key| [ key, AhoyDashboard::Settings::StoredSecretPresenter.google(key, connected: connected) ] }.to_h
      @removing = @secrets.values.find { |secret| secret.stored? && params[:remove] == secret.key.to_s }
    end

    # How far back the walk has got, so the button beside the nightly pull can
    # say whether there is anything left to reach for. Google stops serving
    # days past a rolling floor, so "finished" is against that rather than
    # against any date the site has been up.
    def set_backfill
      @backfill_floor = SearchConsole.earliest_available_date
      @backfill_reached = @account&.backfilled_to
      @backfill_done = @backfill_reached.present? && @backfill_reached <= @backfill_floor
    end

    # The holes in the middle, which neither the nightly run nor the backfill
    # will ever go back for. Only worked out once something has been stored:
    # before that there is no record to have holes in, and the card above
    # already says so.
    def set_missing
      return unless @status.any?

      @missing = SearchConsoleMissingDaysQuery.call
      @fill = SearchConsole::FillQueue.load
      @fill_reason = fill_reason
    end

    # Nothing to fill is two different answers. A record with no holes in it
    # does not need a button at all and the card says so on its own. A record
    # whose only holes are older than sixteen months needs the button there
    # and switched off, because the days are on the screen and somebody is
    # going to ask why they cannot have them.
    def fill_reason
      return @unavailable if @unavailable
      return "Pick a property first." unless @account&.ready?
      return "A fill is already going." if @fill.running?
      return "Those days are gone. Google stopped serving them." if @missing.fillable_days.zero?

      nil
    end
  end
end
