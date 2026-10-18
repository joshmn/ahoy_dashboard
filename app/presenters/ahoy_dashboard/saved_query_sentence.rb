module AhoyDashboard
  class SavedQuerySentence
    SEPARATOR = " · ".freeze

    def self.call(params)
      new(params).call
    end

    def initialize(params)
      @params = (params || {}).symbolize_keys
    end

    def call
      parts.reject(&:blank?).join(SEPARATOR)
    end

    private

    attr_reader :params

    def parts
      [ metric, grouping, filters, range, term ]
    end

    def metric
      found = AhoyDashboard::Metric.find_by_key(params[:metric])
      (found || AhoyDashboard::Metric.default).label
    end

    def grouping
      return if params[:dimension].blank?

      found = AhoyDashboard::Dimension.find_by_key(params[:dimension])
      return if found.nil?

      "by #{found.filter_label.downcase}"
    end

    def filters
      applied = AhoyDashboard::Filters.from_params(filters: params[:filters])
      return if applied.none?

      applied.sentence
    end

    def range
      found = AhoyDashboard::Period.find_by_key(params[:period])
      return if found.nil?

      found.label.downcase
    end

    def term
      wanted = params[:q].to_s.strip
      return if wanted.blank?

      "matching #{wanted.inspect}"
    end
  end
end
