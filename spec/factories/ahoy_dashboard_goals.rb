FactoryBot.define do
  factory :dash_goal, class: "AhoyDashboard::Goal" do
    kind { :custom_event }
    sequence(:event_name) { |n| "thing_happened_#{n}" }
    sequence(:position) { |n| n }

    trait :pageview do
      kind { :pageview }
      event_name { nil }
      sequence(:path_pattern) { |n| "/page-#{n}" }
    end

    trait :narrowed do
      property_key { "facility_id" }
      property_value { "12" }
    end

    trait :revenue do
      currency { "USD" }
    end

    trait :named do
      display_name { "The one that matters" }
    end
  end
end
