module AhoyDashboard
  class SavedQuery < AhoyDashboard::Record
    include Positioned

    PERMITTED = %i[
      period interval metric comparison crawlers internal from to filters
      dimension columns q page
    ].freeze

    FILTER_FIELDS = %i[dimension operator value group].freeze
    PERMITTED_PARAMS = [ *PERMITTED, { filters: FILTER_FIELDS } ].freeze

    MAX_PINNED = 3

    validates :name, presence: true, uniqueness: true
    validate :has_a_question

    normalizes :name, with: ->(value) { value.to_s.strip.presence }
    normalizes :params, with: ->(value) { clean(value) }

    scope :pinned, -> { where(pinned: true).order(:position, :id) }

    def self.listed
      return [] unless Installation.table?(table_name)

      ordered.to_a
    end

    def self.on_the_dashboard
      return [] unless Installation.table?(table_name)

      pinned.limit(MAX_PINNED).to_a
    end

    def self.clean(value)
      source = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
      return {} unless source.respond_to?(:each_pair)

      cleaned = source.to_h.symbolize_keys.slice(*PERMITTED)
      cleaned[:filters] = clean_filters(cleaned[:filters]) if cleaned.key?(:filters)

      cleaned.reject { |_key, value| value.blank? }.transform_keys(&:to_s)
    end

    def self.clean_filters(value)
      return value.to_s if value.to_s == AhoyDashboard::QueryForm::NO_FILTERS

      AhoyDashboard::Filters.from_params(filters: value).to_param.presence
    rescue StandardError
      nil
    end
    private_class_method :clean_filters

    def to_query
      params.symbolize_keys
    end

    def pinned?
      pinned
    end

    def sentence
      AhoyDashboard::SavedQuerySentence.call(to_query)
    end

    private

    def has_a_question
      return if params.present?

      errors.add(:params, "need a question to save, and this one is empty")
    end
  end
end
