require "net/http"

module AhoyDashboard
  # Real favicons for the rows that name a website, fetched here rather than by
  # the operator's browser.
  #
  # The letter chip this replaces was right about the cost of the obvious
  # implementation: one icon request per row, made by the browser, hands a third
  # party the list of everywhere this site's traffic comes from, tied to the
  # operator's address and to the minute they read the dashboard, and it hands it
  # over again on every reload. This is the proxy that comment said did not
  # exist. What the icon host still learns is a domain name, once, from this
  # server, and then not again for a month. What it no longer learns is who
  # asked, from where, when, how often, or that those domains belong to one
  # site's referrer list.
  #
  # Every request goes to a frozen host with a validated label in the path, so
  # nothing that came out of the data can move the request somewhere else.
  class FaviconService
    ICON_HOST = "icons.duckduckgo.com".freeze
    ICON_PATH = "/ip3/%s.ico".freeze
    def self.user_agent
      AhoyDashboard.user_agent
    end

    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 4
    MAX_BYTES = 64.kilobytes

    # An icon does not change, and a domain that has none today will not have one
    # tomorrow either. A timeout says nothing about the domain, so it is held only
    # long enough to stop one dashboard reload retrying every row.
    HIT_TTL = 30.days
    MISSING_TTL = 1.day
    FAILED_TTL = 10.minutes

    MISSING = :missing
    FAILED = :failed

    ICON_KEY = "ahoy_dashboard/favicons/icon".freeze
    DOMAINS_KEY = "ahoy_dashboard/favicons/domains".freeze
    DOMAINS_TTL = 1.hour
    MAX_DOMAINS = 2_000

    # A hostname and only a hostname: no scheme, no userinfo, no port, no path,
    # no trailing dot, no underscore, no leading or trailing hyphen in a label,
    # and a top level domain that is letters or a punycode a-label. That last
    # part is also what refuses an IP address, which is not a site with a favicon.
    # Raw unicode is refused rather than encoded, because ahoy stores the host as
    # it arrived and an a-label is the form the icon host expects.
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

    # A leading www is not a different site, and the domain column is normalised
    # the same way everywhere else that reads it.
    NORMALISED_DOMAIN = Arel.sql(
      "distinct regexp_replace(lower(ahoy_visits.referring_domain), '^www[.]', '')"
    ).freeze

    Icon = Data.define(:bytes, :content_type)

    class << self
      def call(domain)
        new(domain).call
      end

      def enabled?
        AhoyDashboard::Features.on?(:favicons)
      end

      # What a row label turns into. A source row can be a bare domain, a
      # referrer row is a whole URL, and a channel row is a phrase that is no
      # domain at all. nil for anything with no icon to show, which is what
      # leaves the letter chip in place.
      def domain_for(value)
        return unless enabled?

        accept(host_from(value))
      end

      # The one door. A domain nobody in the data referred us from is not worth a
      # request whatever it looks like, so the shape check and the data check are
      # one method and both callers go through it.
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
        Current.favicon_domains ||= AhoyDashboard.cache.fetch(DOMAINS_KEY, expires_in: DOMAINS_TTL) { referring_domains }
      end

      private

      # Capped, because this is held in the cache and read on every row of every
      # source card. The site has dozens of referring domains, not thousands.
      def referring_domains
        AhoyDashboard.visit
          .where.not(referring_domain: [ nil, "" ])
          .limit(MAX_DOMAINS)
          .pluck(NORMALISED_DOMAIN)
          .to_set
      rescue ActiveRecord::StatementInvalid
        Set.new
      end

      # Derivation, not acceptance: it takes the host out of whatever a row
      # printed. The endpoint itself never calls this, so a URL asking for
      # something with a scheme or a port in it is refused rather than tidied up.
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
      "#{ICON_KEY}/#{domain}"
    end

    # AhoyDashboard.cache.fetch cannot vary its expiry by what the block came back with,
    # and the three outcomes here are worth keeping for three different lengths
    # of time, so the read and the write are written out instead.
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

    # Every path out of the block is a return, because Net::HTTP#request hands
    # back the response rather than whatever the block came to, and a response
    # object is not an outcome.
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
      request["User-Agent"] = self.class.user_agent
      request["Accept"] = "image/*"
      request
    end

    # Capped while reading rather than off the header alone: a content length is
    # whatever the other end said it was, and an icon endpoint is not the place to
    # find out what happens when it lied.
    def read(response)
      body = "".b

      response.read_body do |chunk|
        body << chunk.b

        return nil if body.bytesize > MAX_BYTES
      end

      body
    end

    # Worked out from the bytes, never taken off the remote response. This app
    # serves those bytes back from its own origin, so what they actually are
    # matters more than what the sender called them, and anything that is not one
    # of the four raster formats an icon arrives in is refused rather than passed
    # through with a guess.
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
