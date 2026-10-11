module AhoyDashboard
  # What the filter dialog shows on the right.
  #
  # No dimension and nothing typed is the help. Something typed with no
  # dimension is the search across every dimension at once. A dimension named is
  # that dimension's values, with the counts they have in the range and under
  # every other filter being built.
  #
  # The dialog swaps this frame as somebody types or picks a dimension off the
  # rail. Asked for as a page, it is the whole dialog laid out flat, and every
  # value is a link that applies it, so filtering still works with the
  # JavaScript off.
  class FilterValuesController < AhoyDashboard::BaseController
    include AhoyDashboard::FilterOptionScope

    FRAME = "dash_filter_results".freeze

    # Fifty is a long list to scroll and the box above it narrows past that.
    # Under FilterOptionsQuery::MAX_LIMIT with room for the one extra row that
    # says there are more.
    LIMIT = 50

    def index
      @dimension = AhoyDashboard::Dimension.find_by_key(params[:dimension]) if params[:dimension].present?
      @term = params[:q].to_s
      @values = @dimension ? values : []
      @groups = @dimension ? [] : groups
      @live = frame_request?
      @destination = params[:return]
      @carried = carried
      @collect = collect?

      render partial: "ahoy_dashboard/filter_values/panel", locals: panel if @live
    end

    private

    def panel
      { dimension: @dimension, values: @values, groups: @groups, term: @term, live: @live,
        collect: @collect, destination: @destination, carried: @carried }
    end

    # One more than the cap, so the pane knows to say there are more without
    # counting everything the dimension holds.
    def values
      AhoyDashboard::FilterOptionsQuery.call(
        scope: dimension_scope(@dimension),
        dimension: @dimension,
        query: @term.presence,
        limit: LIMIT + 1,
        counted: true
      )
    end

    def groups
      return [] if @term.strip.length < AhoyDashboard::FacetSearchQuery::MINIMUM_TERM

      AhoyDashboard::FacetSearchQuery.call(scope: dimension_scope(nil), term: @term)
    end
  end
end
