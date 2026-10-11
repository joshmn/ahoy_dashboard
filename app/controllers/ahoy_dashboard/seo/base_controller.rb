module AhoyDashboard
  module Seo
    # Everything under the suite. Nothing here answers a filter: a serp row and a
    # search console row carry no visitor and no session, so narrowing by browser
    # or country would silently return the same page and read as a broken filter
    # rather than an absent one.
    #
    # A range is different. Every one of these has a date on it, so the range
    # control is real everywhere.
    class BaseController < AhoyDashboard::BaseController
      include AhoyDashboard::SeoRange
      include AhoyDashboard::CsvRenderable
      include AhoyDashboard::SeoInstallGate

      before_action { require_installed!(*surface.features) }
      before_action :set_sites
      before_action :set_tag

      private

      def surface
        Surface.find(surface_key)
      end

      # Named off the controller rather than declared on each one, so a new
      # surface is a route, a controller and a registry entry with nothing to
      # keep in step by hand.
      def surface_key
        raise NotImplementedError
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

        AhoyDashboard::SerpSite.ours || @sites.first
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

      def present(presenter_class, **options)
        result = options[:result]
        search_context = if request_format == :html && surface.features.include?(:search_console)
          SearchConsole::PageContextQuery.call(range: query.range,
            countries: BasePresenter::SLICEABLE.include?(surface.key), history: result && !result.any?)
        else
          SearchConsole::PageContext.new
        end
        @presenter = presenter_class.new(query: query, surface: surface, site: @site,
                                         sites: @sites, slice: slice, tag: tag,
                                         search_console_context: search_context,
                                         tags: serp? ? AhoyDashboard::SerpKeyword.tags_in_use : [], **options)
        if request_format == :html && @presenter.respond_to?(:tracking_phrases)
          @tracked_keywords = TrackedKeywordsPresenter.new(phrases: @presenter.tracking_phrases)
        end
      end
    end
  end
end
