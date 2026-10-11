# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  gem "pg", "~> 1.1"
  gem "devise"
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "webmock"
end

group :development do
  gem "rubocop-rails-omakase", require: false if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("2.7")
end
