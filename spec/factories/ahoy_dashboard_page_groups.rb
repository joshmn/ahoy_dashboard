FactoryBot.define do
  factory :dash_page_group, class: "AhoyDashboard::PageGroup" do
    sequence(:name) { |n| "Group #{n}" }
    patterns { [ "/blog/*" ] }
    sequence(:position)
  end
end
