require "rails_helper"
require "generators/ahoy_dashboard/install/install_generator"

RSpec.describe AhoyDashboard::Generators::InstallGenerator do
  around do |example|
    Dir.mktmpdir do |dir|
      @destination = dir
      example.run
    end
  end

  def generate
    capture = StringIO.new
    original = $stdout
    $stdout = capture
    described_class.start([ "--skip-migrations", "--skip-routes" ], destination_root: @destination)
    capture.string
  ensure
    $stdout = original
  end

  it "writes the initializer and leaves explaining it to the file" do
    output = generate
    initializer = File.read(File.join(@destination, "config/initializers/ahoy_dashboard.rb"))

    expect(initializer).to include("config.authorize = ->(controller) { controller.current_user&.admin? }")
    expect(output).to include("create  config/initializers/ahoy_dashboard.rb")
    expect(output).not_to include("authorize")
  end

  it "writes an initializer that boots against the configuration as it is now" do
    generate
    config = AhoyDashboard::Configuration.new
    allow(AhoyDashboard).to receive(:configure).and_yield(config)

    expect { load File.join(@destination, "config/initializers/ahoy_dashboard.rb") }.not_to raise_error
    expect(config.authorize).to respond_to(:call)
  end
end
