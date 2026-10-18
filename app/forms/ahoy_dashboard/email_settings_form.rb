require "mail"

module AhoyDashboard
  class EmailSettingsForm < AhoyDashboard::Form
    PERIODS = [ [ "daily", "Daily" ], [ "weekly", "Weekly" ], [ "monthly", "Monthly" ] ].freeze
    LABELS = {
      alerts_digest: "Alert emails", alerts_recipients: "Alert email recipients", alerts_from: "Alert email sender",
      reports_digest: "Traffic emails", reports_recipients: "Traffic email recipients", reports_from: "Traffic email sender"
    }.freeze

    attribute :alerts_digest, default: -> { [] }
    attribute :alerts_recipients, :string
    attribute :alerts_from, TRIMMED
    attribute :alerts_send_empty, :boolean, default: true
    attribute :reports_digest, default: -> { [] }
    attribute :reports_recipients, :string
    attribute :reports_from, TRIMMED

    validate :periods_known
    validate :recipients_readable
    validate :senders_readable

    def self.current
      new(alerts_digest: Preferences.read(:alerts, :digest).map(&:to_s),
          alerts_recipients: Preferences.read(:alerts, :recipients).join("\n"),
          alerts_from: Preferences.read(:alerts, :from),
          alerts_send_empty: Preferences.read(:alerts, :send_empty),
          reports_digest: Preferences.read(:reports, :digest).map(&:to_s),
          reports_recipients: Preferences.read(:reports, :recipients).join("\n"),
          reports_from: Preferences.read(:reports, :from))
    end

    def self.address?(value)
      parsed = Mail::Address.new(value)
      parsed.address.to_s.match?(URI::MailTo::EMAIL_REGEXP) && parsed.domain.to_s.include?(".")
    rescue Mail::Field::ParseError
      false
    end

    def alerts_digest
      Array(super()).map { |period| period.to_s.strip }.reject(&:blank?)
    end

    def reports_digest
      Array(super()).map { |period| period.to_s.strip }.reject(&:blank?)
    end

    def alerts_recipient_list
      Preferences.list(alerts_recipients.to_s)
    end

    def reports_recipient_list
      Preferences.list(reports_recipients.to_s)
    end

    def preferences
      {
        alerts: { digest: alerts_digest, recipients: alerts_recipient_list, from: alerts_from,
                  send_empty: alerts_send_empty },
        reports: { digest: reports_digest, recipients: reports_recipient_list, from: reports_from }
      }
    end

    private

    def periods_known
      known = PERIODS.map(&:first)

      %i[alerts_digest reports_digest].each do |field|
        unknown = public_send(field) - known
        errors.add(field, "#{unknown.map(&:inspect).to_sentence} is not daily, weekly or monthly") if unknown.any?
      end
    end

    def recipients_readable
      { alerts_recipients: alerts_recipient_list, reports_recipients: reports_recipient_list }.each do |field, list|
        bad = list.reject { |entry| entry.match?(URI::MailTo::EMAIL_REGEXP) && entry.split("@").last.include?(".") }
        next if bad.empty?

        errors.add(field, "#{bad.map(&:inspect).to_sentence} #{bad.one? ? "is not an email address" : "are not email addresses"}")
      end
    end

    def senders_readable
      { alerts_from: alerts_from, reports_from: reports_from }.each do |field, value|
        next if value.nil? || self.class.address?(value)

        errors.add(field, "#{value.inspect} is not an email address. Use one like alerts@example.com " \
                          "or Alerts <alerts@example.com>")
      end
    end
  end
end
