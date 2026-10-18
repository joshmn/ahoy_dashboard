namespace :ahoy_dashboard do
  desc "report what the tick would start, and when each thing last ran"
  task schedule: :environment do
    rows = AhoyDashboard::Settings::JobRunPresenter.call.rows.select { |row| row.entry.scheduled? }

    rows.each do |row|
      started = row.started_at&.in_time_zone(AhoyDashboard.time_zone)&.strftime("%Y-%m-%d %H:%M %Z") || "never"
      status = row.record&.status || "unknown"
      result = row.error ? "#{status} (#{row.error})" : status

      puts "#{row.key} runs #{row.cadence.downcase} and is #{row.on? ? "on" : "off"}. " \
           "last started #{started}, last result #{result}, #{row.due? ? "due now" : "not due"}"
    end

    off = rows.reject(&:on?).map(&:key)
    puts(off.any? ? "switched off: #{off.join(", ")}" : "everything is on")
    puts "schedule AhoyDashboard::TickJob and this list runs itself"
  end
end
