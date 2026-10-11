namespace :ahoy_dashboard do
  desc "report what the assistant is configured with"
  task assistant: :environment do
    AhoyDashboard::Assistant::StatusReport.lines.each { |line| puts line }
  end
end
