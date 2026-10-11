module AhoyDashboard::DashboardHelper
  include AhoyDashboard::Compatibility::ClassNames

  UNKNOWN_INITIAL = "?".freeze
  COUNTRY_CODE_LENGTH = 2
  COUNTRY_CODE = /\A[A-Za-z]{2}\z/
  REGIONAL_INDICATOR_OFFSET = 0x1F1E6 - "A".ord
  FAVICON_SIZE = 16
  MAX_SEARCH_TERM = 100

  # Where applying a filter or picking a segment lands. The dashboard is the
  # default and the only other surface that asks the same question of the same
  # filters is explore, so this is an allowlist rather than a path in the URL.
  DESTINATIONS = { "explore" => :explore_path }.freeze
  DESTINATION_KEYS = %i[dimension columns saved].freeze

  # The same keys again, prefixed, for the filter dialog, which has a
  # `dimension` of its own: the one whose values it is listing. Unprefixed the
  # two meanings are one parameter, so the dialog opened from explore would
  # scope itself to explore's grouping and then hand that back as the filter's
  # own.
  CARRIED_PREFIX = "for_".freeze

  def dash_seo_installed?
    AhoyDashboard::Seo::Surface.installed?(AhoyDashboard::Seo::Surface::FEATURES)
  end

  def dash_missing_features
    AhoyDashboard::Installation.switched_on_without_tables
  end

  def dash_not_installed
    AhoyDashboard::FeatureState::BADGE
  end

  def dash_carried_params(carried)
    carried.to_h.transform_keys { |key| :"#{CARRIED_PREFIX}#{key}" }
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

  # Which glyph a filter category wears in the menu. The icon is what makes a
  # list of twelve abstract nouns scannable; without one they read as a wall.
  CATEGORY_ICONS = {
    "page" => :file, "hostname" => :globe,
    "source" => :share, "utm" => :share,
    "location" => :pin,
    "screen_size" => :monitor, "browser" => :monitor, "os" => :monitor,
    "goal" => :target, "property" => :layers, "custom" => :layers, "crawler" => :user,
    "browsed" => :file
  }.freeze

  def dash_category_icon(category_key)
    CATEGORY_ICONS.fetch(category_key.to_s, :layers)
  end

  # A dimension wears its group's glyph. Five groups, five icons, so the filter
  # dialog's rail reads as five runs rather than fifteen nouns.
  GROUP_ICONS = {
    "Page" => :file, "Source" => :share, "Location" => :pin,
    "Device" => :monitor, "Behaviour" => :target
  }.freeze

  def dash_dimension_icon(dimension)
    GROUP_ICONS.fetch(dimension.group.to_s, :layers)
  end

  # One unbroken column of every dimension reads the four ways of asking about a
  # URL, the five UTM tags and everything about a goal as one list of twenty
  # nouns. A dimension already knows its group, so the filter dialog's rail puts
  # the declared groups in their declared order and lets
  # anything a host app registered under a name of its own follow them.
  def dash_grouped_dimensions(dimensions = AhoyDashboard::Dimension.filterable)
    AhoyDashboard::Dimension.grouped(dimensions)
  end

  # A picker facet wears its dimension's glyph when it has one, and its own
  # group's when it does not, so the two facets that are not dimensions still
  # read as part of the same set.
  def dash_picker_icon(facet)
    return dash_dimension_icon(facet.dimension) if facet.dimension?

    GROUP_ICONS.fetch(facet.group.to_s) { AhoyDashboard::PickerFacet::GROUP_ICONS.fetch(facet.group, :layers) }
  end

  ICON_SIZE = 14

  # Past this many views the header keeps the first PRIMARY_TABS as tabs and
  # folds the rest behind one control, because eight tabs do not fit beside a
  # title at any width worth designing for.
  MAX_TABS = 4
  PRIMARY_TABS = 2

  # The filters already applied, as the filter dialog's box holds them: one
  # token per group, each carrying what it needs to be said and sent again.
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
    public_send(DESTINATIONS.fetch(destination.to_s, :root_path), params)
  end

  # The assistant answers in markdown and the answer is model output, so it is
  # rendered and then stripped back to the tags an answer can need. Raw html in
  # a reply is not one of them.
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

  # The same three states chat_stream_controller.js paints, written once on the
  # server so the turn does not change what it says the moment the stream opens.
  def dash_chat_work_label(message)
    return "Read #{message.looked_at.to_sentence}" if message.looked_at.any?
    return "Writing" if message.content.present?

    "Reading the data"
  end

  def dash_number(value)
    AhoyDashboard::CompactNumber.call(value)
  end

  def dash_ago(time, never: "Never")
    return never if time.nil?

    "#{time_ago_in_words(time).delete_prefix("about ")} ago"
  end

  def dash_dashboard_json(presenter)
    presenter.as_json.tap do |json|
      json[:stats].each { |stat| stat[:delta_html] = (dash_delta(**stat[:delta]) if stat[:delta]) }
    end
  end

  # A real icon, served from our own host by AhoyDashboard::FaviconService, with the
  # letter left underneath rather than swapped out: the letter is what shows
  # while the icon is still coming, if the domain has no icon, if the fetch is
  # switched off, or if the row names something that is not a website at all.
  # Same 16px box in every one of those cases, so nothing reflows.
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

  # A country code drawn as its flag. Each letter maps to the regional indicator
  # symbol at the same offset and the browser draws the pair as one glyph, so this
  # costs no image request and no icon font.
  #
  # Windows ships no flag glyphs at all, deliberately, so there the pair falls back
  # to the two boxed letters. That is the same information rather than a broken
  # image, which is the reason to do it this way and the reason the size below has
  # to leave room for two characters.
  #
  # Anything that is not two ASCII letters keeps the old lettered chip. Geocoder
  # can return pseudo-codes like A1 and A2 for anonymous proxies, and a digit has
  # no regional indicator, so it would otherwise render as a letter beside a
  # number.
  def dash_flag(country)
    code = AhoyDashboard::Countries.code(country)
    return if code.nil? || code.length != COUNTRY_CODE_LENGTH
    return tag.span(code.upcase, class: "tm-flag", "aria-hidden": "true") unless code.match?(COUNTRY_CODE)

    tag.span(dash_flag_glyph(code), class: "tm-flag tm-flag--emoji", "aria-hidden": "true")
  end

  def dash_flag_glyph(code)
    code.upcase.each_codepoint.map { |point| point + REGIONAL_INDICATOR_OFFSET }.pack("U*")
  end

  # Which chip a dimension's rows get, read in one place so the card and the
  # details table beside it cannot disagree about whether a country has a flag.
  def dash_chip_kind(dimension_key)
    case dimension_key.to_s
    when "source", "referrer" then :favicon
    when "channel" then :channel
    when "country" then :flag
    end
  end

  # A path is read character by character when somebody is checking whether it
  # is the one they meant, so the dimensions that hold one are set in mono. A
  # country or a browser is read as a word and stays in the body face.
  MONO_DIMENSIONS = %w[page entry_page exit_page entry_url referrer].freeze

  def dash_mono_dimension?(dimension_key)
    MONO_DIMENSIONS.include?(dimension_key.to_s)
  end

  # A path is long in the middle and different at the end. Cut from the right,
  # the five facility guides that share a prefix come out as five copies of the
  # same truncated string, and the .md and .txt mirrors of a page are
  # indistinguishable from the page. Past SPLIT_OVER the label is drawn as a head
  # that ellipsises and a tail that never does, so whatever room there is goes to
  # the middle and the end always shows.
  #
  # Only for the dimensions whose values are paths and URLs. A country is short
  # and a browser name reads from the left.
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

  # The design draws two kinds of thing in front of a row's name and nothing at
  # all in front of a page: .lc, an 18px box, and .flg, a flag. Both are its own
  # classes, so a row here lines up with a row there. What goes in the box is
  # ours: the design puts a coloured letter in it and we put the site's real
  # icon, fetched and served by us so the admin's browser never tells a third
  # party which sites send this one traffic. The letter stays underneath.
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

  # The share bar behind a row. Its width is a custom property rather than the
  # width itself, because the design draws every bar from zero once its list is
  # on screen: .bar is width 0 and .ready .bar is width var(--w). Emitting the
  # width directly would paint them full and skip the sweep.
  #
  # The inset is how much room the numbers on the right need, and it differs
  # between a card and the details dialog because the dialog carries a percentage
  # column the card only shows on hover.
  # 100px is the design's own inset for a row carrying one number. A card with
  # four of them needs the bar to stop further left or it runs under the last
  # column, so the room is worked out from how many there are rather than being
  # written down again per card.
  BAR_GUTTER = 52
  BAR_COLUMN = 48

  # Joined with no separator: .grp-list:empty is what hides the box when a
  # pattern matches nothing, and a newline between rows would fill it.
  def dash_pattern_rows(matches)
    safe_join(matches.map { |path, visitors| tag.li(dash_pattern_row(path, visitors)) })
  end

  def dash_pattern_row(path, visitors)
    safe_join([
      tag.span(path, class: "grp-path"),
      tag.span("#{number_with_delimiter(visitors)} #{"visitor".pluralize(visitors)}", class: "grp-count")
    ])
  end

  def dash_bar_tag(share, columns: 1, inset: nil)
    fraction = share.to_f.clamp(0, 1).round(3)
    room = inset || (BAR_GUTTER + BAR_COLUMN * columns)

    tag.span(nil, class: "bar", style: "--w: calc((100% - #{room}px) * #{fraction})", "aria-hidden": "true")
  end

  def dash_tab_split(report)
    tabs = Array(report.tabs)
    return [ tabs, [] ] if tabs.size <= MAX_TABS

    [ tabs.first(PRIMARY_TABS), tabs.drop(PRIMARY_TABS) ]
  end

  def dash_drilldown_tab(report, query)
    report.drilldown_tab(query.filters)
  end

  # A category's dialog and the page it loads are the same frame, and
  # the two are written in different templates, so the id is built here.
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

  # A frame is a piece of the page that reloads on its own. A link or a GET form
  # inside one resolves back into it; anything that has to leave says so with
  # data-tm-frame="_top". Rendered already means no src fetch on connect.
  def dash_frame_tag(id, src: nil, rendered: false, **options, &block)
    tag.tm_frame(
      (capture(&block) if block),
      id: id,
      src: src,
      complete: ("" if rendered),
      **options
    )
  end

  def dash_chart_data(data, options, kind: :area)
    {
      controller: "dash--chart",
      "dash--chart-kind-value": kind,
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

  # A term out of the query string, so it is trimmed and capped and nothing here
  # can raise on it.
  def dash_search_term(value)
    value.to_s.strip[0, MAX_SEARCH_TERM].to_s
  end

  def dash_link_to_filter(dimension, value, label = nil, **options, &block)
    key = dimension.respond_to?(:key) ? dimension.key : dimension.to_s
    path = dashboard_path(query.filter_link_params(key, value))

    return link_to(path, **options, &block) if block

    link_to(label.presence || value.to_s, path, **options)
  end
end
