module AhoyDashboardRequests
  CHART = "[data-dash--chart-options-value]".freeze

  def document
    Nokogiri::HTML5(response.body)
  end

  def get_frame(path, frame, params: {}, headers: {})
    get path, params: params, headers: headers.merge("Tm-Frame" => frame)
  end

  def open_palette
    get_frame(document.at_css("#tm-palette")["data-commands-url"], "tm-palette-commands")
  end

  def open_filter_dialog
    get_frame(document.at_css("#tm-filter-modal")["data-dash--filter-modal-contents-value"], "tm-filter-controls")
  end

  def dash_chart(body = response.body)
    Nokogiri::HTML5(body).at_css(CHART)
  end

  def dash_chart_options(chart = dash_chart)
    JSON.parse(chart["data-dash--chart-options-value"])
  end

  def dash_chart_series(chart = dash_chart)
    JSON.parse(chart["data-dash--chart-data-value"])
  end

  def dash_chart_points(chart = dash_chart, series: 0)
    dash_chart_series(chart)[series]["data"]
  end

  def dash_chart_plugin(name, chart = dash_chart)
    dash_chart_options(chart).dig("library", "plugins", name)
  end

  def disabled_button_reason(label)
    button = document.css("button[disabled][aria-describedby]").find { |node| node.text.strip == label }
    expect(button).not_to be_nil, "expected a disabled #{label} button with a reason"

    document.at_css("##{button['aria-describedby']}").text
  end

  def link_query(href)
    Rack::Utils.parse_nested_query(URI.parse(href).query.to_s)
  end
end

RSpec.configure { |config| config.include AhoyDashboardRequests, type: :request }
