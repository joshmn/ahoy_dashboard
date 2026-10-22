require "net/http"

module AhoyDashboard
  class FaviconService
    ICON_HOST = "icons.duckduckgo.com".freeze
    ICON_PATH = "/ip3/%s.ico".freeze

    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 4
    MAX_BYTES = 64.kilobytes

    HIT_TTL = 30.days
    MISSING_TTL = 1.day
    FAILED_TTL = 10.minutes

    MISSING = :missing
    FAILED = :failed

    ICON_KEY = "ahoy_dashboard/favicons/icon".freeze
    DOMAINS_KEY = "ahoy_dashboard/favicons/domains".freeze
    DOMAINS_TTL = 1.hour
    DOMAINS_WINDOW = 90.days
    MAX_DOMAINS = 2_000

    MAX_LENGTH = 253
    LABEL = /[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?/
    TLD = /(?:[a-z]{2,63}|xn--[a-z0-9-]{2,59})/
    HOSTNAME = /\A#{LABEL}(?:\.#{LABEL})*\.#{TLD}\z/
    SCHEME = %r{\A[a-z][a-z0-9+.-]*://}
    PATH_START = %r{[/?#]}

    ICO_TYPE = "image/vnd.microsoft.icon".freeze
    WEBP_TYPE = "image/webp".freeze
    RIFF_MAGIC = "RIFF".b.freeze
    WEBP_MAGIC = "WEBP".b.freeze

    CONTENT_TYPES = {
      "image/png" => "\x89PNG\r\n\x1a\n".b.freeze,
      "image/gif" => "GIF8".b.freeze,
      "image/jpeg" => "\xFF\xD8\xFF".b.freeze,
      ICO_TYPE => "\x00\x00\x01\x00".b.freeze
    }.freeze

    NORMALISED_DOMAIN = Arel.sql(
      "regexp_replace(lower(ahoy_visits.referring_domain), '^www[.]', '')"
    ).freeze
    LATEST_FIRST = Arel.sql("max(started_at) desc").freeze

    Icon = Data.define(:bytes, :content_type)

    class << self
      def call(domain)
        new(domain).call
      end

      def enabled?
        AhoyDashboard::Features.on?(:favicons)
      end

      def domain_for(value)
        return unless enabled?

        accept(host_from(value))
      end

      def accept(value)
        domain = value.to_s.strip.downcase

        return unless domain.length.between?(1, MAX_LENGTH)
        return unless domain.match?(HOSTNAME)
        return unless known?(domain)

        domain
      end

      def known?(domain)
        known_domains.include?(domain)
      end

      def known_domains
        key = AnalyticsCache.key(key: DOMAINS_KEY, connection: AhoyDashboard.visit.connection)
        Current.favicon_domains ||= AhoyDashboard.cache.fetch(key, expires_in: DOMAINS_TTL) { referring_domains }
      end

      def cache_key(domain)
        "#{ICON_KEY}/#{domain}"
      end

      private

      def referring_domains
        visits = AhoyDashboard.visit

        visits.where.not(referring_domain: [ nil, "" ])
          .where(visits.arel_table[:started_at].gteq(Time.current - DOMAINS_WINDOW))
          .group(NORMALISED_DOMAIN)
          .order(LATEST_FIRST)
          .limit(MAX_DOMAINS)
          .pluck(NORMALISED_DOMAIN)
          .to_set
      rescue ActiveRecord::StatementInvalid
        Set.new
      end

      def host_from(value)
        host = value.to_s.strip.downcase.sub(SCHEME, "")
        host = host.split(PATH_START).first.to_s
        host = host.rpartition("@").last
        host = host.split(":").first.to_s

        host.delete_prefix("www.").delete_suffix(".")
      end
    end

    def initialize(domain)
      @domain = self.class.accept(domain)
    end

    def call
      return unless self.class.enabled?
      return if domain.nil?

      outcome = AhoyDashboard.cache.read(cache_key) || store(fetch)

      outcome.is_a?(Icon) ? outcome : nil
    end

    def cached
      return unless self.class.enabled?
      return if domain.nil?

      outcome = AhoyDashboard.cache.read(cache_key)
      outcome if outcome.is_a?(Icon)
    end

    private

    attr_reader :domain

    def cache_key
      self.class.cache_key(domain)
    end

    def store(outcome)
      AhoyDashboard.cache.write(cache_key, outcome, expires_in: ttl(outcome))

      outcome
    end

    def ttl(outcome)
      case outcome
      when Icon then HIT_TTL
      when FAILED then FAILED_TTL
      else MISSING_TTL
      end
    end

    def fetch
      Net::HTTP.start(ICON_HOST, 443, use_ssl: true,
        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(icon_request) do |response|
          return MISSING unless response.is_a?(Net::HTTPSuccess)
          return MISSING if response["content-length"].to_i > MAX_BYTES

          body = read(response)

          return body.nil? ? MISSING : icon_for(body)
        end
      end

      MISSING
    rescue StandardError => e
      Rails.logger.warn "duckduckgo favicon fetch failed: #{e.class}: #{e.message}"
      FAILED
    end

    def icon_request
      request = Net::HTTP::Get.new(URI::HTTPS.build(host: ICON_HOST, path: format(ICON_PATH, domain)))
      request["User-Agent"] = AhoyDashboard.user_agent
      request["Accept"] = "image/*"
      request
    end

    def read(response)
      body = "".b

      response.read_body do |chunk|
        body << chunk.b

        return nil if body.bytesize > MAX_BYTES
      end

      body
    end

    def icon_for(body)
      type = content_type_for(body)

      type.nil? ? MISSING : Icon.new(bytes: body, content_type: type)
    end

    def content_type_for(body)
      match = CONTENT_TYPES.find { |_type, magic| body.start_with?(magic) }

      return match.first if match
      return WEBP_TYPE if body.start_with?(RIFF_MAGIC) && body.byteslice(8, 4) == WEBP_MAGIC

      nil
    end
  end
end
