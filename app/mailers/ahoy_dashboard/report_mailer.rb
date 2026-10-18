module AhoyDashboard
  class ReportMailer < Reports::Digests.parent_mailer
    include DigestMailing

    layout "ahoy_dashboard/mailer"

    def digest
      record = params.fetch(:digest)
      window = record.window
      result = params[:result] || Reports::DigestQuery.call(window: window)

      @digest = Reports::DigestPresenter.new(result, host: site_host)
      @dates = period_params(window)
      @dashboard_url = dashboard_url(:root, **@dates)
      @tile_urls = @digest.tiles.index_by(&:key).transform_values { |tile| dashboard_url(:root, metric: tile.key, **@dates) }
      @list_urls = @digest.lists.index_by(&:key)
        .transform_values { |list| dashboard_url(:explore, dimension: list.dimension_key, **@dates) }

      digest_mail(from: Reports::Digests.from, subject: @digest.subject)
    end
  end
end
