module AhoyDashboard
  module Serp
    module Domain
      def self.host(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        extracted = raw.include?("//") ? URI.parse(raw).host : raw.split("/").first

        extracted.to_s.strip.downcase.sub(/:\d+\z/, "").delete_prefix("www.").delete_suffix(".").presence
      rescue URI::InvalidURIError
        nil
      end

      def self.matches?(link, domain, match_subdomains: false)
        link_host = host(link)
        domain_host = host(domain)
        return false if link_host.blank? || domain_host.blank?

        link_host == domain_host || (match_subdomains && link_host.end_with?(".#{domain_host}"))
      end
    end
  end
end
