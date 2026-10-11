FactoryBot.define do
  factory :dash_annotation, class: "AhoyDashboard::Annotation" do
    label { "v2.5.0 deploy" }
    happened_at { Time.current }
    kind { "deploy" }
  end
end
