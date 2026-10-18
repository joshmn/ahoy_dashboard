FactoryBot.define do
  factory :dash_segment, class: "AhoyDashboard::Segment" do
    sequence(:name) { |n| "Segment #{n}" }
    sequence(:position) { |n| n }
    filters { [ { "dimension" => "country", "operator" => "is", "value" => "US" } ] }

    trait :unreadable do
      after(:create) do |segment|
        segment.update_column(:filters, [ { "dimension" => "gone", "operator" => "is", "value" => "US" } ])
        segment.reload
      end
    end
  end
end
