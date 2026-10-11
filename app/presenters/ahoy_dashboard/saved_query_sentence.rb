module AhoyDashboard
  # What a saved question says, in one line.
  #
  # Read off the stored params every time rather than written down beside them,
  # so a question cannot describe itself as something it is not: rename a metric
  # or retire a dimension and the sentence changes with it instead of going
  # stale in a column nobody would think to update.
  #
  # It answers with what it can read and leaves out what it cannot. A dimension
  # that no longer exists is the case that matters: the sentence says the rest of
  # the question rather than printing a raw key or refusing to render.
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
