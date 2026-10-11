FactoryBot.define do
  factory :ahoy_visit, class: "Ahoy::Visit" do
    sequence(:visit_token) { |n| "visit-#{n}-#{SecureRandom.hex(4)}" }
    sequence(:visitor_token) { |n| "visitor-#{n}-#{SecureRandom.hex(4)}" }
    started_at { Time.current }
    landing_page { "https://federalprisondude.com/going-to-federal-prison/faq" }
    browser { "Chrome" }
    os { "Mac OS X" }
    os_version { "14.5" }
    device_type { "desktop" }
    platform { "Mac" }
    user_agent { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36" }
    ip { "203.0.113.10" }
    country { "US" }
    region { "Illinois" }
    city { "Chicago" }

    trait :mobile do
      browser { "Mobile Safari" }
      os { "iOS" }
      os_version { "17.5" }
      device_type { "mobile" }
      platform { "iPhone" }
      user_agent { "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1" }
    end

    trait :organic_search do
      referrer { "https://www.google.com/" }
      referring_domain { "google.com" }
    end

    trait :organic_social do
      referrer { "https://www.reddit.com/r/prison/comments/abc123/" }
      referring_domain { "reddit.com" }
    end

    trait :paid_search do
      referrer { "https://www.google.com/" }
      referring_domain { "google.com" }
      utm_source { "google" }
      utm_medium { "cpc" }
      utm_campaign { "self-surrender" }
      utm_term { "federal prison consultant" }
    end

    trait :email do
      utm_source { "newsletter" }
      utm_medium { "email" }
      utm_campaign { "monthly-2026-08" }
    end

    trait :ai_assistant do
      referrer { "https://chatgpt.com/" }
      referring_domain { "chatgpt.com" }
    end

    trait :unknown_device do
      browser { nil }
      os { nil }
      os_version { nil }
      device_type { nil }
      platform { nil }
      country { nil }
      region { nil }
      city { nil }
    end
  end

  factory :ahoy_event, class: "Ahoy::Event" do
    association :visit, factory: :ahoy_visit
    name { "site_searched" }
    properties { { "query" => "halfway house rules" } }
    time { visit&.started_at || Time.current }

    factory :page_view_event do
      name { "page_view" }
      properties do
        {
          "controller" => "faq_pages",
          "action" => "show",
          "path" => "/going-to-federal-prison/faq/visiting",
          "format" => "html"
        }
      end

      trait :crawler do
        properties do
          {
            "controller" => "faq_pages",
            "action" => "show",
            "path" => "/going-to-federal-prison/faq/visiting.md",
            "format" => "md",
            "crawler" => "GPTBot"
          }
        end
      end

      trait :facility do
        properties do
          {
            "controller" => "facilities",
            "action" => "show",
            "path" => "/resources/federal-prisons/tho-fci-thomson",
            "format" => "html",
            "facility_id" => 1
          }
        end
      end
    end
  end
end
