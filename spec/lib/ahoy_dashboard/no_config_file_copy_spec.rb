require "rails_helper"

RSpec.describe "Dashboard copy about settings" do
  root = AhoyDashboard::Engine.root
  moved = /settings file|config\.(host|canonical_host|time_zone|internal_ips|user_agent|favicons|serp|keywords|backlinks|places|assistant|ai_visibility|search_console|enable_all)\b|config\.(alerts|reports)\[:(enabled|digest|recipients|from|send_empty)\]/
  files = (root.glob("app/**/*.{rb,erb}") + root.glob("lib/**/*.{rb,rake}"))
    .reject { |file| file.to_s.include?("lib/generators/") || file.basename.to_s == "configuration.rb" }

  it "never sends anybody to the settings file for something that is set on a screen" do
    offenders = files.flat_map do |file|
      file.readlines.each_with_index.map { |line, index| "#{file.relative_path_from(root)}:#{index + 1}" if line.match?(moved) }.compact
    end

    expect(offenders).to be_empty
  end
end
