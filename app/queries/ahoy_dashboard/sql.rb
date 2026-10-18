module AhoyDashboard
  module Sql
    PAID_SEARCH = "Paid Search".freeze
    EMAIL = "Email".freeze
    ORGANIC_SOCIAL = "Organic Social".freeze
    ORGANIC_SEARCH = "Organic Search".freeze
    AI_ASSISTANTS = "AI Assistants".freeze
    REFERRAL = "Referral".freeze
    INTERNAL = "Internal".freeze
    DIRECT = "Direct / None".freeze

    PAID_MEDIUMS = %w[cpc ppc paid paidsearch].freeze
    EMAIL_MEDIUMS = %w[email e-mail newsletter].freeze
    SOCIAL_MEDIUMS = %w[social social-network sm paid-social].freeze

    MAIL_DOMAINS = %w[
      mail.google.com mail.yahoo.com mail.aol.com mail.proton.me mail.zoho.com
      outlook.live.com outlook.office.com outlook.office365.com
    ].freeze

    SEARCH_DOMAINS = %w[
      bing.com duckduckgo.com search.yahoo.com ecosia.org brave.com search.brave.com
      startpage.com baidu.com
    ].freeze

    SEARCH_DOMAIN_PATTERNS = %w[google.% yandex.%].freeze

    SOCIAL_DOMAINS = %w[
      facebook.com m.facebook.com l.facebook.com instagram.com t.co x.com twitter.com
      reddit.com out.reddit.com linkedin.com lnkd.in youtube.com pinterest.com tiktok.com
      news.ycombinator.com
    ].freeze

    LLM_DOMAINS = %w[
      chatgpt.com chat.openai.com claude.ai perplexity.ai gemini.google.com
      copilot.microsoft.com
    ].freeze

    def self.literal(value)
      "'#{value.to_s.gsub("'", "''")}'"
    end

    def self.in_list(expression, values)
      "#{expression} in (#{values.map { |value| literal(value) }.join(", ")})"
    end

    def self.like_any(expression, patterns)
      "(#{patterns.map { |pattern| "#{expression} ilike #{literal(pattern)}" }.join(" or ")})"
    end

    PAGE_VIEW_EVENT = "ahoy_events.name = #{literal(AhoyDashboard::PAGE_VIEW)}".freeze
    PAGEVIEW_COUNT = Arel.sql("count(*) filter (where #{PAGE_VIEW_EVENT})").freeze

    VISITOR_TOKEN = Arel.sql(%(ahoy_visits.visitor_token collate "C")).freeze
    VISITORS = Arel.sql("count(distinct #{VISITOR_TOKEN})").freeze
    SESSION_VISITORS = Arel.sql(%(count(distinct tm_visits.visitor_token collate "C"))).freeze
    SESSION_PAGEVIEWS = Arel.sql("coalesce(sum(tm_visits.pageviews), 0)").freeze
    SESSION_DURATION = Arel.sql("coalesce(avg(tm_visits.duration), 0)").freeze

    HOST = "(select nullif(regexp_replace(lower(value #>> '{}'), '^www[.]', ''), '') " \
           "from ahoy_dashboard_settings where key = 'site.host')".freeze

    def self.internal_domain(expression)
      "coalesce(#{expression} = #{HOST} or #{expression} like '%.' || #{HOST}, false)"
    end

    DOMAIN = "(case when lower(ahoy_visits.referring_domain) like 'www.%' " \
             "then substr(lower(ahoy_visits.referring_domain), 5) " \
             "else lower(coalesce(ahoy_visits.referring_domain, '')) end)".freeze

    MEDIUM = "lower(coalesce(ahoy_visits.utm_medium, ''))".freeze

    ENTRY_PATH = Arel.sql(<<~SQL.squish).freeze
      nullif(split_part((case
        when left(ahoy_visits.landing_page, 7) = 'http://' and split_part(ahoy_visits.landing_page, '/', 3) <> ''
          then substr(ahoy_visits.landing_page, 8 + length(split_part(ahoy_visits.landing_page, '/', 3)))
        when left(ahoy_visits.landing_page, 8) = 'https://' and split_part(ahoy_visits.landing_page, '/', 3) <> ''
          then substr(ahoy_visits.landing_page, 9 + length(split_part(ahoy_visits.landing_page, '/', 3)))
        else ahoy_visits.landing_page
      end), '?', 1), '')
    SQL

    ENTRY_URL = Arel.sql("nullif(ahoy_visits.landing_page, '')").freeze

    ENTRY_HOST = Arel.sql(<<~SQL.squish).freeze
      nullif(split_part((case
        when left(ahoy_visits.landing_page, 7) ilike 'http://' or left(ahoy_visits.landing_page, 8) ilike 'https://'
          then lower(split_part(split_part(split_part(ahoy_visits.landing_page, '/', 3), '?', 1), '#', 1))
        else substring(lower(ahoy_visits.landing_page) from '^[a-z]+://([^/?#]+)')
      end), ':', 1), '')
    SQL

    EVENT_PATH = Arel.sql("ahoy_events.properties ->> 'path'").freeze
    PAGE_VIEW_STEP = Arel.sql(%((case when #{PAGE_VIEW_EVENT} then nullif(#{EVENT_PATH}, '') end) collate "C")).freeze

    REFERRER = Arel.sql(<<~SQL.squish).freeze
      nullif(
        regexp_replace(
          regexp_replace(coalesce(ahoy_visits.referrer, ''), '^https?://(www[.])?', '', 'i'),
          '/+$', ''
        ),
      '')
    SQL

    SESSION_BOUNCED = "tm_visits.pageviews = 1".freeze
    SESSION_BROWSED = "tm_visits.pageviews > 0".freeze
    COUNT_BOUNCED = "count(*) filter (where #{SESSION_BOUNCED})".freeze
    COUNT_BROWSED = "count(*) filter (where #{SESSION_BROWSED})".freeze

    PAGE_VIEWS_OF_VISIT = "select 1 from ahoy_events dash_views where dash_views.visit_id = ahoy_visits.id " \
                          "and dash_views.name = '#{AhoyDashboard::PAGE_VIEW}'".freeze
    VIEWED_A_PAGE = "exists (#{PAGE_VIEWS_OF_VISIT})".freeze
    NEVER_VIEWED_A_PAGE = "not #{VIEWED_A_PAGE}".freeze
    BROWSED = Arel.sql("case when #{VIEWED_A_PAGE} then 'Yes' else 'No' end").freeze

    INTERNAL_DOMAIN = internal_domain(DOMAIN).freeze

    SOURCE = Arel.sql(<<~SQL.squish).freeze
      case
      when nullif(ahoy_visits.utm_source, '') is not null then ahoy_visits.utm_source
      when #{INTERNAL_DOMAIN} then #{literal(INTERNAL)}
      else coalesce(nullif(ahoy_visits.referring_domain, ''), #{literal(DIRECT)})
      end
    SQL

    CHANNEL = Arel.sql(<<~SQL.squish).freeze
      case
      when coalesce(ahoy_visits.referring_domain, '') = '' and coalesce(ahoy_visits.utm_medium, '') = '' then #{literal(DIRECT)}
      when #{in_list(MEDIUM, PAID_MEDIUMS)} then #{literal(PAID_SEARCH)}
      when #{in_list(MEDIUM, EMAIL_MEDIUMS)} or #{in_list(DOMAIN, MAIL_DOMAINS)} then #{literal(EMAIL)}
      when #{in_list(MEDIUM, SOCIAL_MEDIUMS)} then #{literal(ORGANIC_SOCIAL)}
      when #{in_list(DOMAIN, SEARCH_DOMAINS)} or #{like_any(DOMAIN, SEARCH_DOMAIN_PATTERNS)} then #{literal(ORGANIC_SEARCH)}
      when #{in_list(DOMAIN, SOCIAL_DOMAINS)} then #{literal(ORGANIC_SOCIAL)}
      when #{in_list(DOMAIN, LLM_DOMAINS)} then #{literal(AI_ASSISTANTS)}
      when #{INTERNAL_DOMAIN} then #{literal(INTERNAL)}
      when #{DOMAIN} <> '' then #{literal(REFERRAL)}
      else #{literal(DIRECT)}
      end
    SQL

    ORGANIC_SEARCH_PREDICATE = Arel.sql(<<~SQL.squish).freeze
      coalesce(ahoy_visits.referring_domain, '') <> ''
      and not #{in_list(MEDIUM, PAID_MEDIUMS + EMAIL_MEDIUMS + SOCIAL_MEDIUMS)}
      and not #{in_list(DOMAIN, MAIL_DOMAINS)}
      and (#{in_list(DOMAIN, SEARCH_DOMAINS)} or #{like_any(DOMAIN, SEARCH_DOMAIN_PATTERNS)})
    SQL

    AI_ASSISTANTS_PREDICATE = Arel.sql(<<~SQL.squish).freeze
      coalesce(ahoy_visits.referring_domain, '') <> ''
      and #{in_list(DOMAIN, LLM_DOMAINS)}
      and not #{in_list(MEDIUM, PAID_MEDIUMS + EMAIL_MEDIUMS + SOCIAL_MEDIUMS)}
      and not #{in_list(DOMAIN, MAIL_DOMAINS + SOCIAL_DOMAINS + SEARCH_DOMAINS)}
      and not #{like_any(DOMAIN, SEARCH_DOMAIN_PATTERNS)}
    SQL

    CHANNEL_PREDICATES = {
      ORGANIC_SEARCH => ORGANIC_SEARCH_PREDICATE,
      AI_ASSISTANTS => AI_ASSISTANTS_PREDICATE
    }.freeze

    class << self
      def dimension_inclusion(dimension, floor: nil)
        return if dimension.exclude.nil?
        return viewed_a_page(floor: floor) if dimension.exclude == NEVER_VIEWED_A_PAGE

        "not (#{dimension.exclude})"
      end

      def viewed_a_page(floor: nil)
        return VIEWED_A_PAGE if floor.nil?

        "exists (#{PAGE_VIEWS_OF_VISIT} and dash_views.time >= #{timestamp(floor)})"
      end

      def timestamp(value)
        "#{AhoyDashboard.event.connection.quote(value)}::timestamp"
      end

      def value_in(relation, expression, values)
        present = values.compact
        return relation.where("#{expression} is null") if present.empty?
        return relation.where("#{expression} in (:values) or #{expression} is null", values: present) if present.size < values.size

        relation.where("#{expression} in (:values)", values: present)
      end
    end

    private_class_method :in_list, :like_any
  end
end
