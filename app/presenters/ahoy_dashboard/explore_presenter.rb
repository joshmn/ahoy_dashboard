module AhoyDashboard
  # One composed question and its answer.
  #
  # A ReportPresenter with no report behind it: the rows, the columns, the bar
  # widths and the label handling are all the same job a card does, so they are
  # inherited rather than written twice. What a report supplies and an explore
  # does not is a key to build paths from, so every path here is rebuilt off the
  # question instead.
  class ExplorePresenter < AhoyDashboard::ReportPresenter
    TITLE = "Explore".freeze

    attr_reader :explore, :row_total

    def initialize(query:, explore:, result:, row_total: nil)
      @query = query
      @explore = explore
      @result = result
      @row_total = row_total
      @page = explore.page
      @details = true
      @dimension = explore.dimension
      @property_keys = []
      @report = nil
      @tab = nil
    end

    def title
      TITLE
    end

    def label_column
      dimension.label
    end

    def term
      explore.term
    end

    def tabs
      []
    end

    def property?
      false
    end

    def property_options
      []
    end

    def heading
      "#{query.metric.label} by #{dimension.label.downcase}"
    end

    # What the question is, in the order the sentence reads it. Kept out of the
    # view so the CSV filename and the page title cannot drift from the heading.
    def summary
      parts = [ range_label ]
      parts << "#{query.filters.count} #{'filter'.pluralize(query.filters.count)}" if query.filters.any?
      parts << "matching #{term}" if explore.searching?

      parts.join(" · ")
    end

    def path(overrides = {})
      routes.explore_path(params_for(overrides))
    end

    def csv_path
      routes.explore_path(params_for(page: nil, saved: nil).merge(format: :csv))
    end

    def next_path
      path(page: page + 1) if more?
    end

    def previous_path
      return if page <= 1

      path(page: page > 2 ? page - 1 : nil)
    end

    def clear_search_path
      path(q: nil, page: nil)
    end

    def row_range_label
      first = explore.offset + 1

      window = "#{first} to #{first + rows.size - 1}"
      return window if row_total.nil?

      "#{window} of #{ActiveSupport::NumberHelper.number_to_delimited(row_total)}"
    end

    def columns_chosen?
      explore.columns_chosen?
    end

    def column_hidden_when_narrow?(index)
      index.positive? && !columns_chosen?
    end

    # Saving a question is handing this URL to the form that names it. The
    # question is the query string, so there is nothing to serialise: what gets
    # stored is what is in the address bar.
    def question_params
      params_for(page: nil, q: nil, saved: nil).reject { |_key, value| value.blank? }
    end

    def save_path
      routes.new_settings_saved_query_path(question: question_params)
    end

    # Editing an existing one is the same trip with the record named. Explore is
    # where a question is composed, so it is where a question is changed; the
    # form only ever holds the name and the pin.
    def update_path
      routes.edit_settings_saved_query_path(saved_query, question: question_params)
    end

    attr_accessor :saved_query

    def editing?
      saved_query.present?
    end

    def save_label
      editing? ? "Save changes to #{saved_query.name}" : "Save this question"
    end

    def metric_options
      AhoyDashboard::Metric::ALL.map do |metric|
        menu_item(metric.label, query.with(metric: metric.key).to_query,
                  active: metric.key == query.metric.key)
      end
    end

    def dimension_options
      dimension_groups.flat_map(&:last)
    end

    def dimension_groups
      AhoyDashboard::Dimension.grouped(AhoyDashboard::ExploreForm.dimensions).map do |group, candidates|
        [ group, candidates.map { |candidate| dimension_item(candidate) } ]
      end
    end

    # Every column the dimension can answer, and clicking one adds or drops it.
    # A dimension that cannot answer a metric does not offer it, rather than
    # offering it and printing 0.
    def column_options
      shown = columns.map(&:key)

      explore.available_columns.map do |key|
        metric = AhoyDashboard::Metric.find_by_key(key)

        menu_item(metric&.label || key.humanize, query.to_query,
                  explore: explore.toggling(key).to_query,
                  active: shown.include?(key))
      end
    end

    def option_groups
      traffic = [ { label: "Include crawlers", url: crawler_toggle_path, active: query.include_crawlers? } ]
      if AhoyDashboard::Sql::ExcludedTraffic.enabled?
        traffic << { label: "Include hidden traffic", url: internal_toggle_path, active: query.include_internal? }
      end

      [ [ "Columns", column_options ], [ "Traffic", traffic ] ]
    end

    # Custom is seeded with the window on screen, the way the dashboard's period
    # menu seeds it, so picking it opens the range fields on the range somebody
    # was already looking at rather than on a silent fall back to 30 days.
    def period_options
      AhoyDashboard::Period::ALL.map do |period|
        params = query.with(period: period.key).to_query
        params = params.merge(from: query.range_from_field, to: query.range_to_field) if period.custom?

        menu_item(period.label, params, active: period.key == query.period.key)
      end
    end

    def interval_options
      query.intervals.map do |interval|
        label = AhoyDashboard::DashboardPresenter::INTERVAL_LABELS.fetch(interval, interval.to_s.humanize)
        menu_item(label, query.with(interval: interval.to_s).to_query, active: query.interval == interval.to_sym)
      end
    end

    def comparison_options
      AhoyDashboard::DashboardPresenter::COMPARISON_LABELS.map do |value, label|
        menu_item(label, query.with(comparison: value).to_query,
                  active: query.comparison&.to_s == value)
      end
    end

    def interval_label
      AhoyDashboard::DashboardPresenter::INTERVAL_LABELS.fetch(query.interval, query.interval.to_s.humanize)
    end

    def comparison_label
      phrase = query.comparison && query.period.comparison_phrase(query.range, query.comparison)
      return phrase if phrase.present? && query.period.running?(query.range)

      AhoyDashboard::DashboardPresenter::COMPARISON_LABELS.fetch(query.comparison&.to_s, nil)
    end

    def period_label
      query.period_label
    end

    def range_label
      query.range_label
    end

    def clear_filters_path
      path_for(query.with(filters: nil).to_query)
    end

    def clear_range_path
      path_for(query.with(period: AhoyDashboard::Period::DEFAULT_KEY).to_query)
    end

    def crawler_toggle_path
      path_for(query.crawler_toggle_params)
    end

    def internal_toggle_path
      path_for(query.internal_toggle_params)
    end

    def remove_filter_path(index)
      path_for(query.without_filter_params(index))
    end

    # Clicking a row narrows the question and stays on it, rather than throwing
    # somebody back to the dashboard the way a card row does.
    def filter_params(row)
      query.filter_link_params(dimension.key, row.value).merge(explore.to_query.except(:page))
    end

    def filter_path(row)
      routes.explore_path(filter_params(row))
    end

    def filename
      today = Time.current.in_time_zone(AhoyDashboard.time_zone).to_date.iso8601

      "ahoy-dashboard-explore-#{dimension.key.parameterize}-#{today}.csv"
    end

    private

    def metric_keys
      explore.columns
    end

    def params_for(overrides = {})
      query.to_query.merge(explore.to_query).merge(overrides).compact
    end

    def path_for(query_params)
      routes.explore_path(query_params.merge(explore.to_query.except(:page)))
    end

    def dimension_item(candidate)
      menu_item(candidate.label, query.to_query,
                explore: explore.with(dimension: candidate.key, columns: nil, page: nil).to_query,
                active: candidate.key == dimension.key)
    end

    def menu_item(label, query_params, explore: nil, active: false)
      params = query_params.merge(explore || self.explore.to_query.except(:page))

      { label: label, url: routes.explore_path(params), active: active }
    end
  end
end
