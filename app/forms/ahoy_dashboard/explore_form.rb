module AhoyDashboard
  # The half of an explore URL that QueryForm does not carry: which dimension to
  # group by, which columns to print, which page of them, and the find term.
  #
  # Same contract as QueryForm. Nothing in here raises, because this is a URL
  # people edit by hand and a nonsense dimension has to fall back to the default
  # rather than 500.
  class ExploreForm < AhoyDashboard::Form
    DEFAULT_DIMENSION = "page".freeze
    ROWS = 50
    MAX_TERM = 100

    # Only the goals query answers these, and it answers nothing else.
    GOAL_COLUMNS = %w[visitors events conversion_rate revenue_total revenue_average].freeze
    GOAL_DEFAULT = %w[visitors events conversion_rate].freeze

    EVENT_COLUMNS = %w[visitors visits pageviews events bounce_rate visit_duration].freeze
    EVENT_DEFAULT = %w[visitors pageviews bounce_rate].freeze

    VISIT_COLUMNS = %w[visitors visits pageviews bounce_rate visit_duration].freeze
    VISIT_DEFAULT = %w[visitors visits bounce_rate visit_duration].freeze

    ENGAGEMENT_COLUMNS = %w[scroll_depth engagement_time].freeze

    # The engagement event carries a path and nothing else, so a dimension read
    # off any other event property groups it to nothing and the columns would
    # print 0 rather than admit the question does not apply. exit_page reads a
    # column off a join that carries no events, and the goal dimension would put
    # every engagement event under the value "engagement".
    ENGAGEMENT_REFUSED = %w[exit_page goal].freeze
    ENGAGEMENT_EVENT_DIMENSION = "page".freeze

    attribute :dimension_key, :string
    attribute :column_keys, :string
    attribute :charted, :string
    attribute :term, :string
    attribute :page_number, :integer, default: 1
    attribute :saved_id, :integer

    # charted is the metric the chart is drawing, which lives in QueryForm. It is
    # handed in rather than parsed so the column order and the chart cannot
    # disagree about which measure leads.
    def self.from_params(params, charted: nil)
      source = normalize(params)

      new(
        dimension_key: source[:dimension],
        column_keys: source[:columns],
        charted: charted,
        term: source[:q].to_s.strip.first(MAX_TERM),
        page_number: source[:page],
        saved_id: source[:saved]
      )
    end

    def self.normalize(params)
      hash = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params
      hash.to_h.symbolize_keys
    rescue StandardError
      {}
    end
    private_class_method :normalize

    # Every dimension a breakdown can group by, which is the registry plus the
    # allowlisted custom properties plus the goal case. Goal is appended rather
    # than in the registry because its SQL is rows, not code.
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

    # The charted metric leads, because ReportPresenter scales every bar off the
    # first column and a bar disagreeing with the chart above it is worse than a
    # column in an order nobody chose. A metric the dimension cannot answer does
    # not lead and does not appear.
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
