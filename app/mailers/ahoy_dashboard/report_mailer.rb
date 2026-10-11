module AhoyDashboard
  class ReportMailer < Reports::Digests.parent_mailer
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

      mail(**{ to: params.fetch(:recipients), from: Reports::Digests.from, subject: @digest.subject,
               template_path: _prefixes }.compact)
    end

    private

    def dashboard_url(name, **params)
      AhoyDashboard::Engine.routes.url_helpers.public_send(:"#{name}_url", **default_url_options, **params)
    end

    def period_params(window)
      { period: AhoyDashboard::Period::CUSTOM_KEY,
        from: window.starts_on.strftime(AhoyDashboard::Period::DATE_FORMAT),
        to: window.ends_on.strftime(AhoyDashboard::Period::DATE_FORMAT) }
    end

    def site_host
      AhoyDashboard.host || default_url_options[:host]
    end
  end
end
