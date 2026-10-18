module AhoyDashboard
  class ExploresController < AhoyDashboard::BaseController
    def show
      @explore = AhoyDashboard::ExploreForm.from_params(params, charted: query.metric.key)
      @explore = @explore.with(saved: nil) if @explore.saved_id && saved_query.nil?

      respond_to do |format|
        format.html { assign_question }
        format.csv { stream_csv(presenter(limit: nil).csv_filename, presenter(limit: nil).csv_rows) }
      end
    end

    private

    def saved_query
      return @saved_query if defined?(@saved_query)

      @saved_query = (AhoyDashboard::SavedQuery.find_by(id: params[:saved]) if params[:saved].present?)
    end

    def assign_question
      @realtime = AhoyDashboard::RealtimeQuery.call
      presenter.saved_query = saved_query
      @series = series(query.scope)
      @comparison_series = query.comparison_scope && series(query.comparison_scope)
      @chart = AhoyDashboard::DashboardPresenter.new(
        query: query,
        series: @series,
        comparison_series: @comparison_series,
        annotations: AhoyDashboard::ChartAnnotationsQuery.call(range: query.range, bucket: query.interval),
        realtime: @realtime
      )
      presenter
    end

    def series(scope)
      AhoyDashboard::TimeseriesQuery.call(scope: scope, metric: query.metric, interval: query.interval)
    end

    def presenter(limit: @explore.limit)
      @presenter ||= AhoyDashboard::ExplorePresenter.new(
        query: query,
        explore: @explore,
        result: answer = result(limit: limit),
        row_total: (row_total(answer) unless limit.nil? && request.format.csv?)
      )
    end

    def row_total(answer)
      shown = @explore.offset + answer.rows.size
      return shown unless answer.more?
      return if @explore.goal?

      @row_count
    end

    def result(limit:)
      if @explore.goal?
        AhoyDashboard::GoalsQuery.call(scope: query.scope, term: @explore.term, limit: limit, offset: offset(limit))
      else
        options = {
          scope: query.scope,
          dimension: @explore.dimension,
          metrics: @explore.columns,
          limit: limit,
          offset: offset(limit),
          search: search
        }
        return AhoyDashboard::BreakdownQuery.call(**options) if request.format.csv?

        counted = AhoyDashboard::BreakdownQuery.with_row_count(**options)
        @row_count = counted.row_count
        counted.result
      end
    end

    def offset(limit)
      limit.nil? ? 0 : @explore.offset
    end

    def search
      AhoyDashboard::DetailsSearchQuery.condition(dimension: @explore.dimension, term: @explore.term)
    end
  end
end
