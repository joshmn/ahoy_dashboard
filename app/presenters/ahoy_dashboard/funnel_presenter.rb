module AhoyDashboard
  class FunnelPresenter
    FRAME_PREFIX = "report_funnel_".freeze
    DETAILS_FRAME_PREFIX = "report_details_funnel_".freeze
    MODAL_PREFIX = "funnel_".freeze
    DETAILS_VIEW = "details".freeze

    COLUMNS = [
      { key: "visitors", label: "Visitors", short: "People" },
      { key: "conversion_rate", label: "Share of step one", short: "Rate" },
      { key: "dropoff", label: "Lost since the step before", short: "Lost" }
    ].freeze

    DETAIL_COLUMNS = (COLUMNS + [
      { key: "dropoff_rate", label: "Share lost since the step before", short: "Lost rate" }
    ]).freeze

    class << self
      def frame_id(funnel)
        "#{FRAME_PREFIX}#{funnel.id}"
      end

      def details_frame_id(funnel)
        "#{DETAILS_FRAME_PREFIX}#{funnel.id}"
      end

      def modal_key(funnel)
        "#{MODAL_PREFIX}#{funnel.id}"
      end

      def wrap(readings, query:)
        readings.map { |reading| new(query: query, funnel: reading.funnel, result: reading) }
      end
    end

    class Row
      def initialize(step:, presenter:)
        @step = step
        @presenter = presenter
      end

      attr_reader :step

      delegate :position, :name, :dropoff_rate, to: :step

      def share
        presenter.share(step)
      end

      def continue_rate
        return if dropoff_rate.nil?

        100 - dropoff_rate.to_f
      end

      def dropoff_label
        return if step.dropoff.nil?

        "drop off (#{AhoyDashboard::Counted.call(step.dropoff.to_i, noun: "visitor")})"
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

    def empty?
      !result.any?
    end

    def summary_line
      return nil if empty?

      "#{number(result.converted)} of #{number(result.entered)} went the whole way, " \
        "#{rate(result.conversion_rate)}."
    end

    def share(step)
      AhoyDashboard::Share.fraction(step.visitors, of: result.entered)
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
      AhoyDashboard.routes.funnel_path(
        funnel, query.to_query.merge(overrides)
      )
    end
  end
end
