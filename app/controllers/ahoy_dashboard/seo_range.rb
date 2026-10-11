module AhoyDashboard
  module SeoRange
    extend ActiveSupport::Concern

    COOKIE = "dash_seo_view".freeze
    EXPIRY = 90.days
    KEYS = %i[period from to comparison].freeze
    RANGE_KEYS = %w[period from to interval].freeze
    FLOOR_DAYS = 28
    TOO_SHORT = %w[realtime day yesterday].freeze
    EVERYTHING = "all".freeze

    included do
      after_action :remember_seo_range, if: :seo_page?
    end

    def self.periods
      AhoyDashboard::Period::ALL.reject { |period| TOO_SHORT.include?(period.key) }
    end

    def self.wide_period
      AhoyDashboard::Period.find("28d")
    end

    def self.widen_label
      "Show the #{wide_period.label.downcase}"
    end

    def self.widened(query)
      query.with(period: wide_period.key, from: nil, to: nil).to_query
    end

    def self.wide_enough?(query)
      return true if query.period.key == EVERYTHING

      range = query.range
      return false if range.nil? || TOO_SHORT.include?(query.period.key)

      (range.end.to_date - range.begin.to_date).to_i + 1 >= FLOOR_DAYS
    end

    private

    def query
      @query ||= AhoyDashboard::QueryForm.from_params(seo_range_params, remembered: cookies[COOKIE])
    end

    def seo_range_params
      return params if frame_request?

      source = params.to_unsafe_h
      source = source.except(*RANGE_KEYS) if TOO_SHORT.include?(source[:period].to_s)
      return source if source[:period].present? || seo_cookie_applies?(source)

      source.merge(period: AhoyDashboard::SeoRange.wide_period.key)
    end

    def seo_cookie_applies?(source)
      cookies[COOKIE].present? && AhoyDashboard::QueryForm::URL_KEYS.none? { |key| source[key].present? }
    end

    def remember_seo_range
      return unless AhoyDashboard::SeoRange.wide_enough?(query)

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
