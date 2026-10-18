require "ipaddr"

module AhoyDashboard
  class GeneralSettingsForm < AhoyDashboard::Form
    HOST_NAME = /\A(?=.{1,253}\z)[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\z/
    LABELS = { host: "Site host", canonical_host: "Canonical host", internal_ips: "Internal addresses" }.freeze

    attribute :time_zone, TRIMMED
    attribute :host, :string
    attribute :canonical_host, :string
    attribute :internal_ips, :string
    attribute :precomputed_dashboard, :boolean, default: false

    validates :time_zone, presence: { message: "has to be picked" }
    validate :time_zone_exists
    validate :hosts_readable
    validate :internal_ips_readable

    def self.current(request_host: nil)
      new(time_zone: option_for(AhoyDashboard.time_zone),
          host: AhoyDashboard.host || request_host,
          canonical_host: Preferences.read(:site, :canonical_host),
          internal_ips: Preferences.read(:site, :internal_ips).join("\n"),
          precomputed_dashboard: Preferences.read(:site, :precomputed_dashboard))
    end

    def self.zones
      ActiveSupport::TimeZone.all.map { |zone| [ zone.to_s, zone.name ] }
    end

    def self.option_for(zone)
      listed = ActiveSupport::TimeZone.all
      named = listed.find { |candidate| candidate.name == zone.name } ||
        listed.find { |candidate| candidate.tzinfo.identifier == zone.tzinfo.identifier }

      (named || zone).name
    end

    def self.bare_host(value)
      text = value.to_s.strip.downcase
      text = text.sub(%r{\A[a-z][a-z0-9+.-]*://}, "")
      text.split(%r{[/?#]}, 2).first.to_s.sub(/\.\z/, "").presence
    end

    def zone
      time_zone && ActiveSupport::TimeZone[time_zone]
    end

    def host
      self.class.bare_host(super())
    end

    def canonical_host
      self.class.bare_host(super())
    end

    def internal_ip_list
      Preferences.list(internal_ips.to_s)
    end

    def preferences
      { time_zone: zone.name, host: host, canonical_host: canonical_host, internal_ips: internal_ip_list,
        precomputed_dashboard: precomputed_dashboard }
    end

    private

    def time_zone_exists
      return if time_zone.blank? || zone.present?

      errors.add(:time_zone, "is not a time zone this app knows")
    end

    def hosts_readable
      { host: host, canonical_host: canonical_host }.each do |field, value|
        next if value.nil? || value.match?(HOST_NAME)

        errors.add(field, "#{value.inspect} is not a host name. Use one like example.com, with no port")
      end
    end

    def internal_ips_readable
      bad = internal_ip_list.reject { |entry| address?(entry) }
      return if bad.empty?

      errors.add(:internal_ips, "#{bad.map(&:inspect).to_sentence} #{bad.one? ? "is not an address or a range" : "are not addresses or ranges"}. " \
                                "Use one like 10.0.0.0/8 or 203.0.113.7")
    end

    def address?(entry)
      IPAddr.new(entry)
      true
    rescue IPAddr::Error
      false
    end
  end
end
