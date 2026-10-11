module AhoyDashboard
  # A question saved out of Explore.
  #
  # What is stored is the query string, in the shape the URL carries it, so
  # opening one is the same navigation as editing the address bar. Nothing is
  # precomputed and nothing is stored per visitor: a question saved today reads
  # whatever the range holds when it is opened, which is the same thing a segment
  # does and for the same reason.
  #
  # Pinned ones get a card on the dashboard. That is the only thing the flag
  # does, and the order is the order they sit in there.
  class SavedQuery < AhoyDashboard::Record
    # The keys a saved question is allowed to carry. Anything else in the params
    # is dropped on the way in: this is a hash that ends up in url_for, and a
    # stored :host or :controller would build a link somewhere nobody asked for.
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

    scope :ordered, -> { order(:position, :id) }
    scope :pinned, -> { where(pinned: true).order(:position, :id) }

    # Guarded against a missing table so the dashboard still boots mid-migration,
    # the same way Segment.listed is.
    def self.listed
      ordered.to_a
    rescue ActiveRecord::StatementInvalid
      []
    end

    def self.on_the_dashboard
      pinned.limit(MAX_PINNED).to_a
    rescue ActiveRecord::StatementInvalid
      []
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

    # Straight into a url helper. Symbol keys because that is what url_for wants
    # and what every other link on the dashboard hands it.
    def to_query
      params.symbolize_keys
    end

    def pinned?
      pinned
    end

    # What the question says in one line, read back out of the params rather than
    # stored beside them, so a saved question cannot describe itself as something
    # it no longer is.
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
