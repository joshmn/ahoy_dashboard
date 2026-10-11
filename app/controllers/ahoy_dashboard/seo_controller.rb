module AhoyDashboard
  class SeoController < AhoyDashboard::Seo::BaseController
    def show
      reading = AhoyDashboard::Seo::HubQuery.call(range: query.range, site: @site)

      present(AhoyDashboard::Seo::HubPresenter, reading: reading)
    end

    private

    # The overview is not one of the surfaces the rail lists under a group, so
    # it wears a registry entry built here rather than one in the list that
    # would then have to be filtered out of every menu.
    def surface
      @surface ||= AhoyDashboard::Seo::Surface.new(
        key: "seo", title: "SEO", group: nil, source: :stored, route: :seo_path, reads: "",
        features: AhoyDashboard::Seo::Surface::FEATURES,
        blurb: "How your site is doing in Google search, and what to work on next."
      )
    end

    def surface_key
      "seo"
    end
  end
end
