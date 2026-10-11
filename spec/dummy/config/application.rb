# frozen_string_literal: true

require File.expand_path("boot", __dir__)

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"

require "devise"
require "factory_bot_rails"
require "ahoy_dashboard"

module Dummy

  class Application < Rails::Application
    config.load_defaults(6.0)
    config.eager_load = false
    config.root = File.expand_path("..", __dir__)
    config.secret_key_base = "dummy"
    config.x.main_host = "example.com"
    config.factory_bot.definition_file_paths = [ File.expand_path("../../factories", __dir__) ]
  end
end
