module AhoyDashboard
  module FilterOptionScope
    INDEX = /\A\d{1,6}\z/

    private

    def edited_index
      return @edited_index if defined?(@edited_index)

      index = params[:edit].to_s
      @edited_index = index.match?(INDEX) && query.filters[index.to_i] ? index.to_i : nil
    end

    # The same filter dialog feeding a form rather than the dashboard. A
    # parameter rather than a resource of its own, because it is the same values
    # and only what a pick does with the answer changes.
    def collect?
      params[:collect].present?
    end

    def collect_scope
      query.with(filters: AhoyDashboard::QueryForm::NO_FILTERS, internal: AhoyDashboard::QueryForm::INTERNAL_ON).scope
    end

    def option_scope(edit: edited_index)
      return collect_scope if collect?
      return query.without_filter(edit).scope if edit

      query.scope
    end

    # A dimension's values read with every filter but its own. Values picked in
    # one dimension join as alternatives, so listing Country under a filter that
    # already says Country is US would offer US and nothing it could be joined to.
    def dimension_scope(dimension)
      return collect_scope if collect?
      return query.scope if dimension.nil?

      others = query.filters.without_dimension(dimension.key).to_param.presence
      query.with(filters: others || AhoyDashboard::QueryForm::NO_FILTERS).scope
    end
  end
end
