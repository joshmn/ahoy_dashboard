FactoryBot.define do
  factory :dash_ai_assistant, class: "AhoyDashboard::AiVisibility::Assistant" do
    name { "openai" }

    trait :keyed do
      credentials { { api_key: "stored-key" } }
    end
  end

  factory :dash_ai_prompt, class: "AhoyDashboard::AiVisibility::Prompt" do
    sequence(:text) { |n| "what is the best federal prison consultant #{n}" }
    sequence(:position)
  end

  factory :dash_ai_run, class: "AhoyDashboard::AiVisibility::Run" do
    status { "queued" }
    trigger { "schedule" }
    requests { 1 }
    started_at { Time.current }
  end

  factory :dash_ai_answer, class: "AhoyDashboard::AiVisibility::Answer" do
    association :run, factory: :dash_ai_run
    association :prompt, factory: :dash_ai_prompt
    assistant { "openai" }
    model { "gpt-4.1" }
    status { "success" }
    text { "Some answer." }
    asked_at { Time.current }

    trait :mentioned do
      mentioned { true }
    end

    trait :cited do
      mentioned { true }
      cited { true }
      position { 1 }
    end

    trait :failed do
      status { "failed" }
      text { nil }
      error { "openai returned 500" }
    end
  end

  factory :dash_ai_source, class: "AhoyDashboard::AiVisibility::Source" do
    association :answer, factory: :dash_ai_answer
    sequence(:slot)
    url { "https://rival.example/page" }
    title { "Rival" }
    domain { "rival.example" }
    ours { false }
  end
end
