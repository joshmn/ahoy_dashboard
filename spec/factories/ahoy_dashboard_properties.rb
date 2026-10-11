FactoryBot.define do
  factory :dash_property, class: "AhoyDashboard::Property" do
    sequence(:key) { |n| "custom_key_#{n}" }
    sequence(:position) { |n| n }
    label { nil }

    trait :labelled do
      label { "Facility" }
    end

    trait :disabled do
      enabled { false }
    end
  end
end
