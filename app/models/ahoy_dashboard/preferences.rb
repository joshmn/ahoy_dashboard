module AhoyDashboard
  module Preferences
    INTERNAL_IPS = %w[127.0.0.0/8 ::1/128 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 fc00::/7].freeze

    PLACES_SOURCE = "https://cdn.dataforseo.com/v3/locations/locations_serp_google_%Y_%m_01.csv".freeze

    Definition = Data.define(:scope, :name, :type, :default, :stored_as) do
      def key
        stored_as || "#{scope == :site ? "site" : "features.#{scope}"}.#{name}"
      end

      def cast(value)
        return default if value.nil?

        case type
        when :boolean then ActiveModel::Type::Boolean.new.cast(value) || false
        when :string then value.to_s.strip.presence || default
        when :symbol then value.to_s.strip.presence&.to_sym || default
        when :integer then value.to_s.strip.match?(/\A[-+]?\d+\z/) ? value.to_i : default
        when :list then Preferences.list(value)
        when :periods then Digests::PERIODS & Preferences.list(value).map { |period| period.downcase.to_sym }
        end
      end
    end

    DEFINITIONS = [
      [ :site, :host, :string, nil ],
      [ :site, :canonical_host, :string, nil ],
      [ :site, :internal_ips, :list, INTERNAL_IPS ],
      [ :site, :time_zone, :string, "UTC", Setting::TIME_ZONE ],
      [ :site, :precomputed_dashboard, :boolean, false ],
      [ :site, :hide_known_crawlers, :boolean, false ],
      [ :search_console, :redirect_uri, :string, nil ],
      [ :search_console, :property, :string, nil, SearchConsole::STORED_PROPERTY_SETTING ],
      [ :assistant, :withheld, :list, [], Assistant::WITHHELD_KEY ],
      [ :ai_visibility, :frequency, :string, AiVisibility::DEFAULT_FREQUENCY, AiVisibility::FREQUENCY_KEY ],
      [ :ai_visibility, :monthly_cap, :integer, AiVisibility::DEFAULT_CAP, AiVisibility::CAP_KEY ],
      [ :keywords, :provider, :symbol, nil ],
      [ :keywords, :location, :string, "us" ],
      [ :keywords, :language, :string, "en" ],
      [ :backlinks, :provider, :symbol, nil ],
      [ :places, :postal_codes, :boolean, false ],
      [ :places, :source, :string, PLACES_SOURCE ],
      [ :alerts, :digest, :periods, [] ],
      [ :alerts, :recipients, :list, [] ],
      [ :alerts, :from, :string, nil ],
      [ :alerts, :send_empty, :boolean, true ],
      [ :reports, :digest, :periods, [] ],
      [ :reports, :recipients, :list, [] ],
      [ :reports, :from, :string, nil ]
    ].map { |scope, name, type, default, stored_as| Definition.new(scope, name, type, default, stored_as) }.freeze

    class << self
      def definitions
        @definitions ||= (DEFINITIONS + switches).index_by { |definition| [ definition.scope, definition.name ] }
      end

      def definition(scope, name)
        definitions.fetch([ scope.to_sym, name.to_sym ]) do
          raise ArgumentError, "no setting named #{name} for #{scope}"
        end
      end

      def read(scope, name)
        found = definition(scope, name)
        found.cast(stored[found.key])
      end

      def stored?(scope, name)
        !stored[definition(scope, name).key].nil?
      end

      def write(scope, **values)
        values.each do |name, value|
          found = definition(scope, name)
          blank = value.nil? || (value.respond_to?(:empty?) && value.empty? && found.type != :list && found.type != :periods)
          blank ? Setting.clear(found.key) : Setting.write(found.key, serialize(found, value))
        end
        forget
      end

      def clear(scope, *names)
        Setting.where(key: names.map { |name| definition(scope, name).key }).delete_all
        forget
      end

      def forget
        Current.preferences = nil
      end

      def stored
        Current.preferences ||= Setting.where(key: definitions.values.map(&:key)).pluck(:key, :value).to_h
      rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
        {}
      end

      def list(value)
        values = value.is_a?(String) ? value.split(/[\s,]+/) : Array(value)
        values.map { |entry| entry.to_s.strip }.reject(&:blank?).uniq
      end

      private

      def switches
        Features::ALL.map do |feature|
          Definition.new(feature.name, :enabled, :boolean, feature.name == :favicons, nil)
        end
      end

      def serialize(found, value)
        cast = found.cast(value)
        cast.is_a?(Symbol) ? cast.to_s : cast.is_a?(Array) ? cast.map(&:to_s) : cast
      end
    end
  end
end
