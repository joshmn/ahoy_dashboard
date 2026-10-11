module AhoyDashboard
  class SearchOptionsForm < AhoyDashboard::Form
    LANGUAGE = /\A[a-z]{2,3}(-[a-z0-9]{2,4})?\z/
    LABELS = {
      keywords_provider: "Keyword research provider", keywords_location: "Search from",
      keywords_language: "Language", backlinks_provider: "Backlinks provider",
      places_postal_codes: "Postal codes", places_source: "Monthly list address"
    }.freeze

    attribute :keywords_provider, :string
    attribute :keywords_location, :string
    attribute :keywords_language, :string
    attribute :backlinks_provider, :string
    attribute :places_postal_codes, :boolean, default: false
    attribute :places_source, :string

    validate :providers_known
    validate :location_readable
    validate :language_readable
    validate :source_readable

    def self.current
      new(keywords_provider: Preferences.read(:keywords, :provider).to_s,
          keywords_location: Preferences.read(:keywords, :location),
          keywords_language: Preferences.read(:keywords, :language),
          backlinks_provider: Preferences.read(:backlinks, :provider).to_s,
          places_postal_codes: Preferences.read(:places, :postal_codes),
          places_source: Preferences.read(:places, :source))
    end

    def self.human_attribute_name(attribute, options = {})
      LABELS.fetch(attribute.to_sym) { super }
    end

    def self.providers
      Serp.adapter_names.map { |name| [ Settings::Display.serp_label(name.to_s), name.to_s ] }
    end

    def self.countries
      Serp::Location.country_names.map { |code, name| [ name, code ] }.sort_by(&:first)
    end

    def keywords_provider
      super().to_s.strip.presence
    end

    def backlinks_provider
      super().to_s.strip.presence
    end

    def keywords_location
      super().to_s.strip.downcase.presence
    end

    def keywords_language
      super().to_s.strip.downcase.presence
    end

    def places_source
      super().to_s.strip.presence
    end

    def preferences
      {
        keywords: { provider: keywords_provider, location: keywords_location, language: keywords_language },
        backlinks: { provider: backlinks_provider },
        places: { postal_codes: places_postal_codes, source: places_source }
      }
    end

    private

    def providers_known
      known = Serp.adapter_names.map(&:to_s)

      %i[keywords_provider backlinks_provider].each do |field|
        value = public_send(field)
        next if value.nil? || known.include?(value)

        errors.add(field, "#{value.inspect} is not a search provider this dashboard knows")
      end
    end

    def location_readable
      return if keywords_location.nil? || Serp::Location.country_names.key?(keywords_location)

      errors.add(:keywords_location, "#{keywords_location.inspect} is not a country this dashboard knows")
    end

    def language_readable
      return if keywords_language.nil? || keywords_language.match?(LANGUAGE)

      errors.add(:keywords_language, "#{keywords_language.inspect} is not a language code. Use one like en or es")
    end

    def source_readable
      return if places_source.nil?

      uri = URI.parse(Date.current.strftime(places_source))
      return if uri.is_a?(URI::HTTP) && uri.host.present?

      errors.add(:places_source, "has to be a web address starting with https://")
    rescue URI::InvalidURIError, ArgumentError
      errors.add(:places_source, "has to be a web address starting with https://")
    end
  end
end
