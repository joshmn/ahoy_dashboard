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

    trait :organic_search do
      referrer { "https://www.google.com/" }
      referring_domain { "google.com" }
    end

    trait :paid_search do
      referrer { "https://www.google.com/" }
      referring_domain { "google.com" }
      utm_source { "google" }
      utm_medium { "cpc" }
      utm_campaign { "self-surrender" }
      utm_term { "federal prison consultant" }
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
    end
  end
end
