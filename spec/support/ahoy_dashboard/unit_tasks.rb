require "rake"

module DashboardTasks
  def run_dashboard_task(name, *args)
    Rails.application.load_tasks unless Rake::Task.task_defined?("ahoy_dashboard:statistics")
    task = Rake::Task[name]
    task.reenable
    output = StringIO.new
    original = $stdout
    $stdout = output
    begin
      task.invoke(*args)
    ensure
      $stdout = original
    end
    output.string
  end

  def run_install_generator(destination, *args)
    output = StringIO.new
    original = [ $stdout, $stderr ]
    $stdout = $stderr = output
    AhoyDashboard::Generators::InstallGenerator.start([ "--skip-routes", *args ], destination_root: destination)
    output.string
  ensure
    $stdout, $stderr = original
  end
end

RSpec.configure { |config| config.include DashboardTasks }
