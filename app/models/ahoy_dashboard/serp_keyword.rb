module AhoyDashboard
  class SerpKeyword < AhoyDashboard::Record
    MAX_LOCATIONS = 5
    MAX_TAGS = 20
    MAX_TAG_LENGTH = 40

    MONTH = 30.days

    DURATIONS = {
      "daily" => 1.day,
      "weekly" => 1.week,
      "biweekly" => 2.weeks,
      "monthly" => 1.month
    }.freeze

    SEARCH_FIELDS = %i[query engine device language].freeze

    enum :frequency, { daily: 0, weekly: 1, biweekly: 2, monthly: 3 }, validate: true
    enum :source, { manual: 0, search_console: 1 }, validate: true

    has_many :keyword_targets, class_name: "AhoyDashboard::SerpKeywordTarget", foreign_key: :keyword_id,
             inverse_of: :keyword, dependent: :delete_all
    has_many :sites, through: :keyword_targets
    has_many :runs, class_name: "AhoyDashboard::SerpRun", foreign_key: :keyword_id,
             inverse_of: :keyword, dependent: :delete_all
    has_many :checks, class_name: "AhoyDashboard::SerpCheck", foreign_key: :keyword_id,
             inverse_of: :keyword, dependent: :delete_all

    normalizes :query, with: ->(value) { value.to_s.strip.squeeze(" ").presence }
    normalizes :engine, :device, :language, with: ->(value) { value.to_s.strip.downcase.presence }
    normalizes :tags, with: ->(values) { SerpKeyword.clean_tags(values) }

    validates :query, presence: true, length: { maximum: 255 }
    validates :engine, presence: true
    validates :language, presence: true
    validates :device, inclusion: { in: Serp::DEVICES }
    validates :pages, numericality: {
      only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: Serp::MAX_PAGES
    }
    validate :locations_are_usable
    validate :tags_are_usable

    before_validation :clean_locations

    scope :ordered, -> { order(:query, :id) }
    scope :phrased, ->(text) {
      where("lower(#{table_name}.query) = lower(?)", text.to_s.strip.squeeze(" "))
    }
    scope :tagged, ->(tag) {
      tag.present? ? where("#{table_name}.tags @> array[?]::varchar[]", tag.to_s) : all
    }

    def self.clean_tags(values)
      Array(values).flat_map { |value| value.to_s.split(",") }
        .map { |value| value.strip.squeeze(" ") }
        .reject(&:blank?)
        .uniq(&:downcase)
    end

    def self.tags_in_use
      where.not(tags: []).pluck(Arel.sql("distinct unnest(tags)")).sort_by { |tag| [ tag.downcase, tag ] }
    end

    def self.canonical_tags(values, known: tags_in_use)
      spellings = known.index_by(&:downcase)

      clean_tags(values).map { |tag| spellings.fetch(tag.downcase, tag) }
    end
    scope :trackable, -> {
      where(enabled: true)
        .where(id: SerpKeywordTarget.tracked.select(:keyword_id))
    }

    scope :due, ->(now = Time.current) {
      clauses = DURATIONS.keys.map do |name|
        "(frequency = #{frequencies.fetch(name)} and last_checked_at <= :#{name})"
      end
      cutoffs = DURATIONS.map { |name, span| [ name.to_sym, now - span ] }.to_h

      trackable.where("last_checked_at is null or #{clauses.join(' or ')}", **cutoffs)
    }

    def locations
      Array(self[:locations]).map(&:to_s)
    end

    def places
      locations.map { |value| Serp::Location.parse(value) }
    end

    def next_check_at
      return nil if last_checked_at.blank?

      last_checked_at + DURATIONS.fetch(frequency)
    end

    def due?(now: Time.current)
      last_checked_at.blank? || next_check_at <= now
    end

    def plan
      Serp::KeywordPlan.new(pages: pages, place_count: Array(locations).size, frequency: frequency)
    end

    def cost_units(adapter_class = Serp.adapter_class)
      plan.per_check(adapter_class)
    end

    def monthly_units(adapter_class = Serp.adapter_class)
      return 0 unless enabled?

      plan.monthly_units(adapter_class)
    end

    def monthly_checks
      return 0 unless enabled?

      plan.monthly_checks
    end

    def search_identity(values = attributes.symbolize_keys)
      [ values[:query].to_s.downcase, values[:engine].to_s, values[:device].to_s, values[:language].to_s ]
    end

    def search_changed?
      return false if new_record?

      search_identity(SEARCH_FIELDS.index_with { |field| attribute_in_database(field) }) != search_identity
    end

    private

    def clean_locations
      values = Array(self[:locations]).map { |value| value.to_s.strip }.reject(&:blank?).uniq

      self[:locations] = values.presence || [ Serp::DEFAULT_COUNTRY ]
    end

    def tags_are_usable
      errors.add(:tags, "are more than #{MAX_TAGS}") if tags.size > MAX_TAGS

      long = tags.select { |tag| tag.length > MAX_TAG_LENGTH }
      errors.add(:tags, "can be #{MAX_TAG_LENGTH} characters at most, and #{long.to_sentence} is longer") if long.any?
    end

    def locations_are_usable
      return errors.add(:locations, "need at least one place to search from") if locations.empty?

      if locations.size > MAX_LOCATIONS
        errors.add(:locations, "is more than #{MAX_LOCATIONS} places, and every place is another search")
      end

      problems = places.map(&:problem).select { |value| value }
      errors.add(:locations, problems.to_sentence) if problems.any?
    end
  end
end
