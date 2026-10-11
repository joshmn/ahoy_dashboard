# frozen_string_literal: true

Devise.setup do |config|
  require "devise/orm/active_record"

  config.mailer_sender = "devise@example.com"
  config.secret_key = "dummy" * 13
  config.stretches = 1
  config.navigational_formats = [ "*/*", :html ]
  config.sign_out_via = :delete
end
