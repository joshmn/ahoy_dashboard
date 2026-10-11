require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::Sql do
  describe "ENTRY_PATH" do
    it "pulls the bare path out of a landing page url" do
      create(:ahoy_visit, visit_token: "a", landing_page: "https://federalprisondude.com/going-in/faq?utm_source=x")
      create(:ahoy_visit, visit_token: "b", landing_page: "http://federalprisondude.com/")
      create(:ahoy_visit, visit_token: "c", landing_page: "https://federalprisondude.com")
      create(:ahoy_visit, visit_token: "d", landing_page: nil)

      expect(Ahoy::Visit.order(:visit_token).pluck(described_class::ENTRY_PATH))
        .to eq([ "/going-in/faq", "/", nil, nil ])
    end

    it "preserves relative, malformed, non-http and case-sensitive URL handling" do
      examples = [
        [ "", nil ], [ "http://", "http://" ], [ "http:///path", "http:///path" ],
        [ "http://host?x=/path?drop=yes", "/path" ], [ "https://host#fragment/path", "/path" ],
        [ "HTTP://host/path?x=1", "HTTP://host/path" ], [ "ftp://host/path?x=1", "ftp://host/path" ],
        [ "relative?x=1", "relative" ], [ "/path#fragment?x=1", "/path#fragment" ],
        [ "https://føø.example/읽기", "/읽기" ], [ "https://host//", "//" ]
      ]
      connection = ActiveRecord::Base.connection
      values = examples.each_with_index.map { |(value, _expected), index| "(#{index}, #{connection.quote(value)})" }
      paths = connection.select_values(<<~SQL)
        SELECT #{described_class::ENTRY_PATH}
        FROM (VALUES #{values.join(', ')}) AS ahoy_visits(id, landing_page) ORDER BY id
      SQL

      expect(paths).to eq(examples.map(&:last))
    end
  end

  describe "EVENT_PATH" do
    it "reads the path property off an event" do
      visit = create(:ahoy_visit)
      create(:ahoy_event, visit: visit, name: AhoyDashboard::PAGE_VIEW, time: Time.current,
                          properties: { "path" => "/resources" })

      expect(Ahoy::Event.pluck(described_class::EVENT_PATH)).to eq([ "/resources" ])
    end
  end

  describe "ENTRY_HOST" do
    it "preserves host, port and missing-host handling across recorded URL formats" do
      examples = [
        [ nil, nil ], [ "", nil ], [ "http://", nil ], [ "http:///path", nil ],
        [ "HTTPS://WWW.Example.COM:5000/path?x=1#fragment", "www.example.com" ],
        [ "http://host?x=/path", "host" ], [ "https://host#fragment/path", "host" ],
        [ "ftp://Uploads.Example.com/file", "uploads.example.com" ], [ "git+ssh://host/path", nil ],
        [ "relative/path", nil ], [ "//host/path", nil ], [ "https://FØØ.example/읽기", "føø.example" ]
      ]
      connection = ActiveRecord::Base.connection
      values = examples.each_with_index.map { |(value, _expected), index| "(#{index}, #{connection.quote(value)})" }
      hosts = connection.select_values(<<~SQL)
        SELECT #{described_class::ENTRY_HOST}
        FROM (VALUES #{values.join(', ')}) AS ahoy_visits(id, landing_page) ORDER BY id
      SQL

      expect(hosts).to eq(examples.map(&:last))
    end
  end

  describe "REFERRER" do
    it "folds the scheme, a leading www and a trailing slash into one row" do
      create(:ahoy_visit, visit_token: "a", referrer: "https://federalprisondude.com")
      create(:ahoy_visit, visit_token: "b", referrer: "https://federalprisondude.com/")
      create(:ahoy_visit, visit_token: "c", referrer: "http://www.federalprisondude.com//")
      create(:ahoy_visit, visit_token: "d", referrer: "HTTPS://WWW.federalprisondude.com/")

      expect(Ahoy::Visit.order(:visit_token).pluck(described_class::REFERRER).uniq)
        .to eq([ "federalprisondude.com" ])
    end

    it "keeps the path, its case and its query string" do
      create(:ahoy_visit, visit_token: "a", referrer: "https://reddit.com/r/Prison/comments/abc/")
      create(:ahoy_visit, visit_token: "b", referrer: "https://www.google.com/search?q=Federal+Prison")

      expect(Ahoy::Visit.order(:visit_token).pluck(described_class::REFERRER))
        .to eq([ "reddit.com/r/Prison/comments/abc", "google.com/search?q=Federal+Prison" ])
    end

    it "leaves a scheme that is not http alone so it keeps its identity" do
      create(:ahoy_visit, referrer: "android-app://com.reddit.frontpage/")

      expect(Ahoy::Visit.pluck(described_class::REFERRER)).to eq([ "android-app://com.reddit.frontpage" ])
    end

    it "reads a missing referrer as nothing rather than as an empty row" do
      create(:ahoy_visit, visit_token: "a", referrer: nil)
      create(:ahoy_visit, visit_token: "b", referrer: "")
      create(:ahoy_visit, visit_token: "c", referrer: "https://")

      expect(Ahoy::Visit.order(:visit_token).pluck(described_class::REFERRER)).to eq([ nil, nil, nil ])
    end
  end

  describe "SOURCE" do
    it "prefers a utm source, then the referring domain, then direct" do
      create(:ahoy_visit, visit_token: "a", utm_source: "newsletter", referring_domain: "google.com")
      create(:ahoy_visit, visit_token: "b", utm_source: "", referring_domain: "google.com")
      create(:ahoy_visit, visit_token: "c", utm_source: nil, referring_domain: "")
      create(:ahoy_visit, visit_token: "d", utm_source: nil, referring_domain: nil)

      expect(Ahoy::Visit.order(:visit_token).pluck(described_class::SOURCE))
        .to eq([ "newsletter", "google.com", "Direct / None", "Direct / None" ])
    end

    it "calls this site's own hosts internal rather than a source" do
      create(:ahoy_visit, visit_token: "a", utm_source: nil, referring_domain: "example.com")
      create(:ahoy_visit, visit_token: "b", utm_source: nil, referring_domain: "www.example.com")
      create(:ahoy_visit, visit_token: "c", utm_source: nil, referring_domain: "portal.example.com")
      create(:ahoy_visit, visit_token: "d", utm_source: nil, referring_domain: "notexample.com")

      expect(Ahoy::Visit.order(:visit_token).pluck(described_class::SOURCE))
        .to eq([ "Internal", "Internal", "Internal", "notexample.com" ])
    end

    it "still reads a utm source off an internal referrer" do
      create(:ahoy_visit, utm_source: "newsletter", referring_domain: "portal.example.com")

      expect(Ahoy::Visit.pluck(described_class::SOURCE)).to eq([ "newsletter" ])
    end
  end

  describe "CHANNEL" do
    channel_cases = [
      { referring_domain: nil, utm_medium: "cpc", channel: "Paid Search" },
      { referring_domain: nil, utm_medium: "ppc", channel: "Paid Search" },
      { referring_domain: nil, utm_medium: "paid", channel: "Paid Search" },
      { referring_domain: nil, utm_medium: "paidsearch", channel: "Paid Search" },
      { referring_domain: "google.com", utm_medium: "cpc", channel: "Paid Search" },
      { referring_domain: nil, utm_medium: "email", channel: "Email" },
      { referring_domain: nil, utm_medium: "e-mail", channel: "Email" },
      { referring_domain: nil, utm_medium: "newsletter", channel: "Email" },
      { referring_domain: nil, utm_medium: "social", channel: "Organic Social" },
      { referring_domain: nil, utm_medium: "social-network", channel: "Organic Social" },
      { referring_domain: nil, utm_medium: "sm", channel: "Organic Social" },
      { referring_domain: nil, utm_medium: "paid-social", channel: "Organic Social" },
      { referring_domain: "google.com", utm_medium: nil, channel: "Organic Search" },
      { referring_domain: "google.co.uk", utm_medium: nil, channel: "Organic Search" },
      { referring_domain: "bing.com", utm_medium: nil, channel: "Organic Search" },
      { referring_domain: "duckduckgo.com", utm_medium: nil, channel: "Organic Search" },
      { referring_domain: "search.yahoo.com", utm_medium: nil, channel: "Organic Search" },
      { referring_domain: "ecosia.org", utm_medium: nil, channel: "Organic Search" },
      { referring_domain: "brave.com", utm_medium: nil, channel: "Organic Search" },
      { referring_domain: "startpage.com", utm_medium: nil, channel: "Organic Search" },
      { referring_domain: "baidu.com", utm_medium: nil, channel: "Organic Search" },
      { referring_domain: "yandex.ru", utm_medium: nil, channel: "Organic Search" },
      { referring_domain: "facebook.com", utm_medium: nil, channel: "Organic Social" },
      { referring_domain: "m.facebook.com", utm_medium: nil, channel: "Organic Social" },
      { referring_domain: "l.facebook.com", utm_medium: nil, channel: "Organic Social" },
      { referring_domain: "instagram.com", utm_medium: nil, channel: "Organic Social" },
      { referring_domain: "t.co", utm_medium: nil, channel: "Organic Social" },
      { referring_domain: "x.com", utm_medium: nil, channel: "Organic Social" },
      { referring_domain: "twitter.com", utm_medium: nil, channel: "Organic Social" },
      { referring_domain: "reddit.com", utm_medium: nil, channel: "Organic Social" },
      { referring_domain: "out.reddit.com", utm_medium: nil, channel: "Organic Social" },
      { referring_domain: "linkedin.com", utm_medium: nil, channel: "Organic Social" },
      { referring_domain: "lnkd.in", utm_medium: nil, channel: "Organic Social" },
      { referring_domain: "youtube.com", utm_medium: nil, channel: "Organic Social" },
      { referring_domain: "pinterest.com", utm_medium: nil, channel: "Organic Social" },
      { referring_domain: "tiktok.com", utm_medium: nil, channel: "Organic Social" },
      { referring_domain: "news.ycombinator.com", utm_medium: nil, channel: "Organic Social" },
      { referring_domain: "chatgpt.com", utm_medium: nil, channel: "AI Assistants" },
      { referring_domain: "chat.openai.com", utm_medium: nil, channel: "AI Assistants" },
      { referring_domain: "claude.ai", utm_medium: nil, channel: "AI Assistants" },
      { referring_domain: "perplexity.ai", utm_medium: nil, channel: "AI Assistants" },
      { referring_domain: "www.perplexity.ai", utm_medium: nil, channel: "AI Assistants" },
      { referring_domain: "gemini.google.com", utm_medium: nil, channel: "AI Assistants" },
      { referring_domain: "copilot.microsoft.com", utm_medium: nil, channel: "AI Assistants" },
      { referring_domain: "prisonprofessors.com", utm_medium: nil, channel: "Referral" },
      { referring_domain: "bop.gov", utm_medium: "referral", channel: "Referral" },
      { referring_domain: "example.com", utm_medium: nil, channel: "Internal" },
      { referring_domain: "www.example.com", utm_medium: nil, channel: "Internal" },
      { referring_domain: "portal.example.com", utm_medium: nil, channel: "Internal" },
      { referring_domain: "surveys.example.com", utm_medium: nil, channel: "Internal" },
      { referring_domain: "example.com", utm_medium: "cpc", channel: "Paid Search" },
      { referring_domain: "notexample.com", utm_medium: nil, channel: "Referral" },
      { referring_domain: nil, utm_medium: nil, channel: "Direct / None" },
      { referring_domain: "", utm_medium: "", channel: "Direct / None" }
    ].freeze

    channel_cases.each_with_index do |row, index|
      it "puts #{row[:referring_domain].inspect} on medium #{row[:utm_medium].inspect} in #{row[:channel]}" do
        domain = row[:referring_domain]
        create(:ahoy_visit, visit_token: format("channel-%02d", index), referring_domain: domain,
                            referrer: domain.presence && "https://#{domain}/somewhere",
                            utm_medium: row[:utm_medium], utm_source: nil)

        expect(Ahoy::Visit.pluck(described_class::CHANNEL)).to eq([ row[:channel] ])
      end
    end

    it "reads www, case and blanks off the stored domain and medium" do
      cases = [
        [ "www.google.com", nil, "Organic Search" ], [ "google.co.uk", nil, "Organic Search" ],
        [ "WWW.Bing.com", nil, "Organic Search" ], [ "www.facebook.com", nil, "Organic Social" ],
        [ "mail.google.com", nil, "Email" ], [ "www.chatgpt.com", nil, "AI Assistants" ],
        [ "www.example.com", nil, "Internal" ], [ "portal.example.com", nil, "Internal" ],
        [ "wwwexample.org", nil, "Referral" ], [ "www.", nil, "Direct / None" ], [ nil, nil, "Direct / None" ],
        [ "", "cpc", "Paid Search" ], [ "news.example.org", "Email", "Email" ], [ nil, "CPC", "Paid Search" ]
      ]
      cases.each_with_index do |(domain, medium, _channel), index|
        create(:ahoy_visit, visit_token: format("%02d", index), referring_domain: domain, utm_medium: medium)
      end

      expect(Ahoy::Visit.order(:visit_token).pluck(described_class::CHANNEL)).to eq(cases.map(&:last))
    end
  end

  describe "CHANNEL_PREDICATES" do
    it "matches the full channel classifier across domains, medium precedence, case and missing values" do
      domains = [ nil, "", "www.", "google", "google.com", "google.co.uk", "yandex.ru", "notgoogle.com",
                  "google.com.evil.test", "example.com", "unknown.test", " google.com " ] +
        described_class::SEARCH_DOMAINS + described_class::MAIL_DOMAINS +
        described_class::SOCIAL_DOMAINS + described_class::LLM_DOMAINS
      domains += domains.compact.map { |domain| "WWW.#{domain.upcase}" }
      mediums = [ nil, "", "organic", " Email ", "unknown" ] + described_class::PAID_MEDIUMS +
        described_class::EMAIL_MEDIUMS + described_class::SOCIAL_MEDIUMS
      mediums += mediums.compact.map(&:upcase)
      connection = ActiveRecord::Base.connection
      values = domains.uniq.product(mediums.uniq).map do |domain, medium|
        "(#{connection.quote(domain)}, #{connection.quote(medium)})"
      end
      described_class::CHANNEL_PREDICATES.each do |channel, predicate|
        results = connection.select_rows(<<~SQL)
          select (#{described_class::CHANNEL}) = #{connection.quote(channel)},
                 (#{predicate})
          from (values #{values.join(', ')}) as ahoy_visits(referring_domain, utm_medium)
        SQL

        expect(results.map(&:last)).to eq(results.map(&:first)), "classification differs for #{channel}"
        expect(results.map(&:last).uniq).to contain_exactly(true, false)
      end
    end
  end

  it "reads the host when the query runs, so a new host counts without a restart" do
    create(:ahoy_visit, referring_domain: "elsewhere.test")
    expect(Ahoy::Visit.pick(described_class::SOURCE)).to eq("elsewhere.test")

    AhoyDashboard::Preferences.write(:site, host: "www.elsewhere.test")
    expect(Ahoy::Visit.pick(described_class::SOURCE)).to eq("Internal")

    AhoyDashboard::Preferences.write(:site, host: nil)
    expect(Ahoy::Visit.pick(described_class::CHANNEL)).to eq("Referral")
  end

  describe ".internal_domain?" do
    it "matches the main host and anything under it" do
      expect(described_class.internal_domain?("example.com")).to be(true)
      expect(described_class.internal_domain?("vouch.example.com")).to be(true)
      expect(described_class.internal_domain?("notexample.com")).to be(false)
      expect(described_class.internal_domain?("example.com.evil.test")).to be(false)
      expect(described_class.internal_domain?(nil)).to be(false)
    end
  end
end
