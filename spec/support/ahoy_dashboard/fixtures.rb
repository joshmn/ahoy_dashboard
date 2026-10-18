module AhoyDashboardFixtures
  PAGE_VIEW_PROPERTIES = {
    "controller" => "public/pages",
    "action" => "show",
    "path" => "/",
    "format" => "html"
  }.freeze

  def dash_time(year, month, day, hour = 0, minute = 0, second = 0)
    AhoyDashboard.time_zone.local(year, month, day, hour, minute, second)
  end

  def dash_day_range(year, month, day)
    start = dash_time(year, month, day)

    start..start.end_of_day
  end

  def dash_visit(started_at:, visitor: nil, **attributes)
    attributes[:visitor_token] = visitor if visitor

    create(:ahoy_visit, started_at: started_at, **attributes)
  end

  def dash_landing(path = "/", at:, visitor: nil, **visit_attributes)
    dash_visit(started_at: at, visitor: visitor, **visit_attributes).tap { |visit| dash_page_view(visit, path: path) }
  end

  def dash_page_view(visit, path: "/", at: nil, **properties)
    create(
      :ahoy_event,
      visit: visit,
      name: AhoyDashboard::PAGE_VIEW,
      time: at || visit.started_at,
      properties: PAGE_VIEW_PROPERTIES.merge("path" => path).merge(properties.transform_keys(&:to_s))
    )
  end

  def dash_goal(visit, name, properties = {}, at: nil, **attributes)
    properties = properties.merge(attributes)
    create(
      :ahoy_event,
      visit: visit,
      name: name,
      time: at || visit.started_at,
      properties: properties.transform_keys(&:to_s)
    )
  end

  def dash_engagement(visit, depth:, time: 0, path: "/a", at: nil, **properties)
    attributes = { path: path, scroll_depth: depth }
    attributes[:engagement_time] = time unless time.nil?
    dash_goal(visit, AhoyDashboard::ENGAGEMENT, at: at, **attributes.merge(properties))
  end

  def dash_entry(dimension: "country", operator: "is", value: "US", group: nil, block: nil)
    { "dimension" => dimension, "operator" => operator, "value" => value, "group" => group, "block" => block }.compact
  end

  def dash_exclusion(name, *conditions, enabled: true)
    filters = conditions.map do |dimension, operator, value, group|
      dash_entry(dimension: dimension, operator: operator, value: value, group: group)
    end
    AhoyDashboard::Exclusion.create!(name: name, enabled: enabled, filters: filters)
  end

  def dash_scope(range:, filters: AhoyDashboard::Filters.new([]), include_crawlers: false, include_internal: false)
    AhoyDashboard::ScopeQuery.call(range: range, filters: filters, include_crawlers: include_crawlers,
                                   include_internal: include_internal)
  end

  def dash_group(*conditions)
    AhoyDashboard::FilterGroup.new(conditions.map { |dimension, operator, value| dash_filter(dimension, operator, value) })
  end

  def dash_filter(dimension, operator, value)
    AhoyDashboard::Filter.new(dimension: AhoyDashboard::Dimension.find(dimension), operator: operator, value: value)
  end

  def dash_filters(*conditions)
    AhoyDashboard::Filters.new(
      conditions.map { |dimension, operator, value| dash_filter(dimension, operator, value) }
    )
  end

  def dash_stat(stats, key)
    stats.find { |stat| stat.metric.key == key }
  end

  def dash_value(stats, key)
    dash_stat(stats, key)&.value
  end

  def dash_row(result, label)
    result.rows.find { |row| row.label == label }
  end
end

RSpec.configure do |config|
  config.include AhoyDashboardFixtures

  config.around do |example|
    dimensions = AhoyDashboard::Dimension.registry.dup
    reports = AhoyDashboard::Report.registry.dup

    example.run

    AhoyDashboard::Dimension.instance_variable_set(:@registry, dimensions)
    AhoyDashboard::Report.instance_variable_set(:@registry, reports)
  end
end
