FactoryBot.define do
  factory :dash_assistant_provider, class: "AhoyDashboard::AssistantProvider" do
    name { "anthropic" }

    trait :active do
      active { true }
    end
  end

  factory :dash_serp_provider, class: "AhoyDashboard::SerpProvider" do
    name { "fake" }
    monthly_cap_units { 500 }

    trait :serpapi do
      name { "serpapi" }
      credentials { { api_key: "stored-key" } }
    end

    trait :active do
      active { true }
    end

    trait :spent do
      units_spent { 500 }
      units_reset_on { Time.current.in_time_zone(AhoyDashboard.time_zone).to_date.beginning_of_month }
    end
  end

  factory :dash_serp_spend_day, class: "AhoyDashboard::SerpSpendDay" do
    provider { "serpapi" }
    on { Time.current.in_time_zone(AhoyDashboard.time_zone).to_date }
    kind { :checks }
    units { 10 }
  end

  factory :dash_serp_site, class: "AhoyDashboard::SerpSite" do
    sequence(:name) { |n| "Site #{n}" }
    sequence(:domain) { |n| "site-#{n}.com" }

    trait :subdomains do
      match_subdomains { true }
    end
  end

  factory :dash_serp_keyword, class: "AhoyDashboard::SerpKeyword" do
    sequence(:query) { |n| "federal prison question #{n}" }
    locations { [ "us" ] }
    pages { 1 }
    frequency { :daily }
  end

  factory :dash_serp_keyword_target, class: "AhoyDashboard::SerpKeywordTarget" do
    association :keyword, factory: :dash_serp_keyword
    association :site, factory: :dash_serp_site
  end

  factory :dash_serp_run, class: "AhoyDashboard::SerpRun" do
    association :keyword, factory: :dash_serp_keyword
    provider { "fake" }
    query { keyword.query }
    location { "us" }
    requested_pages { 1 }
    status { :success }
    checked_at { Time.current }
  end

  factory :dash_serp_run_page, class: "AhoyDashboard::SerpRunPage" do
    association :run, factory: :dash_serp_run
    page_number { 1 }
    start { 0 }
    depth { 10 }
    status { :success }
    response do
      {
        "search_id" => "fake-1",
        "results" => [
          { "rank" => 1, "url" => "https://bop.gov/a", "heading" => "One" },
          { "rank" => 2, "url" => "https://example.com/b", "heading" => "Two" }
        ],
        "overview" => {
          "body" => "An overview.",
          "cited" => [ { "slot" => 1, "url" => "https://example.com/b", "name" => "example.com" } ]
        }
      }
    end
  end

  factory :dash_serp_ai_citation, class: "AhoyDashboard::SerpAiCitation" do
    association :run, factory: :dash_serp_run
    slot { 1 }
    sequence(:link) { |n| "https://cited-#{n}.com/a" }
    domain { AhoyDashboard::Serp::Domain.host(link) }
    checked_at { run.checked_at }
  end

  factory :dash_serp_result, class: "AhoyDashboard::SerpResult" do
    association :run, factory: :dash_serp_run
    position { 1 }
    page { 1 }
    sequence(:link) { |n| "https://site-#{n}.com/a" }
    domain { AhoyDashboard::Serp::Domain.host(link) }
    checked_at { run.checked_at }
  end

  factory :dash_serp_check, class: "AhoyDashboard::SerpCheck" do
    association :run, factory: :dash_serp_run
    keyword { run.keyword }
    association :site, factory: :dash_serp_site
    target do
      AhoyDashboard::SerpKeywordTarget.find_or_create_by!(keyword: keyword, site: site)
    end
    location { run.location }
    checked_at { run.checked_at }
    position { 3 }
    status { :success }
  end
end
