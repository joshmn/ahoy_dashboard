FactoryBot.define do
  factory :dash_google_account, class: "AhoyDashboard::GoogleAccount" do
    email { "josh@example.com" }
    access_token { "access-token" }
    refresh_token { "refresh-token" }
    expires_at { 50.minutes.from_now }
    scope { AhoyDashboard::SearchConsole::SCOPE }
    connected_at { Time.current }

    trait :with_property do
      property_uri { "sc-domain:example.com" }
    end

    trait :expired do
      expires_at { 5.minutes.ago }
    end

    trait :unconnected do
      refresh_token { nil }
    end
  end

  factory :dash_search_console_row, class: "AhoyDashboard::SearchConsoleRow" do
    date { Date.current }
    sequence(:query) { |n| "federal prison question #{n}" }
    page { "https://example.com/going-in/faq" }
    clicks { 3 }
    impressions { 40 }
    ctr { 0.075 }
    position { 8.4 }
  end

  factory :dash_search_console_keyword, class: "AhoyDashboard::SearchConsoleKeyword" do
    date { Date.current }
    sequence(:query) { |n| "federal prison question #{n}" }
    clicks { 5 }
    impressions { 90 }
    ctr { 0.055 }
    position { 7.2 }
  end

  factory :dash_search_console_day, class: "AhoyDashboard::SearchConsoleDay" do
    date { Date.current }
    scanned_at { Time.current }
  end

  factory :dash_search_console_total, class: "AhoyDashboard::SearchConsoleTotal" do
    date { Date.current }
    clicks { 10 }
    impressions { 200 }
    ctr { 0.05 }
    position { 9.1 }
  end
end
