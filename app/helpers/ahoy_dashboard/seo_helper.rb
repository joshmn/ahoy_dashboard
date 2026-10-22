module AhoyDashboard
  module SeoHelper
    PLOT_WIDTH = 640
    PLOT_HEIGHT = 96
    PLOT_INSET = 10
    PLOT_MINIMUM = 3
    READING_COUNTS = { 1 => "One", 2 => "Two" }.freeze
    OVERVIEW_TITLES = {
      "Cited" => "The AI overview cited your site",
      "Shown" => "An AI overview showed without your site in it"
    }.freeze

    Stack = Data.define(:day, :x, :width, :segments)
    Segment = Data.define(:key, :y, :height)

    def self.not_installed_reason(name)
      "#{AhoyDashboard::FeatureState.for(name).label} isn't installed."
    end

    def seo_date(value)
      AhoyDashboard::DateFormat.short(value, zone: (@seo_time_zone ||= AhoyDashboard.time_zone))
    end

    def seo_charted?(points)
      Array(points).size >= PLOT_MINIMUM
    end

    def seo_readings(points)
      pairs = Array(points).map { |label, value| [ label.to_s, seo_reading_value(value) ] }
      return "No readings in this range yet. The chart starts at the third." if pairs.empty?

      count = READING_COUNTS.fetch(pairs.size, pairs.size.to_s)
      noun = pairs.one? ? "reading" : "readings"
      values = pairs.map(&:last)

      listed =
        if pairs.many? && values.uniq.one?
          "#{pairs.map(&:first).to_sentence}, both #{values.first}"
        else
          pairs.map { |label, value| "#{label} at #{value}" }.to_sentence
        end

      "#{count} #{noun} so far, #{listed}. The chart starts at the third."
    end

    def seo_reading_value(value)
      number = value.to_f
      number == number.round ? number.round.to_s : number.round(1).to_s
    end

    def seo_label(text, path: false)
      value = text.to_s
      return dash_value(nil) if value.blank? || value == "&mdash;"

      tag.span(dash_row_label(value, split: path, mono: path),
               class: class_names("seo-label", "seo-label--path" => path), title: value)
    end

    def seo_seeded(text, seed)
      value = text.to_s
      at = seed.present? && value != seed ? value.index(seed.to_s) : nil
      return seo_label(value) if at.nil?

      parts = [ value[0...at], tag.span(seed, class: "seo-seed"), value[(at + seed.length)..-1] ]
      tag.span(tag.span(safe_join(parts), class: "nm"), class: "seo-label", title: value)
    end

    def seo_referer_path
      AhoyDashboard::Seo::Referer.local_path(request.referer, host: request.host)
    end

    def seo_page_link(url, stack: false)
      value = AhoyDashboard::Seo::Formatting.url_path(url).to_s
      return seo_label(value, path: true) if value.blank? || value == "&mdash;" || !value.start_with?("/")

      link_to dashboard_path(query.filter_link_params("page", value)), class: "seo-link min-w-0",
              data: { tm_frame: "_top" } do
        stack ? seo_stacked_path(value) : seo_label(value, path: true)
      end
    end

    def seo_stacked_path(value)
      head, tail = seo_path_parts(value)
      return seo_label(value, path: true) if head.nil?

      tag.span(class: "seo-label seo-label--path seo-label--stack", title: value) do
        tag.span(head, class: "nm mono seo-stack__head") + tag.span(tail, class: "nm mono seo-stack__tail")
      end
    end

    def seo_path_parts(value)
      return [ nil, value ] if value.length <= AhoyDashboard::DashboardHelper::SPLIT_OVER

      segments = value.split("/", -1)
      longest = segments.each_with_index.max_by { |segment, _index| segment.length }.last
      return [ nil, value ] if longest <= 1

      [ "#{segments[0...longest].join("/")}/", segments[longest..-1].join("/") ]
    end

    def seo_track_path(query, return_to: nil)
      return unless dashboard_allowed?(:manage) || seo_tracked?(query)

      return unless seo_tracking?

      tracked = seo_tracked_keyword_id(query)
      return rank_keyword_path(keyword: tracked) if tracked.present?

      new_settings_serp_keyword_path(query: query, return_to: return_to || request.fullpath)
    end

    def seo_site_link(domain, css: "seo-link min-w-0")
      link_to("https://#{domain}", class: css, target: "_blank", rel: "noopener noreferrer", title: domain) do
        safe_join([ dash_row_label(domain, mono: true), tag.span(", opens in a new tab", class: "visually-hidden") ])
      end
    end

    def seo_tracking?
      AhoyDashboard::Serp.installed?
    end

    def seo_untracked_reason
      SeoHelper.not_installed_reason(:serp)
    end

    def seo_disabled_box(id, label)
      why = "#{id}-why"

      safe_join([
        tag.input(type: "checkbox", id: id, disabled: true, "aria-label": label, "aria-describedby": why,
                  title: seo_untracked_reason),
        tag.span(seo_untracked_reason, id: why, class: "visually-hidden")
      ])
    end

    def seo_tracked?(query)
      seo_tracked_keyword_id(query).present?
    end

    def seo_tracked_keyword_id(query)
      @tracked_keywords.id_for(query) if @tracked_keywords
    end

    def seo_track_link(query, button: false, return_to: nil)
      return unless dashboard_allowed?(:manage) || seo_tracked?(query)

      unless seo_tracking?
        return dash_unavailable(button ? "Track keyword" : "Track", reason: seo_untracked_reason,
                                tone: button ? :secondary : :link)
      end

      label = if seo_tracked?(query)
        button ? "See rankings" : "Tracked"
      else
        button ? "Track keyword" : "Track"
      end

      dash_button label, seo_track_path(query, return_to: return_to),
                  tone: button ? :secondary : :link, data: { tm_frame: "_top" }
    end

    def seo_track_form(id, return_to: nil)
      return unless dashboard_allowed?(:manage)

      return dash_unavailable("Track these", reason: seo_untracked_reason, tone: :link) unless seo_tracking?

      form_with url: new_settings_serp_keyword_import_path, method: :get, id: id, data: { tm_frame: "_top" } do
        safe_join([
          hidden_field_tag(:batch, 1, id: nil),
          hidden_field_tag(:return_to, return_to || request.fullpath, id: nil),
          dash_button("Track these", type: "submit", tone: :link)
        ])
      end
    end

    def seo_track_all(form, label: nil)
      return unless dashboard_allowed?(:manage)

      box = if seo_tracking?
        seo_track_all_box(form, label)
      else
        seo_disabled_box("#{form}-all", ("Select every search" if label.nil?))
      end
      return box if label.nil?

      tag.span(safe_join([ box, tag.label(label, for: "#{form}-all", class: "seo-track-all__label") ]),
               class: "seo-track-all")
    end

    def seo_track_all_box(form, label)
      return unless dashboard_allowed?(:manage)

      tag.input(type: "checkbox", id: "#{form}-all",
                "aria-label": (label.nil? ? "Select every search" : nil),
                data: { "dash--check-all-target": "master", action: "change->dash--check-all#toggle" })
    end

    def seo_track_box(query, form:, index:, compact: false)
      return unless dashboard_allowed?(:manage)

      return seo_disabled_box("#{form}-#{index}", "Track #{query}") unless seo_tracking?

      if seo_tracked?(query)
        path = rank_keyword_path(keyword: seo_tracked_keyword_id(query))
        return dash_button("Tracked", path, tone: :link, data: { tm_frame: "_top" }) unless compact

        return link_to(path, class: "seo-tracked", title: "Already tracked", data: { tm_frame: "_top" }) do
          safe_join([ dash_icon(:check, size: 12), tag.span("#{query} is already tracked", class: "visually-hidden") ])
        end
      end

      check_box_tag("track[]", query, false, id: "#{form}-#{index}", form: form, aria: { label: "Track #{query}" },
                    data: { "dash--check-all-target": "box", action: "change->dash--check-all#sync" })
    end

    def seo_csv(presenter, key = nil, label: "CSV")
      table = presenter.csv_table(key)
      return if table.nil?

      dash_button label, presenter.csv_path(table.key), tone: :link, icon: :download,
                  aria: { label: "Download #{table.label} as CSV" }, data: { tm_frame: "_top" }
    end

    def seo_period_menu(presenter, id:)
      dash_link_menu(id: id, icon: :cal, label: presenter.range_label, section: "Date range",
                     items: presenter.period_options)
    end

    def seo_group_header(presenter, group)
      title = safe_join([ group.title, dash_badge(group.rows.size, tone: group.tone, class: "seo-count") ], " ")

      dash_card_header(title, title_class: "seo-group-title") do
        safe_join([ tag.span(group.note, class: "g-hint"), seo_csv(presenter, group.key) ])
      end
    end

    def seo_link(text, url)
      link_to(url, class: "seo-link min-w-0", data: { tm_frame: "_top" }) { seo_label(text) }
    end

    def seo_plot(values, width: PLOT_WIDTH, height: PLOT_HEIGHT, floor: nil, ceiling: nil, inset: PLOT_INSET, places: 2)
      numbers = Array(values).map { |value| value&.to_f }
      known = numbers.compact
      return nil if numbers.size < 2 || known.empty?

      low = floor || known.min
      high = ceiling || known.max
      step = width.to_f / (numbers.size - 1)
      drawing = false

      numbers.each_with_index.map { |value, index|
        next drawing = false if value.nil?

        x = (index * step).round(places)
        y = seo_plot_y(value, height: height, floor: low, ceiling: high, inset: inset, places: places)
        command = drawing ? "L" : "M"
        drawing = true

        "#{command}#{x} #{y}"
      }.select { |segment| segment }.join(" ")
    end

    def seo_plot_y(value, height: PLOT_HEIGHT, floor: 0, ceiling: 100, inset: PLOT_INSET, places: 2)
      span = (ceiling - floor).abs < 1e-9 ? 1.0 : (ceiling - floor).to_f

      (height - ((value.to_f - floor) / span * (height - (inset * 2))) - inset).round(places)
    end

    def seo_plot_percent(value, height: PLOT_HEIGHT, floor: 0, ceiling: 100)
      (seo_plot_y(value, height: height, floor: floor, ceiling: ceiling) / height * 100).round(2)
    end

    def seo_stacks(days, keys:, width: PLOT_WIDTH, height: PLOT_HEIGHT)
      peak = days.map(&:total).max.to_i
      return [] if days.empty? || peak.zero?

      step = width.to_f / days.size
      bar = step * (days.size > 60 ? 1.0 : 0.72)
      unit = height.to_f / peak

      days.each_with_index.map do |day, index|
        floor = height.to_f

        segments = keys.map do |key|
          size = day.count(key) * unit
          next if size.zero?

          floor -= size
          Segment.new(key: key, y: floor.round(2), height: size.round(2))
        end.select { |value| value }

        Stack.new(day: day, x: (index * step + (step - bar) / 2).round(2), width: bar.round(2), segments: segments)
      end
    end

    def seo_meter(share, wide: false)
      tag.span(class: class_names("seo-meter", "seo-meter--wide" => wide),
               style: "--w: #{(share.to_f.clamp(0, 1) * 100).round(1)}%")
    end

    def seo_figure(share, label, wide: false, number: false)
      tag.div(class: class_names("seo-figure", "seo-figure--start" => wide)) do
        safe_join([ seo_meter(share, wide: wide), tag.span(label, class: number ? "seo-figure__num" : "seo-figure__pct") ])
      end
    end

    def seo_domain(domain, mine:)
      safe_join([ seo_label(domain, path: true), (dash_badge("You", tone: :kind) if mine) ].compact)
    end

    def seo_overview_badge(label, titled: true)
      return dash_value(nil) if label.nil?

      dash_badge(label, tone: label == "Cited" ? :success : :neutral, title: (OVERVIEW_TITLES[label] if titled))
    end
  end
end
