module AhoyDashboard
  class ExploreForm < AhoyDashboard::Form
    DEFAULT_DIMENSION = "page".freeze
    ROWS = 50

    GOAL_COLUMNS = %w[visitors events conversion_rate revenue_total revenue_average].freeze
    GOAL_DEFAULT = %w[visitors events conversion_rate].freeze

    EVENT_COLUMNS = %w[visitors visits pageviews events bounce_rate visit_duration].freeze
    EVENT_DEFAULT = %w[visitors pageviews bounce_rate].freeze

    VISIT_COLUMNS = %w[visitors visits pageviews bounce_rate visit_duration].freeze
    VISIT_DEFAULT = %w[visitors visits bounce_rate visit_duration].freeze

    ENGAGEMENT_COLUMNS = %w[scroll_depth engagement_time].freeze

    ENGAGEMENT_REFUSED = %w[exit_page goal].freeze
    ENGAGEMENT_EVENT_DIMENSION = "page".freeze

    attribute :dimension_key, :string
    attribute :column_keys, :string
    attribute :charted, :string
    attribute :term, :string
    attribute :page_number, :integer, default: 1
    attribute :saved_id, :integer

    def self.from_params(params, charted: nil)
      source = normalize(params)

      new(
        dimension_key: source[:dimension],
        column_keys: source[:columns],
        charted: charted,
        term: SearchTerm.clean(source[:q]),
        page_number: source[:page],
        saved_id: source[:saved]
      )
    end

    def self.dimensions
      (AhoyDashboard::Dimension.filterable + [ AhoyDashboard::Dimension.goal ]).uniq
    end

    def dimension
      @dimension ||= AhoyDashboard::Dimension.find_by_key(dimension_key) ||
        AhoyDashboard::Dimension.find(DEFAULT_DIMENSION)
    end

    def goal?
      dimension.key == AhoyDashboard::Dimension::GOAL_KEY
    end

    def page
      [ page_number.to_i, 1 ].max
    end

    def offset
      (page - 1) * ROWS
    end

    def limit
      ROWS
    end

    def searching?
      term.present?
    end

    def columns_chosen?
      requested.any?
    end

    def available_columns
      return GOAL_COLUMNS if goal?

      base = dimension.event? ? EVENT_COLUMNS : VISIT_COLUMNS
      engagement? ? base + ENGAGEMENT_COLUMNS : base
    end

    def columns
      wanted = requested.presence || default_columns
      lead = charted.to_s.presence_in(available_columns)

      ([ lead ].compact + (available_columns & wanted)).uniq.presence || default_columns
    end

    def default_columns
      return GOAL_DEFAULT if goal?

      available_columns & (dimension.event? ? EVENT_DEFAULT : VISIT_DEFAULT)
    end

    def to_query
      {
        dimension: (dimension.key unless dimension.key == DEFAULT_DIMENSION),
        columns: (requested.join(",") if requested.any?),
        q: term.presence,
        page: (page if page > 1),
        saved: saved_id
      }.compact
    end

    def with(overrides)
      self.class.from_params(to_query.merge(overrides.to_h.symbolize_keys), charted: charted)
    end

    def toggling(column)
      column = column.to_s
      current = columns
      wanted = current.include?(column) ? current - [ column ] : current + [ column ]

      with(columns: (wanted.presence || current).join(","), page: nil)
    end

    private

    def engagement?
      return false if dimension.key.in?(ENGAGEMENT_REFUSED)
      return false if dimension.property?

      dimension.visit? || dimension.key == ENGAGEMENT_EVENT_DIMENSION
    end

    def requested
      @requested ||= column_keys.to_s.split(",").map(&:strip) & available_columns
    end
  end
end
