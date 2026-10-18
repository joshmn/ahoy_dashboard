FactoryBot.define do
  factory :dash_place, class: "AhoyDashboard::Place" do
    sequence(:code) { |n| 900_000 + n }
    name { "United States" }
    label { name.to_s.split(",").first }
    country_code { "us" }
    kind { "country" }
    depth { name.to_s.split(",").size - 1 }
    children_count { 0 }
    synced_at { Time.current }
  end
end
