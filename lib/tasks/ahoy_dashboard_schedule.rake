namespace :ahoy_dashboard do
  desc "report what the tick would start, and when each thing last ran"
  task schedule: :environment do
    now = Time.current

    puts "schedule"
    AhoyDashboard::Schedule::ALL.each do |entry|
      record = AhoyDashboard::JobRun.find_by(key: entry.key)
      state = entry.on? ? "on" : "off"
      last = record&.last_run_at&.in_time_zone(AhoyDashboard.time_zone)
      due = entry.on? && entry.due?(record&.last_run_at, now: now)

      puts "  #{entry.key}"
      puts "    #{entry.name}, #{entry.cadence}, #{state}"
      puts "    last started: #{last ? last.strftime("%Y-%m-%d %H:%M %Z") : "never"}"
      puts "    last result: #{record&.status || "unknown"}#{record&.last_error.present? ? ", #{record.last_error}" : ""}"
      puts "    due now: #{due ? "yes" : "no"}"
    end

    puts "next"
    off = AhoyDashboard::Schedule::ALL.reject(&:on?).map(&:key)
    if off.any?
      puts "  switched off: #{off.join(", ")}"
    else
      puts "  everything is on"
    end
    puts "  schedule AhoyDashboard::TickJob and this list runs itself"
  end
end
