module AhoyDashboard
  class RankingsController < AhoyDashboard::Seo::BaseController
    def show
      present(AhoyDashboard::Serp::RankingsPresenter, result: overview, visibility: visibility, share: share,
                                                      distribution: distribution, band: params[:band])
    end

    private

    def surface_key
      "rankings"
    end

    def range
      @range ||= AhoyDashboard::Serp::TrackedRangeQuery.call(
        query: query, checks: AhoyDashboard::SerpCheck.where(site_id: @site&.id)
      )
    end

    def overview
      AhoyDashboard::Serp::RankOverviewQuery.call(site: @site, range: range, tag: tag)
    end

    def visibility
      AhoyDashboard::Serp::AiVisibilityQuery.call(site: @site, range: range, tag: tag)
    end

    def distribution
      AhoyDashboard::Serp::RankDistributionQuery.call(site: @site, range: range, tag: tag)
    end

    def share
      AhoyDashboard::Serp::ShareOfPageOneQuery.call(range: range, site: @site, tag: tag)
    end
  end
end
