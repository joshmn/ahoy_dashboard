FactoryBot.define do
  factory :dash_chat, class: "AhoyDashboard::Chat"

  factory :dash_chat_message, class: "AhoyDashboard::ChatMessage" do
    association :chat, factory: :dash_chat
    role { :user }
    status { :complete }

    trait :assistant do
      role { :assistant }
    end

    trait :pending do
      status { :pending }
    end

    trait :failed do
      status { :failed }
    end
  end
end
