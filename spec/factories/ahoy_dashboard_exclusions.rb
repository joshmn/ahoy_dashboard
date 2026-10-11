FactoryBot.define do
  factory :dash_exclusion, class: "AhoyDashboard::Exclusion" do
    sequence(:name) { |n| "Exclusion #{n}" }
    enabled { true }
    filters { [ { "dimension" => "asn", "operator" => "contains", "value" => "EXAMPLE-DATACENTER" } ] }

    trait :off do
      enabled { false }
    end

    trait :unreadable do
      after(:create) do |exclusion|
        exclusion.update_column(:filters, [ { "dimension" => "gone", "operator" => "is", "value" => "US" } ])
        exclusion.reload
      end
    end
  end
end
