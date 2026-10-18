module AhoyDashboard
  module Seo
    module Referer
      class << self
        def local_uri(referer, host:)
          uri = URI.parse(referer.to_s)
          return nil if uri.host.present? && uri.host != host
          return nil unless uri.path.to_s.start_with?("/")

          uri
        rescue URI::InvalidURIError
          nil
        end

        def local_path(referer, host:)
          uri = local_uri(referer, host: host)

          uri && full_path(uri)
        end

        def full_path(uri)
          [ uri.path, uri.query.presence ].compact.join("?")
        end
      end
    end
  end
end
