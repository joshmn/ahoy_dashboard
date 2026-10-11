# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :users, only: :sessions
  mount AhoyDashboard::Engine, at: "/telemetry"
end
