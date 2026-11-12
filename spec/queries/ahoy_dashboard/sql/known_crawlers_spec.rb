require "rails_helper"

RSpec.describe AhoyDashboard::Sql::KnownCrawlers do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:at) { dash_time(2026, 8, 10, 9) }

  let(:crawlers) do
    [
      "Mediapartners-Google",
      "AdsBot-Google (+http://www.google.com/adsbot.html)",
      "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
      "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
      "FeedFetcher-Google; (+http://www.google.com/feedfetcher.html)",
      "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)",
      "Mozilla/5.0 (compatible; Baiduspider/2.0; +http://www.baidu.com/search/spider.html)",
      "Mozilla/5.0 (compatible; Yahoo! Slurp; http://help.yahoo.com/help/us/ysearch/slurp)",
      "Sogou web spider/4.0(+http://www.sogou.com/docs/help/webmasters.htm#07)",
      "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)",
      "meta-externalagent/1.1 (+https://developers.facebook.com/docs/sharing/webmasters/crawler)",
      "ia_archiver (+http://www.alexa.com/site/help/webmasters; crawler@alexa.com)",
      "Slackbot-LinkExpanding 1.0 (+https://api.slack.com/robots)",
      "Slackbot 1.0 (+https://api.slack.com/robots)",
      "Pingdom.com_bot_version_1.4_(http://www.pingdom.com/)",
      "AWS Security Scanner",
      "HubSpot Crawler 2.0 http://www.hubspot.com/",
      "Mozilla/5.0 (Linux; Android 5.0) AppleWebKit/537.36 (KHTML, like Gecko) Mobile Safari/537.36 (compatible; Bytespider; spider-feedback@bytedance.com)",
      "Better Uptime Bot Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
      "Cloudflare-Healthchecks/1.0",
      "GTmetrix",
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 GTmetrix",
      "Mozilla/5.0 (Unknown; Linux x86_64) AppleWebKit/534.34 (KHTML, like Gecko) PingdomTMS/0.8.5 Safari/534.34",
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Chrome-Lighthouse",
      "ELB-HealthChecker/2.0",
      "Mozilla/5.0 (compatible; Yeti/1.1; +https://naver.me/spd)",
      "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; ClaudeBot/1.0; +claudebot@anthropic.com)",
      "CCBot/2.0 (https://commoncrawl.org/faq/)",
      "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko); compatible; OAI-SearchBot/1.0; +https://openai.com/searchbot",
      "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko); compatible; GPTBot/1.1; +https://openai.com/gptbot",
      "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko); compatible; ChatGPT-User/1.0; +https://openai.com/bot",
      "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; PerplexityBot/1.0; +https://perplexity.ai/perplexitybot)",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.1.1 Safari/605.1.15 (Applebot/0.1; +http://www.apple.com/go/applebot)",
      "DuckDuckBot/1.1; (+http://duckduckgo.com/duckduckbot.html)",
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Lightpanda/1.0 Safari/537.36",
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/120.0.0.0 Safari/537.36",
      "Mozilla/5.0 (compatible; AhrefsBot/7.0; +http://ahrefs.com/robot/)",
      "Mozilla/5.0 (compatible; SemrushBot/7~bl; +http://www.semrush.com/bot.html)",
      "Twitterbot/1.0",
      "Discordbot/2.0; +https://discordapp.com",
      "curl/8.4.0",
      "python-requests/2.31.0",
      "Go-http-client/1.1",
      "Wget/1.21.4",
      "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/534+ (KHTML, like Gecko) BingPreview/1.0b",
      "Mozilla/5.0 (compatible; Google-InspectionTool/1.0;)",
      "Mozilla/5.0 (compatible; GoogleOther)",
      "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; Claude-User/1.0; +Claude-User@anthropic.com)",
      "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; Perplexity-User/1.0; +https://perplexity.ai/perplexity-user)",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/8.0.2 Safari/600.2.5 (Amazonbot/0.1; +https://developer.amazon.com/support/amazonbot)",
      "Mozilla/5.0 (Linux; Android 5.0) AppleWebKit/537.36 (KHTML, like Gecko) Mobile Safari/537.36 (compatible; TikTokSpider; ttspider-feedback@tiktok.com)",
      "Scrapy/2.11.0 (+https://scrapy.org)",
      "Java/17.0.2",
      "WhatsApp/2.23.20.0",
      "SomeNewThing bot",
      "Mozilla/5.0 (compatible; ExampleBot/1.0)",
      "ExampleSpider/3.1",
      "examplecrawler/1.0"
    ]
  end

  let(:people) do
    [
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0",
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1",
      "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36",
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [FBAN/FBIOS;FBAV/440.0.0.0;FBBV/1;FBDV/iPhone15,2;FBMD/iPhone;FBSN/iOS;FBSV/17.0;FBSS/3;FBID/phone;FBLC/en_US;FBOP/5]",
      "Mozilla/5.0 (Linux; Android 9; CUBOT P30) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
      "Mozilla/5.0 (Linux; Android 10; CUBOT KINGKONG 5 PRO) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Slack/4.41.105 Chrome/130.0.6723.59 Electron/33.0.2 Safari/537.36 Sonic Slack_SSB/4.41.105"
    ]
  end

  def matched(agents)
    connection = AhoyDashboard.visit.connection
    values = agents.map { |agent| "(#{connection.quote(agent)}::text)" }.join(", ")

    connection.select_values(<<~SQL)
      select user_agent from (values #{values}) as ahoy_visits(user_agent) where coalesce(#{described_class.condition}, false)
    SQL
  end

  describe ".condition" do
    it "is nil while the switch is off" do
      expect(described_class).not_to be_enabled
      expect(described_class.condition).to be_nil
    end

    it "matches every known crawler" do
      with_ahoy_dashboard_settings(:site, hide_known_crawlers: true) do
        expect(crawlers - matched(crawlers)).to be_empty
      end
    end

    it "matches every listed name at the start of a user agent" do
      agents = described_class::NAMES.map { |name| "#{name} 1.0" }

      with_ahoy_dashboard_settings(:site, hide_known_crawlers: true) do
        expect(agents - matched(agents)).to be_empty
      end
    end

    it "leaves ordinary browsers alone" do
      with_ahoy_dashboard_settings(:site, hide_known_crawlers: true) do
        expect(matched(people)).to be_empty
      end
    end

    it "never matches a missing user agent" do
      with_ahoy_dashboard_settings(:site, hide_known_crawlers: true) do
        connection = AhoyDashboard.visit.connection
        value = connection.select_value(
          "select (#{described_class.condition}) is true from (values (null::text)) as ahoy_visits(user_agent)"
        )

        expect(value).to be(false)
      end
    end

    it "is off when the visits table has no user_agent column" do
      allow(AhoyDashboard.visit).to receive(:column_names).and_return(%w[id visitor_token started_at])

      with_ahoy_dashboard_settings(:site, hide_known_crawlers: true) do
        expect(described_class).not_to be_enabled
        expect(described_class.condition).to be_nil
      end
    end
  end

  describe "the scope" do
    def visitors(**options)
      dash_scope(range: range, **options).visits.pluck(:visitor_token).sort
    end

    before do
      dash_landing(at: at, visitor: "person", user_agent: people.first)
      dash_landing(at: at, visitor: "googlebot", user_agent: crawlers[2])
      dash_landing(at: at, visitor: "unknown", user_agent: nil)
    end

    it "counts crawlers while the switch is off" do
      expect(visitors).to eq(%w[googlebot person unknown])
    end

    it "leaves crawlers out when the switch is on" do
      with_ahoy_dashboard_settings(:site, hide_known_crawlers: true) do
        expect(visitors).to eq(%w[person unknown])
        expect(AhoyDashboard::Sql::ExcludedTraffic).to be_enabled
      end
    end

    it "puts them back with the hidden traffic switch" do
      with_ahoy_dashboard_settings(:site, hide_known_crawlers: true) do
        expect(visitors(include_internal: true)).to eq(%w[googlebot person unknown])
      end
    end

    it "counts them as hidden visits" do
      with_ahoy_dashboard_settings(:site, hide_known_crawlers: true, internal_ips: []) do
        visits = AhoyDashboard.visit.where(started_at: range)

        expect(AhoyDashboard::Sql::ExcludedTraffic.only(visits, floor: range.begin).pluck(:visitor_token)).to eq(%w[googlebot])
      end
    end
  end
end
