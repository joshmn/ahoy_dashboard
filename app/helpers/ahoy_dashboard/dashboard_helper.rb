module AhoyDashboard::DashboardHelper
  include AhoyDashboard::Compatibility::ClassNames

  UNKNOWN_INITIAL = "?".freeze
  COUNTRY_CODE_LENGTH = 2
  COUNTRY_CODE = /\A[A-Za-z]{2}\z/
  REGIONAL_INDICATOR_OFFSET = 0x1F1E6 - "A".ord
  FAVICON_SIZE = 16

  def dash_filter_params(destination: nil, carried: {}, base: query.to_query)
    params = base.merge(AhoyDashboard::FilterDestination.prefixed(carried))
    destination.present? ? params.merge(return: destination) : params
  end

  def dash_site_name
    AhoyDashboard.host || request.host
  end

  def dash_range_hint(drop: AhoyDashboard::RangeHint::DROP_FILTER)
    AhoyDashboard::RangeHint.call(query.filters, drop: drop)
  end

  def dash_snapshot_cache(section, snapshot: nil, &block)
    cached = snapshot || @presenter.try(:fragment_cache_key)

    cache_if(cached, dash_dashboard_cache_key(section, snapshot: snapshot),
             expires_in: AhoyDashboard::Dashboards::Snapshot::MAX_AGE, &block)
  end

  def dash_dashboard_cache_key(section, snapshot: nil)
    generation = if snapshot
      [ snapshot.snapshot_key, snapshot.computed_at.iso8601(9) ]
    elsif @presenter.respond_to?(:fragment_cache_key)
      @presenter.fragment_cache_key
    end

    [ "ahoy_dashboard/dashboard", section, generation,
      request.base_url, request.script_name, I18n.locale, query.to_query,
      AhoyDashboard::Context.current, AhoyDashboard.url_options, dashboard_allowed?(:manage), dashboard_allowed?(:assistant) ]
  end

  CHANNEL_ICONS = {
    AhoyDashboard::Sql::DIRECT => :enter,
    AhoyDashboard::Sql::ORGANIC_SEARCH => :search,
    AhoyDashboard::Sql::PAID_SEARCH => :tag,
    AhoyDashboard::Sql::REFERRAL => :link,
    AhoyDashboard::Sql::ORGANIC_SOCIAL => :nodes,
    AhoyDashboard::Sql::EMAIL => :mail,
    AhoyDashboard::Sql::AI_ASSISTANTS => :sparkle,
    AhoyDashboard::Sql::INTERNAL => :home
  }.transform_keys(&:downcase).freeze
  CHANNEL_FALLBACK_ICON = :compass

  def dash_channel_icon(channel)
    CHANNEL_ICONS.fetch(channel.to_s.strip.downcase, CHANNEL_FALLBACK_ICON)
  end

  GROUP_ICONS = {
    "Page" => :file, "Source" => :share, "Location" => :pin,
    "Device" => :monitor, "Behaviour" => :target, "Goals" => :target
  }.freeze

  def dash_dimension_icon(dimension)
    GROUP_ICONS.fetch(dimension.group.to_s, :layers)
  end

  def dash_picker_icon(facet)
    return dash_dimension_icon(facet.dimension) if facet.dimension?

    GROUP_ICONS.fetch(facet.group.to_s, :layers)
  end

  ICON_SIZE = 14

  MAX_TABS = 4
  PRIMARY_TABS = 2

  def dash_filter_tokens(filters)
    filters.groups.map do |group|
      {
        filters: group.map do |filter|
          { dimension: filter.dimension.key, label: filter.dimension.filter_label,
            operator: filter.operator, value: filter.value }
        end
      }
    end
  end

  def dash_destination_path(destination, params = {})
    public_send(AhoyDashboard::FilterDestination.route(destination), params)
  end

  MARKDOWN_TAGS = %w[p br strong em b i code pre ul ol li a h3 h4 h5 blockquote
                     table thead tbody tr th td hr].freeze
  MARKDOWN_ATTRIBUTES = %w[href].freeze

  def dash_markdown(text)
    return "" if text.blank?

    dash_scrolling_tables(sanitize(AhoyDashboard::Markdown.to_html(text), tags: MARKDOWN_TAGS, attributes: MARKDOWN_ATTRIBUTES))
  end

  def dash_scrolling_tables(html)
    fragment = Nokogiri::HTML::DocumentFragment.parse(html.to_str)
    fragment.css("table").each.with_index(1) do |table, position|
      table.wrap(dash_table_scroll(label: "Table #{position} in this answer, scrolls sideways", region: true) { "" })
    end

    fragment.to_html.html_safe
  end

  def dash_number(value)
    AhoyDashboard::CompactNumber.call(value)
  end

  def dash_ago(time, never: "Never")
    AhoyDashboard::DateFormat.ago(time, never: never)
  end

  def dash_dashboard_json(presenter)
    presenter.as_json.tap do |json|
      json[:stats].each { |stat| stat[:delta_html] = (dash_delta(**stat[:delta]) if stat[:delta]) }
    end
  end

  def dash_favicon_tag(domain)
    letter = dash_initial(domain)
    fetched = AhoyDashboard::FaviconService.domain_for(domain)

    return tag.span(letter, class: "lc", "aria-hidden": "true") if fetched.nil?

    tag.span(
      safe_join([ tag.span(letter, class: "lc__letter"), dash_favicon_image(fetched) ]),
      class: "lc lc--icon",
      "aria-hidden": "true"
    )
  end

  def dash_favicon_image(domain)
    tag.img(
      src: favicon_path(domain),
      alt: "",
      width: FAVICON_SIZE,
      height: FAVICON_SIZE,
      loading: "lazy",
      decoding: "async",
      class: "lc__icon"
    )
  end

  def dash_initial(domain)
    stripped = domain.to_s.downcase.sub(%r{\Ahttps?://}, "").delete_prefix("www.")
    stripped[/[a-z0-9]/] || UNKNOWN_INITIAL
  end

  def dash_flag(country)
    code = AhoyDashboard::Countries.code(country)
    return if code.nil? || code.length != COUNTRY_CODE_LENGTH
    return tag.span(code.upcase, class: "tm-flag", "aria-hidden": "true") unless code.match?(COUNTRY_CODE)

    tag.span(dash_flag_glyph(code), class: "tm-flag tm-flag--emoji", "aria-hidden": "true")
  end

  def dash_flag_glyph(code)
    code.upcase.each_codepoint.map { |point| point + REGIONAL_INDICATOR_OFFSET }.pack("U*")
  end

  def dash_chip_kind(dimension_key, favicon: true)
    case dimension_key.to_s
    when "source", "referrer" then (:favicon if favicon)
    when "channel" then :channel
    when "country" then :flag
    end
  end

  def dash_row_name(label, chip: nil, chip_label: label, mono: false, class_name: nil)
    parts = [ (dash_row_chip(chip, chip_label) if chip), dash_row_label(label, split: mono) ]

    tag.span(safe_join(parts.compact), class: class_names("rn", { "mono" => mono }, class_name))
  end

  MONO_DIMENSIONS = %w[page entry_page exit_page entry_url referrer].freeze

  def dash_mono_dimension?(dimension_key)
    MONO_DIMENSIONS.include?(dimension_key.to_s)
  end

  SPLIT_OVER = 24
  SPLIT_TAIL = 16
  SPLIT_TAIL_MAX = 24

  def dash_row_label(label, split: false, mono: false)
    text = label.to_s

    return tag.span(text, class: class_names("nm", "mono" => mono)) unless split && text.length > SPLIT_OVER

    tail = dash_label_tail(text)

    tag.span(class: class_names("nm", "nm--split", "mono" => mono), title: text) do
      tag.span(text[0...-tail.length], class: "nm__head") +
        tag.span(tail, class: "nm__tail")
    end
  end

  def dash_label_tail(text)
    cut = text.rindex("/", -2)

    return text[-SPLIT_TAIL..-1] if cut.nil? || cut.zero? || text.length - cut > SPLIT_TAIL_MAX

    text[cut..-1]
  end

  def dash_row_chip(kind, label)
    case kind
    when :favicon
      return tag.span(nil, class: "lc", "aria-hidden": "true") if label.blank?

      dash_favicon_tag(label)
    when :channel
      tag.span(dash_icon(dash_channel_icon(label), size: 12), class: "lc lc--glyph", "aria-hidden": "true")
    when :flag
      flag = dash_flag(label)
      tag.span(flag, class: "flg", "aria-hidden": "true") if flag
    end
  end

  BAR_GUTTER = 52
  BAR_COLUMN = 48

  def dash_pattern_rows(matches)
    safe_join(matches.map { |path, visitors| tag.li(dash_pattern_row(path, visitors)) })
  end

  def dash_pattern_row(path, visitors)
    safe_join([
      tag.span(path, class: "grp-path"),
      tag.span(AhoyDashboard::Counted.call(visitors, noun: "visitor"), class: "grp-count")
    ])
  end

  def dash_bar_tag(share, columns: 1, inset: nil)
    fraction = share.to_f.clamp(0, 1).round(3)
    room = inset || (BAR_GUTTER + BAR_COLUMN * columns)

    tag.span(nil, class: "bar", style: "--w: calc((100% - #{room}px) * #{fraction})", "aria-hidden": "true")
  end

  def dash_tab_split(tabs)
    return [ tabs, [] ] if tabs.size <= MAX_TABS

    [ tabs.first(PRIMARY_TABS), tabs.drop(PRIMARY_TABS) ]
  end

  def dash_details_dialog(key:, title:, frame:, loading: "Loading the full list")
    dash_dialog(key: key, title: title, close_label: "Close the #{title.downcase} details") do
      dash_frame_tag(frame) { dash_empty(loading, compact: true, role: "status") }
    end
  end

  def dash_details_opener(url, frame:, key:, &block)
    dash_card_footer(action: true) do
      dash_button(url, tone: :link, class: "more", "aria-haspopup": "dialog",
                       data: { tm_frame: frame, action: "dash--modal#open", "dash--modal-key-param": key }, &block)
    end
  end

  def dash_filter_frame(category)
    "tm_filter_#{category.key}"
  end

  def dash_stylesheet_tag
    tag.link(rel: "stylesheet", href: dash_asset_url(AhoyDashboard::Assets::STYLESHEET))
  end

  def dash_javascript_tag
    tag.script(nil, type: "module", src: dash_asset_url(AhoyDashboard::Assets::SCRIPT))
  end

  def dash_asset_url(path)
    asset_path((@dash_asset_build ||= AhoyDashboard::Assets.build), path)
  end

  def dash_frame_tag(id, src: nil, rendered: false, **options, &block)
    tag.tm_frame(
      (capture(&block) if block),
      id: id,
      src: src,
      complete: ("" if rendered),
      **options
    )
  end

  def dash_chart_data(data, options)
    {
      controller: "dash--chart",
      "dash--chart-data-value": data.to_json,
      "dash--chart-options-value": options.to_json
    }
  end

  def dash_filter_row_id(category, dimension)
    "tm-filter-#{category.key}-#{dimension.key.parameterize}"
  end

  def dash_icon(name, size: ICON_SIZE, class_name: nil)
    tag.svg(
      AhoyDashboard::IconDecorator.new(name).body,
      class: class_names("ic", class_name),
      viewBox: "0 0 16 16",
      width: size,
      height: size,
      "aria-hidden": "true",
      focusable: "false"
    )
  end
end
