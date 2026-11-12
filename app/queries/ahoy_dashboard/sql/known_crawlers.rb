module AhoyDashboard
  module Sql
    class KnownCrawlers
      COLUMN = "ahoy_visits.user_agent".freeze
      LOWERED = %(lower(#{COLUMN} collate "C")).freeze

      NAMES = [
        "Mediapartners-Google", "AdsBot-Google", "Googlebot", "FeedFetcher-Google", "Storebot-Google",
        "Google-InspectionTool", "GoogleOther", "Google Favicon", "Calypso AppCrawler",
        "BingBot", "BingPreview", "Baiduspider", "Slurp", "Sogou", "YandexBot", "Yeti/", "naver.me/spd",
        "facebookexternalhit", "facebookcatalog", "meta-externalagent", "meta-externalfetcher", "ia_archiver",
        "Slackbot", "Slack-ImgProxy", "Discordbot", "TelegramBot", "WhatsApp/", "LinkedInBot", "Twitterbot",
        "Pinterestbot", "pingdom", "lyticsbot", "AWS Security Scanner", "HubSpot Crawler", "Bytespider",
        "Better Uptime", "UptimeRobot", "Cloudflare-Healthchecks", "GTmetrix", "BrightEdgeOnCrawl",
        "ELB-HealthChecker", "ClaudeBot", "Claude-User", "Claude-SearchBot", "anthropic-ai", "CCBot",
        "OAI-SearchBot", "GPTBot", "ChatGPT-User", "PerplexityBot", "Perplexity-User", "Applebot",
        "DuckDuckBot", "Amazonbot", "AhrefsBot", "SemrushBot", "MJ12bot", "DotBot", "PetalBot", "Lightpanda",
        "HeadlessChrome", "Chrome-Lighthouse", "python-requests", "python-urllib", "aiohttp", "Go-http-client",
        "curl/", "Wget/", "okhttp", "axios/", "node-fetch", "Scrapy", "libwww-perl", "Java/", "Apache-HttpClient"
      ].freeze

      GENERIC = [
        "bots?([/[:space:]);]|$)",
        "spider([/[:space:]);]|$)",
        "crawler([/[:space:]);]|$)"
      ].freeze

      ALLOWED = [ "cubot" ].freeze

      BROWSER_PREFIX = "Mozilla/".freeze
      GUARD = %w[bot spider crawl google bing http headless lighthouse lightpanda claude gtmetrix pingdom scanner perplexity].freeze

      class << self
        def switched_on?
          Preferences.read(:site, :hide_known_crawlers)
        end

        def readable?
          AhoyDashboard.visit.column_names.include?("user_agent")
        rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
          false
        end

        def enabled?
          switched_on? && readable?
        end

        def condition
          return nil unless enabled?

          connection = AhoyDashboard.visit.connection

          <<~SQL.squish
            (case when left(#{COLUMN}, #{BROWSER_PREFIX.length}) <> #{connection.quote(BROWSER_PREFIX)}
                    or #{LOWERED} like any (#{like_array(connection, GUARD)})
                  then (#{LOWERED} like any (#{like_array(connection, NAMES)})
                        or #{LOWERED} ~ #{connection.quote(GENERIC.join('|'))})
                       and not #{LOWERED} like any (#{like_array(connection, ALLOWED)})
                  else false end)
          SQL
        end

        private

        def like_array(connection, words)
          "array[#{words.map { |word| connection.quote("%#{like_escape(word.downcase)}%") }.join(', ')}]"
        end

        def like_escape(text)
          text.gsub(/[\\%_]/) { |character| "\\#{character}" }
        end
      end
    end
  end
end
