module AhoyDashboard
  class RankKeywordsController < AhoyDashboard::BaseController
    include AhoyDashboard::SeoRange
    include AhoyDashboard::CsvRenderable
    include AhoyDashboard::SeoInstallGate

    requires_installed :serp

    def show
      return redirect_to(rankings_path(query.to_query)) if params[:keyword].blank? && params[:q].to_s.strip.blank?

      @keyword = AhoyDashboard::Serp::KeywordLookupQuery.call(id: params[:keyword], text: params[:q], location: params[:at])
      raise ActiveRecord::RecordNotFound, "no tracked keyword" if @keyword.nil?
      return redirect_to(canonical_path, status: :moved_permanently) if params[:keyword].blank?

      @site = site
      @presenter = AhoyDashboard::Serp::KeywordPresenter.new(query: query, result: result)
      set_seo_back(fallback_label: "Rankings", fallback_url: @presenter.rankings_path) if request_format == :html
    end

    private

    def canonical_path
      rank_keyword_path(request.query_parameters.except("q", "keyword").merge("keyword" => @keyword.id))
    end

    def range
      AhoyDashboard::Serp::TrackedRangeQuery.call(
        query: query, checks: AhoyDashboard::SerpCheck.where(keyword_id: @keyword.id)
      )
    end

    def site
      @site ||= if params[:site].present?
        AhoyDashboard::SerpSite.find_by(id: params[:site])
      else
        AhoyDashboard::SerpSite.ours || @keyword.sites.first
      end
    end

    def result
      AhoyDashboard::Serp::KeywordSeriesQuery.call(
        keyword: @keyword, site: site, range: range, location: params[:at]
      )
    end
  end
end
