# frozen_string_literal: true

require "rails_helper"
require "open3"

RSpec.describe "Embedded scheduler boot" do
  def boot(embedded:)
    script = <<~RUBY
      require #{AhoyDashboard::Engine.root.join("spec/dummy/config/application").to_s.inspect}
      AhoyDashboard.config.embedded_scheduler = #{embedded.inspect}
      require #{AhoyDashboard::Engine.root.join("spec/dummy/config/environment").to_s.inspect}
      puts JSON.generate([
        Rails.application.middleware.map(&:klass).include?(AhoyDashboard::Scheduler::Middleware),
        AhoyDashboard.scheduler.running?
      ])
    RUBY
    output, error, status = Open3.capture3({ "RAILS_ENV" => "test" }, "bundle", "exec", "ruby", "-e", script)
    raise error unless status.success?

    JSON.parse(output)
  end

  it "leaves the request stack unchanged by default" do
    expect(boot(embedded: false)).to eq([ false, false ])
  end

  it "installs the middleware when opted in without starting a thread during boot" do
    expect(boot(embedded: true)).to eq([ true, false ])
  end
end
