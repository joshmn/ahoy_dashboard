module AhoyDashboard
  module Seo
    class BrandTerms
      KEY = "seo_brand_terms".freeze
      LIMIT = 20
      MAX_LENGTH = 80
      SEPARATOR = /[,\n]/

      class << self
        def current
          stored = parse(Array(AhoyDashboard::Setting.read(KEY)).join(","))

          stored.presence || default
        end

        def stored?
          Array(AhoyDashboard::Setting.read(KEY)).any?
        end

        def parse(text)
          text.to_s.split(SEPARATOR)
            .map { |term| term.squish.first(MAX_LENGTH) }
            .reject(&:blank?)
            .uniq { |term| fold(term) }
            .first(LIMIT)
        end

        def default
          label = AhoyDashboard.host.to_s.downcase.delete_prefix("www.").split(".").first.to_s
          return [] if label.blank?

          words = label.tr("-_", " ").squish

          [ words, label.delete("-_") ].uniq { |term| fold(term) }
        end

        def fold(term)
          term.to_s.downcase.gsub(/[\s-]+/, "")
        end
      end
    end
  end
end
