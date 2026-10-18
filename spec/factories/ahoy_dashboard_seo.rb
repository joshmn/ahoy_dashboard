FactoryBot.define do
  factory :dash_alert_rule, class: "AhoyDashboard::AlertRule" do
    key { "off_page_one" }
    name { AhoyDashboard::Alerts::Catalogue.find(key)&.name || "Fell off page one" }
    severity { :high }
    threshold { 10 }
    enabled { true }

    trait :off do
      enabled { false }
    end
  end

  factory :dash_alert_event, class: "AhoyDashboard::AlertEvent" do
    association :rule, factory: :dash_alert_rule
    fired_at { Time.current }
    severity { :high }
    headline { "Fell off page one: federal prison consultant" }
    detail { "Was 8, now 14 on google.com in the us" }
    sequence(:subject) { |n| "federal prison consultant #{n} (us)" }
  end

  factory :dash_backlink_domain, class: "AhoyDashboard::BacklinkDomain" do
    sequence(:domain) { |n| "linker-#{n}.example" }
    first_seen_on { Date.current - 1 }
    last_seen_on { Date.current }
    provider { "dataforseo" }
  end

  factory :dash_backlink_sample, class: "AhoyDashboard::BacklinkSample" do
    on { Date.current }
    provider { "dataforseo" }
  end

  factory :dash_backlink_anchor, class: "AhoyDashboard::BacklinkAnchor" do
    sequence(:text) { |n| "anchor #{n}" }
    seen_on { Date.current }
  end

  factory :dash_keyword_idea, class: "AhoyDashboard::KeywordIdea" do
    seed { "visiting" }
    sequence(:query) { |n| "visiting idea #{n}" }
    provider { "fake" }
    fetched_at { Time.current }
  end
end
