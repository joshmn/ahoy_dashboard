FactoryBot.define do
  # A segment is invalid with no filters, so the factory ships one. Pass
  # filters: [{ "dimension" => ..., "operator" => ..., "value" => ... }] to say
  # which, in the same shape the column holds.
  factory :dash_segment, class: "AhoyDashboard::Segment" do
    sequence(:name) { |n| "Segment #{n}" }
    sequence(:position) { |n| n }
    filters { [ { "dimension" => "country", "operator" => "is", "value" => "US" } ] }

    # A segment naming a dimension nobody registered. Written past the validations
    # on purpose: this is the state a row falls into when a dimension is taken out
    # of the registry after the row was saved, which no save could produce.
    trait :unreadable do
      after(:create) do |segment|
        segment.update_column(:filters, [ { "dimension" => "gone", "operator" => "is", "value" => "US" } ])
        segment.reload
      end
    end
  end
end
