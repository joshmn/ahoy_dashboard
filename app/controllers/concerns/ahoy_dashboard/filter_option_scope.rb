module AhoyDashboard
  module FilterOptionScope
    INDEX = /\A\d{1,6}\z/

    private

    def edited_index
      return @edited_index if defined?(@edited_index)

      index = params[:edit].to_s
      @edited_index = index.match?(INDEX) && query.filters[index.to_i] ? index.to_i : nil
    end

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

    def dimension_scope(dimension)
      return collect_scope if collect?
      return query.scope if dimension.nil?

      others = query.filters.without_dimension(dimension.key).to_param.presence
      query.with(filters: others || AhoyDashboard::QueryForm::NO_FILTERS).scope
    end
  end
end
