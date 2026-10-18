module AhoyDashboard
  class KeywordIdea < AhoyDashboard::Record
    self.table_name = "ahoy_dashboard_keyword_ideas"

    UPSERT_KEYS = %i[seed query location language].freeze

    EASY = 35
    HARD = 60

    Lookup = Data.define(:seed, :location, :language) do
      def place
        Serp::Location.parse(location)
      end

      def place_label
        place.city? ? place.label : place.country_name
      end

      def label
        [ seed, place_label, language ].join(", ")
      end
    end

    validates :seed, :query, :provider, :fetched_at, presence: true

    scope :ordered, -> { order(Arel.sql("volume desc nulls last, query asc")) }

    def self.lookups
      distinct.order(:seed, :location, :language).pluck(:seed, :location, :language)
        .map { |seed, location, language| Lookup.new(seed: seed, location: location, language: language) }
    end

    def self.saved(seed, location: Keywords.location, language: Keywords.language)
      where(seed: seed.to_s.strip.downcase, location: location, language: language)
    end

    def self.absorb(rows)
      return 0 if rows.blank?

      upsert_all(rows, unique_by: UPSERT_KEYS,
                       update_only: %i[volume difficulty cpc competition intent trend provider fetched_at])
      rows.size
    end

    def band
      return "Unknown" if difficulty.nil?
      return "Hard" if difficulty >= HARD
      return "Medium" if difficulty >= EASY

      "Easy"
    end

    def worth
      return 0.0 if volume.nil?

      (volume / (difficulty.to_i + 10).to_f).round(1)
    end
  end
end
