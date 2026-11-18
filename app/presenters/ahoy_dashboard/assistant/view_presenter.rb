module AhoyDashboard
  module Assistant
    class ViewPresenter
      HEIGHT = 190

      def self.wrap(views)
        Array(views).map { |view| new(view) }
      end

      def initialize(view)
        @view = view
      end

      attr_reader :view

      delegate :kind, :title, :subtitle, :path, :path_label, :series?, :table?, :figures?, :prompts?,
               :columns, :rows, :figures, :metric, to: :view

      def chart_data
        [ { name: metric.label, data: view.points } ]
      end

      def chart_options
        {
          library: {
            plugins: { tmFormat: { label: metric.label, value: metric.format_type.to_s,
                                   interval: view.interval.to_s } },
            scales: { y: { max: (100 if AhoyDashboard::DashboardPresenter::PERCENT_METRICS.include?(metric.key)) }.compact }
          }
        }
      end

      def height
        HEIGHT
      end

      def cell(row, column)
        value = row[column[:key].to_sym]
        return "Unknown" if value.nil? || value.to_s.strip.empty?

        value.is_a?(Numeric) ? ActiveSupport::NumberHelper.number_to_delimited(value) : value.to_s
      end

      def alignment(column)
        column[:align].to_s == "end" ? "end" : nil
      end

      def grid_template
        widths = columns.each_with_index.map { |_, index| index.zero? ? "minmax(0, 1fr)" : "110px" }

        widths.join(" ")
      end

      def delta(figure)
        metric = AhoyDashboard::Metric.find_by_key(figure[:metric_key].to_s)

        AhoyDashboard::Delta.percent(figure[:change], inverted: metric&.inverted?)
      end
    end
  end
end
