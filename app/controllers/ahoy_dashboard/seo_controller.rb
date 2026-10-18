module AhoyDashboard
  class SeoController < AhoyDashboard::Seo::BaseController
    def show
      reading = AhoyDashboard::Seo::HubQuery.call(range: query.range, site: @site)

      present(AhoyDashboard::Seo::HubPresenter, reading: reading)
    end

    private

    def surface
      @surface ||= AhoyDashboard::Seo::Surface.new(
        key: "seo", title: "SEO", group: nil, source: :stored, route: :seo_path, reads: "search_console_rows",
        features: AhoyDashboard::Seo::Surface::FEATURES,
        blurb: "How your site is doing in Google search, and what to work on next."
      )
    end

    def surface_key
      "seo"
    end
  end
end
