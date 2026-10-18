module AhoyDashboard
  module Seo
    class BaseController < AhoyDashboard::BaseController
      include AhoyDashboard::SeoRange
      include AhoyDashboard::CsvRenderable

      before_action { require_installed!(*surface.features) }
      before_action :set_sites, if: -> { request.get? || request.head? }
      before_action :set_tag

      private

      def seo_navigation?
        true
      end

      def surface
        Surface.find(surface_key)
      end

      def surface_key
        raise NotImplementedError
      end

      def require_installed!(*names)
        state = FeatureState.for(names)
        return if state.installed?
        return super unless request_format == :html && (request.get? || request.head?) && !error_frame_id

        render "ahoy_dashboard/seo/not_installed", locals: { state: state, title: surface.title, current: surface_key }
      end

      def set_sites
        @sites = serp? ? AhoyDashboard::SerpSite.own_first : []
        @site = chosen_site
      end

      def serp?
        AhoyDashboard::Serp.installed?
      end

      def chosen_site
        return unless serp?
        return @sites.find { |site| site.id == params[:site].to_i } if params[:site].present?

        @sites.first
      end

      def set_tag
        @tag = params[:tag].presence
      end

      def tag
        @tag
      end

      def slice
        @slice ||= AhoyDashboard::SearchConsole::Slice.from_params(params)
      end

      def search_console_context(countries:, history: false)
        return SearchConsole::PageContext.new unless request_format == :html

        SearchConsole::PageContextQuery.call(range: query.range, countries: countries, history: history)
      end

      def set_seo_back(fallback_label:, fallback_url:)
        @back = ReturnLinkPresenter.new(
          host: request.host, path: request.path, referer: request.referer, remembered: session[:seo_back],
          fallback_label: fallback_label, fallback_url: fallback_url
        )
        session[:seo_back] = @back.memory
      end

      def present(presenter_class, **options)
        result = options[:result]
        search_context = if request_format == :html && surface.features.include?(:search_console)
          search_console_context(countries: BasePresenter::SLICEABLE.include?(surface.key), history: result && !result.any?)
        else
          SearchConsole::PageContext.new
        end
        @presenter = presenter_class.new(query: query, surface: surface, site: @site,
                                         sites: @sites, slice: slice, tag: tag,
                                         search_console_context: search_context,
                                         tags: serp? && request_format == :html ? AhoyDashboard::SerpKeyword.tags_in_use : [], **options)
        track_phrases
      end

      def track_phrases
        return unless request_format == :html && @presenter.respond_to?(:tracking_phrases)

        @tracked_keywords = TrackedKeywordsPresenter.new(phrases: @presenter.tracking_phrases)
      end
    end
  end
end
