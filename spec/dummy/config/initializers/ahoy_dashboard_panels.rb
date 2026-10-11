# frozen_string_literal: true

Rails.application.config.to_prepare do
  AhoyDashboard::Dimension.register(
    key: "ip",
    label: "IP address",
    group: "Location",
    scope: :visit,
    sql: Arel.sql("ahoy_visits.ip")
  )

  AhoyDashboard::Dimension.register(
    key: "asn",
    label: "Network (ASN)",
    group: "Location",
    scope: :visit,
    sql: Arel.sql("ahoy_visits.asn")
  )

  AhoyDashboard::Report.register(
    key: "ip_addresses",
    title: "IP addresses",
    tabs: [
      AhoyDashboard::Report::Tab.new(
        key: "ip",
        label: "IP",
        dimension_key: "ip",
        metrics: %w[visits],
        detail_metrics: %w[visits visitors pageviews visit_duration],
        label_column: "IP address"
      ),
      AhoyDashboard::Report::Tab.new(
        key: "asn",
        label: "Network",
        dimension_key: "asn",
        metrics: %w[visits],
        detail_metrics: %w[visits visitors pageviews visit_duration],
        label_column: "Network"
      )
    ]
  )
end
