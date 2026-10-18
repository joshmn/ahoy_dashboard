FactoryBot.define do
  factory :dash_funnel, class: "AhoyDashboard::Funnel" do
    sequence(:name) { |n| "Funnel #{n}" }
    sequence(:position) { |n| n }

    transient do
      steps { AhoyDashboard::Funnel::MINIMUM_STEPS }
      goals { [] }
    end

    after(:build) do |funnel, evaluator|
      next if funnel.funnel_steps.any?

      chosen = evaluator.goals.presence || Array.new(evaluator.steps) { create(:dash_goal) }
      chosen.each_with_index do |goal, index|
        funnel.funnel_steps.build(goal: goal, position: index + 1)
      end
    end
  end

  factory :dash_funnel_step, class: "AhoyDashboard::FunnelStep" do
    association :funnel, factory: :dash_funnel
    association :goal, factory: :dash_goal
    sequence(:position) { |n| n }
  end
end
