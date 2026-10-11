module AhoyDashboard
  class RankingsController < AhoyDashboard::BaseController
    include AhoyDashboard::SeoRange
    include AhoyDashboard::CsvRenderable
    include AhoyDashboard::SeoInstallGate

    requires_installed :serp

    def show
      @sites = AhoyDashboard::SerpSite.own_first
      @site = chosen_site
      @presenter = AhoyDashboard::Serp::RankingsPresenter.new(
        query: query, result: overview, visibility: visibility, share: share,
        site: @site, sites: @sites, distribution: distribution, band: params[:band],
        tag: tag, tags: AhoyDashboard::SerpKeyword.tags_in_use
      )
      @realtime = AhoyDashboard::RealtimeQuery.call
      @tag = tag
    end

    private

    def tag
      params[:tag].presence
    end

    def chosen_site
      return @sites.find { |site| site.id == params[:site].to_i } if params[:site].present?

      AhoyDashboard::SerpSite.ours || @sites.first
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
