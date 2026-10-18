module AhoyDashboard
  module Requirements
    GOOGLE_FIX = :settings_google_connection_path
    EMAILS_FIX = :edit_settings_emails_path
    AI_VISIBILITY_FIX = :edit_settings_ai_visibility_path

    GOOGLE_CREDENTIALS = Requirement.new(ok: -> { SearchConsole.credentials? },
                                         reason: "Add your Google OAuth client ID and secret.", fix: GOOGLE_FIX)
    GOOGLE_CONNECTED = Requirement.new(ok: -> { GoogleAccount.current&.connected? },
                                       reason: "Connect a Google account.", fix: GOOGLE_FIX)
    GOOGLE_PROPERTY = Requirement.new(ok: -> { GoogleAccount.current&.ready? },
                                      reason: "Pick which Search Console property to read.",
                                      fix: :edit_settings_search_console_property_path)

    AI_VISIBILITY = [
      Requirement.new(ok: -> { AiVisibility.asked_names.any? }, reason: "No assistant is on with a key.",
                      fix: AI_VISIBILITY_FIX),
      Requirement.new(ok: -> { AiVisibility::Prompt.exists? }, reason: "There are no prompts.", fix: AI_VISIBILITY_FIX)
    ].freeze

    ALERT_RULES = Requirement.new(ok: -> { AlertRule.live.available.exists? }, reason: "No alert rules are switched on.",
                                  fix: :settings_alert_rules_path)

    ALERT_EMAILS = [
      Requirement.new(ok: -> { Alerts::Digests.periods.any? },
                      reason: "No alert emails are set up. Pick daily, weekly or monthly under Settings, Emails.",
                      fix: EMAILS_FIX),
      Requirement.new(ok: -> { Alerts::Digests.recipients.any? },
                      reason: "Nobody is set to get alert emails. Add an address under Settings, Emails.",
                      fix: EMAILS_FIX)
    ].freeze

    REPORT_EMAILS = [
      Requirement.new(ok: -> { Reports::Digests.periods.any? },
                      reason: "No traffic emails are set up. Pick daily, weekly or monthly under Settings, Emails.",
                      fix: EMAILS_FIX),
      Requirement.new(ok: -> { Reports::Digests.recipients.any? },
                      reason: "Nobody is set to get traffic emails. Add an address under Settings, Emails.",
                      fix: EMAILS_FIX)
    ].freeze
  end
end
