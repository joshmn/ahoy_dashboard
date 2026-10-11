require "csv"

module AhoyDashboard
  # One composed question. The dashboard asks about twenty questions somebody
  # decided in advance; this asks whichever one is in the URL.
  #
  # Every part of it already existed: QueryForm parses the range, the filters and
  # the charted metric, ScopeQuery turns that into a Scope, and BreakdownQuery
  # answers it against any dimension in the registry. What was missing was a
  # surface that let the dimension be chosen rather than hardcoded into a card.
  class ExploresController < AhoyDashboard::BaseController
    def show
      @explore = AhoyDashboard::ExploreForm.from_params(params, charted: query.metric.key)
      @explore = @explore.with(saved: nil) if @explore.saved_id && saved_query.nil?

      respond_to do |format|
        format.html { assign_question }
        format.csv { stream_csv(presenter(limit: nil).filename, rows) }
      end
    end

    private

    # A saved question that no longer exists is a stale link, and the answer is
    # the question without it rather than a 404: everything needed to read it is
    # in the query string either way.
    def saved_query
      return @saved_query if defined?(@saved_query)

      @saved_query = (AhoyDashboard::SavedQuery.find_by(id: params[:saved]) if params[:saved].present?)
    end

    def assign_question
      @realtime = AhoyDashboard::RealtimeQuery.call
      # Arrived here from a saved question, so the save control offers to change
      # that one rather than to write a second one saying nearly the same thing.
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

    # The goals dimension is the goals table rather than a group by, so it pages
    # and matches in Ruby the way the goals card already does.
    def result(limit:)
      if @explore.goal?
        AhoyDashboard::DetailsSearchQuery.goals(
          scope: query.scope, term: @explore.term, limit: limit, offset: offset(limit)
        )
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

    # A download is the whole list rather than the page somebody is standing on.
    # It does honour the find term, unlike the card's export, because here the
    # term is in the URL the download was built from: a file that answered a
    # wider question than the address bar says would be the surprising one.
    def offset(limit)
      limit.nil? ? 0 : @explore.offset
    end

    def search
      AhoyDashboard::DetailsSearchQuery.condition(dimension: @explore.dimension, term: @explore.term)
    end

    # No row count. A limit on an export is a number somebody has to discover by
    # noticing their spreadsheet is short.
    def rows
      view = presenter(limit: nil)

      Enumerator.new do |out|
        out << view.header_row
        view.rows.each { |row| out << [ row.display_label, *row.raw_values ] }
      end
    end
  end
end
