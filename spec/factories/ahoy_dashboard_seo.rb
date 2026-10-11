FactoryBot.define do
  factory :dash_alert_rule, class: "AhoyDashboard::AlertRule" do
    key { "off_page_one" }
    name { "Fell off page one" }
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
end
