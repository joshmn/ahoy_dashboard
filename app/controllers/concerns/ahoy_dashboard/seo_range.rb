module AhoyDashboard
  module SeoRange
    extend ActiveSupport::Concern

    COOKIE = "dash_seo_view".freeze
    EXPIRY = 90.days
    KEYS = %i[period from to comparison].freeze
    RANGE_KEYS = %w[period from to interval].freeze

    included do
      after_action :remember_seo_range, if: :seo_page?
    end

    private

    def query
      @query ||= AhoyDashboard::QueryForm.from_params(seo_range_params, remembered: cookies[COOKIE])
    end

    def seo_range_params
      return params if frame_request?

      source = params.to_unsafe_h
      source = source.except(*RANGE_KEYS) if AhoyDashboard::Seo::Periods::TOO_SHORT.include?(source[:period].to_s)
      return source if source[:period].present? || seo_cookie_applies?(source)

      source.merge(period: AhoyDashboard::Seo::Periods.wide.key)
    end

    def seo_cookie_applies?(source)
      cookies[COOKIE].present? && AhoyDashboard::QueryForm::URL_KEYS.none? { |key| source[key].present? }
    end

    def remember_seo_range
      return unless AhoyDashboard::Seo::Periods.wide_enough?(query)

      cookies[COOKIE] = {
        value: query.to_query.slice(*KEYS).to_query,
        expires: EXPIRY.from_now,
        httponly: true,
        same_site: :lax
      }
    end

    def seo_page?
      request.get? && request_format == :html && !frame_request? && response.successful?
    end
  end
end
