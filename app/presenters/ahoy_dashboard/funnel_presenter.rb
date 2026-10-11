module AhoyDashboard
  # One funnel card, or the same funnel blown up into the details modal.
  #
  # Its rows are in step order rather than ranked, and every bar is scaled against
  # step one rather than against the biggest row, because the shape of the drop is
  # the whole answer. The top bar is therefore always full.
  class FunnelPresenter
    FRAME_PREFIX = "report_funnel_".freeze
    DETAILS_FRAME_PREFIX = "report_details_funnel_".freeze
    MODAL_PREFIX = "funnel_".freeze
    DETAILS_VIEW = "details".freeze

    LABEL_COLUMN = "Step".freeze

    COLUMNS = [
      { key: "visitors", label: "Visitors", short: "People" },
      { key: "conversion_rate", label: "Share of step one", short: "Rate" },
      { key: "dropoff", label: "Lost since the step before", short: "Lost" }
    ].freeze

    DETAIL_COLUMNS = (COLUMNS + [
      { key: "dropoff_rate", label: "Share lost since the step before", short: "Lost rate" }
    ]).freeze

    def self.frame_id(funnel)
      "#{FRAME_PREFIX}#{funnel.id}"
    end

    def self.details_frame_id(funnel)
      "#{DETAILS_FRAME_PREFIX}#{funnel.id}"
    end

    def self.modal_key(funnel)
      "#{MODAL_PREFIX}#{funnel.id}"
    end

    class Row
      def initialize(step:, presenter:)
        @step = step
        @presenter = presenter
      end

      attr_reader :step

      delegate :position, :name, :visitors, :first?, :dropoff_rate, to: :step

      def share
        presenter.share(step)
      end

      # The other side of the drop off, which is the number somebody actually
      # reads off the line between two steps. dropoff_rate is measured against
      # the step above rather than against the top, so this is too.
      def continue_rate
        return if dropoff_rate.nil?

        100 - dropoff_rate.to_f
      end

      def dropoff_label
        return if step.dropoff.nil?

        "drop off (#{presenter.number(step.dropoff)} #{"visitor".pluralize(step.dropoff.to_i)})"
      end

      def values
        {
          "visitors" => presenter.number(step.visitors),
          "conversion_rate" => presenter.rate(step.conversion_rate),
          "dropoff" => presenter.number(step.dropoff),
          "dropoff_rate" => presenter.rate(step.dropoff_rate)
        }
      end

      private

      attr_reader :presenter
    end

    attr_reader :query, :funnel, :result

    def initialize(query:, funnel:, result:, details: false)
      @query = query
      @funnel = funnel
      @result = result
      @details = details
    end

    def details?
      @details
    end

    def title
      funnel.name
    end

    def label_column
      LABEL_COLUMN
    end

    def columns
      details? ? DETAIL_COLUMNS : COLUMNS
    end

    def frame_id
      details? ? self.class.details_frame_id(funnel) : self.class.frame_id(funnel)
    end

    def modal_key
      self.class.modal_key(funnel)
    end

    def rows
      @rows ||= result.steps.map { |step| Row.new(step: step, presenter: self) }
    end

    # Nobody reached the first step, so there is no shape to draw. The steps are
    # still real and still named, which is why this is about the traffic rather
    # than about the funnel.
    def empty?
      !result.any?
    end

    def header_row
      [ label_column, *columns.map { |column| column[:label] } ]
    end

    def summary_line
      return nil if empty?

      "#{number(result.converted)} of #{number(result.entered)} went the whole way, " \
        "#{rate(result.conversion_rate)}."
    end

    # The one thing about a funnel that is not visible in it. Somebody reading a
    # drop between two steps will otherwise assume a visitor who came back the
    # next day and finished is in the bottom number.
    def counting_note
      "Counted per visit: the steps have to happen in order, in one sitting. Coming back later " \
        "and finishing is a different visit and does not carry through."
    end

    def share(step)
      return 0.0 unless result.entered.positive?

      (step.visitors.to_f / result.entered).clamp(0.0, 1.0)
    end

    def card_path
      path
    end

    def details_path
      path(view: DETAILS_VIEW)
    end

    def number(value)
      return "" if value.nil?

      ActiveSupport::NumberHelper.number_to_delimited(value.to_i)
    end

    # Already a percentage on the way in, unlike Search Console's ctr. Blank for
    # a step with nothing to compare against rather than a flat zero.
    def rate(value)
      return "" if value.nil?

      "#{value.to_f.round(1)}%"
    end

    def as_json(*)
      {
        funnel: funnel.id,
        title: title,
        details: details?,
        entered: result.entered,
        converted: result.converted,
        conversion_rate: result.conversion_rate,
        columns: columns,
        steps: rows.map do |row|
          { position: row.position, name: row.name, share: row.share, values: row.values }
        end
      }
    end

    private

    def path(overrides = {})
      AhoyDashboard::Engine.routes.url_helpers.funnel_path(
        funnel, query.to_query.merge(overrides)
      )
    end
  end
end
