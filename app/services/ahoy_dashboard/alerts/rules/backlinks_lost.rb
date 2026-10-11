module AhoyDashboard
  module Alerts
    module Rules
      class BacklinksLost < Rule
        defines key: "backlinks_lost", name: "Referring domains lost", group: :backlinks,
                watches: "Your backlink profile", severity: :medium, default_threshold: 5, unit: "domains",
                threshold_range: 1..Float::INFINITY,
                phrase: "the latest backlinks sync marked %{threshold} or more domains lost"

        def findings
          sample = readings.latest_backlink_sample
          return [] if sample.nil? || sample.lost.to_i < threshold

          [ finding(subject: subject, reading: sample.on.iso8601,
                    headline: "Lost #{counted(sample.lost, "referring domain")}",
                    detail: "The #{day(sample.on)} sync marked #{number(sample.lost)} lost. " \
                            "#{counted(sample.domains.to_i, "domain")} still #{sample.domains.to_i == 1 ? "links" : "link"} to you.",
                    sample_data: sample.provider == Serp::Adapters::FakeAdapter.adapter_name) ]
        end

        private

        def subject
          Backlinks.domain.presence || "Backlinks"
        end
      end
    end
  end
end
