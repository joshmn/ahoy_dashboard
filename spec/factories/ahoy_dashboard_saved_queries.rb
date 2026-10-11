FactoryBot.define do
  factory :dash_saved_query, class: "AhoyDashboard::SavedQuery" do
    sequence(:name) { |n| "Question #{n}" }
    params { { "period" => "30d", "metric" => "visitors", "dimension" => "page" } }
    pinned { false }
    sequence(:position)
  end
end
