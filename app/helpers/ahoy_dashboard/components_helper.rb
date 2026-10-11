module AhoyDashboard
  module ComponentsHelper
    include AhoyDashboard::Compatibility::ClassNames

    BUTTON_TONES = {
      primary: "btn-primary",
      secondary: "btn-secondary",
      danger: "btn-outline-danger",
      link: "btn-link"
    }.freeze

    BUTTON_SIZES = { sm: "btn-sm", md: nil }.freeze

    BUTTON_ICON_SIZE = 14

    BADGE_TONES = {
      neutral: "bg-secondary-subtle text-secondary-emphasis",
      kind: "bg-primary-subtle text-primary-emphasis",
      success: "bg-success-subtle text-success-emphasis",
      warning: "bg-warning-subtle text-warning-emphasis",
      danger: "bg-danger-subtle text-danger-emphasis"
    }.freeze

    def dash_badge(label = nil, tone: :neutral, pill: false, **options, &block)
      classes = class_names("badge", BADGE_TONES.fetch(tone.to_sym), options.delete(:class), "rounded-pill" => pill)
      tag.span(block ? capture(&block) : label, class: classes, **options)
    end

    def dash_button_class(tone: :secondary, size: :sm, icon_only: false, extra: nil)
      variant = icon_only && tone == :danger ? "btn-link btn-icon-danger" : BUTTON_TONES.fetch(tone)
      class_names("btn", variant, BUTTON_SIZES.fetch(size), extra, "btn-icon" => icon_only)
    end

    def dash_button(label = nil, url = nil, tone: :secondary, size: :sm, icon: nil, icon_end: nil, type: "button", **options, &block)
      url, label = label, nil if block
      classes = dash_button_class(tone: tone, size: size, extra: options.delete(:class))
      body = dash_button_body(block ? capture(&block) : label, icon: icon, icon_end: icon_end)
      return link_to(body, url, class: classes, **options) if url

      button_tag(body, type: type, class: classes, **options)
    end

    def dash_icon_button(icon, label:, url: nil, tone: :link, size: :sm, type: "button", **options)
      classes = dash_button_class(tone: tone, size: size, icon_only: true, extra: options.delete(:class))
      body = dash_icon(icon, size: BUTTON_ICON_SIZE)
      return link_to(body, url, class: classes, "aria-label": label, **options) if url

      button_tag(body, type: type, class: classes, "aria-label": label, **options)
    end

    def dash_button_to(label = nil, url = nil, tone: :secondary, size: :sm, icon: nil, icon_end: nil,
                       reason: nil, confirm: nil, **options, &block)
      url, label = label, nil if block
      content = block ? capture(&block) : label
      return dash_unavailable(content, reason: reason, tone: tone, size: size) if reason.present?

      options = dash_button_form_options(options, confirm)
      classes = dash_button_class(tone: tone, size: size, extra: options.delete(:class))
      button_to(url, class: classes, **options) { dash_button_body(content, icon: icon, icon_end: icon_end) }
    end

    def dash_toggle_icon_button(off:, on:, label:, pressed: false, tone: :link, size: :sm, **options)
      classes = dash_button_class(tone: tone, size: size, icon_only: true, extra: options.delete(:class))
      body = safe_join([ dash_icon(off, size: BUTTON_ICON_SIZE, class_name: "ic-off"),
                         dash_icon(on, size: BUTTON_ICON_SIZE, class_name: "ic-on") ])

      button_tag(body, type: "button", class: classes, "aria-label": label, "aria-pressed": pressed.to_s, **options)
    end

    def dash_icon_button_to(icon, url, label:, tone: :link, size: :sm, confirm: nil, **options)
      options = dash_button_form_options(options, confirm)
      classes = dash_button_class(tone: tone, size: size, icon_only: true, extra: options.delete(:class))
      button_to(url, class: classes, "aria-label": label, **options) { dash_icon(icon, size: BUTTON_ICON_SIZE) }
    end

    def dash_unavailable(label, reason:, tone: :secondary, size: :sm, type: "button")
      @dash_unavailable_count = (@dash_unavailable_count || 0) + 1
      id = "dash-why-#{@dash_unavailable_count}"

      button = button_tag(label, type: type, class: dash_button_class(tone: tone, size: size),
                                 disabled: true, "aria-describedby": id)
      why = tag.span(reason, id: id, class: "visually-hidden")

      tag.span(safe_join([ button, why ]), class: "btn-reason", title: reason)
    end

    def dash_unavailable_notice(label, reason, fix: nil, tone: :warning, **options)
      return if reason.blank?

      action = fix && dash_button(fix[:label], fix[:url], data: { tm_frame: "_top" })

      dash_notice("#{label} is off.", detail: reason, tone: tone, action: action,
                  class: class_names("mb-3", options.delete(:class)), **options)
    end

    def dash_link(label = nil, url = nil, **options, &block)
      url, label = label, nil if block
      link_to(block ? capture(&block) : label, url, class: class_names("link-quiet", options.delete(:class)), **options)
    end

    NOTICE_ROLES = { primary: "status", warning: "status", danger: "alert" }.freeze
    TOAST_TONES = {
      success: { icon: :check, icon_class: "toast-ok", role: "status", delay: nil },
      danger: { icon: :close, icon_class: "toast-bad", role: "alert", delay: 6000 }
    }.freeze

    def dash_notice(title = nil, detail: nil, tone: :primary, action: nil, **options, &block)
      role = NOTICE_ROLES.fetch(tone.to_sym)
      detail = capture(&block) if block
      text = safe_join([ (tag.b(title) if title), detail ].compact, " ")
      classes = class_names("alert", "alert-#{tone}", options.delete(:class))

      tag.div(safe_join([ tag.p(text), action ].compact, "\n"), class: classes, role: role, **options)
    end

    def dash_toast(message, tone: :success)
      settings = TOAST_TONES.fetch(tone.to_sym)
      body = safe_join([
        tag.span(dash_icon(settings[:icon], size: BUTTON_ICON_SIZE), class: settings[:icon_class]),
        tag.span(message),
        dash_close_button(data: { action: "dash--toast#dismiss" })
      ])

      tag.div(tag.div(body, class: "toast-body"), class: "toast", role: settings[:role],
              data: { controller: "dash--toast", "dash--toast-delay-value": settings[:delay] }.compact)
    end

    def dash_empty(title = nil, hint: nil, action: nil, secondary: nil, compact: false, fill: false, **options)
      title ||= options.delete(:title)
      buttons = []
      if action
        tone = action.fetch(:primary, true) ? :primary : :secondary
        buttons << dash_button(action[:label], action[:url], tone: tone, data: action[:data])
        buttons << dash_button(secondary[:label], secondary[:url], data: secondary[:data]) if secondary
      end

      parts = [
        tag.p(title, class: "empty-title"),
        (tag.p(hint, class: "empty-hint") if hint.present?),
        (tag.div(safe_join(buttons), class: "empty-actions") if buttons.any?)
      ]
      classes = class_names("empty", options.delete(:class), "empty-compact" => compact, "h-100" => fill)

      tag.div(safe_join(parts.compact), class: classes, **options)
    end

    def dash_page_head(title = nil, lede: nil, back: nil, kicker: nil, actions: nil, clip: false, **options, &block)
      title ||= options.delete(:title)
      heading = clip ? tag.h1(title, class: "text-truncate", title: title) : tag.h1(title)
      actions = capture(&block) if block

      above =
        if back.present?
          link_to(back[:url], class: "page-head-kicker", data: { tm_frame: "_top" }) do
            safe_join([ dash_icon(:chevron_left, size: 12), back[:label] ])
          end
        elsif kicker.present?
          tag.p(kicker, class: "page-head-kicker")
        end

      main = tag.div(safe_join([ above, heading, (tag.p(lede, class: "page-head-lede") if lede.present?) ].compact),
                     class: "page-head-main")
      side = tag.div(actions, class: "page-head-actions") if actions.present?

      tag.header(safe_join([ main, side ].compact), class: class_names("page-head", options.delete(:class)), **options)
    end

    def dash_page_tabs(tabs = nil, actions: nil, **options, &block)
      tabs = capture(&block) if block
      parts = [ tabs, (tag.div(actions, class: "page-tabs-actions") if actions.present?) ]

      tag.div(safe_join(parts.compact), class: class_names("page-tabs", options.delete(:class)), **options)
    end

    def dash_card(element: :div, padded: false, **options, &block)
      classes = class_names("card", options.delete(:class), "card-body" => padded)
      content_tag(element, capture(&block), class: classes, **options)
    end

    def dash_card_header(title = nil, id: nil, level: :h2, title_class: nil, element: :div, **options, &block)
      actions = capture(&block) if block
      parts = [
        (content_tag(level, title, id: id, class: class_names("card-title", title_class)) if title),
        (tag.div(actions, class: "card-header-actions") if actions.present?)
      ]

      content_tag(element, safe_join(parts.compact), class: class_names("card-header", options.delete(:class)), **options)
    end

    def dash_card_footer(action: false, element: nil, **options, &block)
      element ||= action ? :footer : :div
      classes = class_names("card-footer", options.delete(:class), "card-footer-action mt-auto" => action)

      content_tag(element, capture(&block), class: classes, **options)
    end

    METER_TONES = { neutral: nil, warning: "meter-warning", danger: "meter-danger" }.freeze

    def dash_meter(share, label:, tone: :neutral, **options)
      filled = (share.to_f.clamp(0, 1) * 100).round(1)
      classes = class_names("progress", "dash-meter", METER_TONES.fetch(tone.to_sym), options.delete(:class))

      tag.div(tag.div("", class: "progress-bar dash-meter-fill", style: "width: #{[ filled, 1.5 ].max}%"),
              class: classes, role: "progressbar", "aria-label": label,
              "aria-valuemin": 0, "aria-valuemax": 100, "aria-valuenow": filled, **options)
    end

    def dash_tabs(items, label: nil, select: false, **options)
      links = items.map do |item|
        data = item[:data].to_h
        data = data.merge(action: [ data[:action], "dash--tabs#select" ].compact.join(" ")) if select
        link_to(item[:label], item[:url], class: "nav-link", "aria-current": ("true" if item[:current]), data: data.presence)
      end
      data = options.delete(:data).to_h
      data = data.merge(action: [ data[:action], "keydown->dash--tabs#navigate" ].compact.join(" ")) if select

      tag.nav(safe_join(links), class: class_names("nav nav-pills card-tabs", options.delete(:class)),
                                "aria-label": label, data: data.presence, **options)
    end

    def dash_table(label:, cols: nil, compact: false, region: false, **options, &block)
      tracks = cols.to_s.scan(/minmax\([^)]*\)|\S+/)
      columns = tracks.each_with_index.map do |track, index|
        width = track[/\A(\d+)px\z/, 1]&.to_i
        edges = [ index.zero?, index == tracks.size - 1 ].count(true) * 9
        tag.col(style: ("width: #{width + 10 + edges}px" if width))
      end
      floor = tracks.sum { |track| track[/\A(\d+)px\z/, 1]&.to_i || track[/\Aminmax\((\d+)px/, 1]&.to_i || 100 }

      body = safe_join([ (tag.colgroup(safe_join(columns)) if columns.any?), capture(&block) ].compact)
      classes = class_names("table table-hover dash-table", options.delete(:class), "dash-table-compact" => compact,
                                                                                          "dash-table-auto" => tracks.empty?)
      style = ("--dash-table-floor: #{floor + (tracks.size * 10) + 18}px" if tracks.any?)

      dash_table_scroll(label: label, region: region) { tag.table(body, class: classes, style: style, **options) }
    end

    def dash_input_group(size: :sm, **options, &block)
      tag.div(capture(&block), class: class_names("input-group", options.delete(:class), "input-group-sm" => size == :sm,
                                                  "input-group-lg" => size == :lg), **options)
    end

    def dash_table_scroll(label:, region: false, &block)
      tag.div(capture(&block), class: "table-scroll table-responsive", tabindex: 0,
                               role: (region ? "region" : "group"), "aria-label": label)
    end

    def dash_table_confirm(message, span:, cancel: nil, &block)
      actions = [ capture(&block) ]
      actions << dash_button("Cancel", cancel, tone: :link, autofocus: true) if cancel
      body = tag.div(safe_join([ tag.p(message, class: "text-break"), tag.div(safe_join(actions), class: "row-confirm-actions") ]),
                     class: "row-confirm-body flex-wrap")

      tag.tr(tag.td(body, colspan: span), class: "row-confirm", id: "confirm")
    end

    def dash_form_with(card: false, stack: true, **options, &block)
      options[:class] = class_names(options[:class], "d-flex flex-column gap-3" => stack, "card-body" => card).presence
      form_with(**options, builder: AhoyDashboard::Components::FormBuilder, &block)
    end

    # A select with its label, hidden, the same way dash_search_field carries
    # its own.
    def dash_select(name, choices, selected = nil, label:, id:, size: :sm, **options)
      classes = class_names("form-select", options.delete(:class), "form-select-sm" => size == :sm)
      select = select_tag(name, options_for_select(choices, selected), id: id, class: classes, **options)

      safe_join([ tag.label(label, for: id, class: "visually-hidden"), select ])
    end

    # A form control that holds more than one input: tokens, a chip, and the
    # text box they sit in front of. The box draws the control; the input inside
    # it draws nothing.
    def dash_token_field(**options, &block)
      tag.div(capture(&block), class: class_names("form-control d-flex flex-wrap align-items-center gap-1",
                                                  options.delete(:class)), **options)
    end

    # Bootstrap's checkbox, drawn rather than used, for a row that is itself the
    # toggle and says so with aria-pressed.
    def dash_check_mark(**options)
      tag.span(nil, class: class_names("form-check-input m-0 flex-shrink-0", options.delete(:class)),
                    "aria-hidden": "true", **options)
    end

    def dash_search_field(name, value = nil, label:, id:, size: :sm, **options)
      classes = class_names("form-control", options.delete(:class), "form-control-sm" => size == :sm)
      input = search_field_tag(name, value, id: id, class: classes, autocomplete: "off", **options)

      safe_join([ tag.label(label, for: id, class: "visually-hidden"), input ])
    end

    # A labelled date or datetime field. Here rather than in the two templates
    # that draw a custom range, so the range on the dashboard and the range on a
    # composed question cannot end up two different controls.
    def dash_range_field(name, value, label:, id:, type: "date", max: nil, size: :sm, hide_label: false, **options)
      classes = class_names("form-control", options.delete(:class), "form-control-sm" => size == :sm)
      required = options.delete(:required) { true }
      input = tag.input(type: type, name: name, id: id, value: value, max: max, class: classes, required: required, **options)

      safe_join([ tag.label(label, class: hide_label ? "visually-hidden" : "form-label", for: id), input ])
    end

    # Two shapes of the same control. An item with a url is a link and the strip
    # is navigation; an item without one is a button and the strip is a group,
    # for a choice that changes what is on screen without going anywhere. The
    # markup is the same either way, which is the only reason it is one helper.
    def dash_segmented(items, label:, size: :sm, **options)
      buttons = items.none? { |item| item[:url] }
      classes = class_names("btn", "btn-sm" => size == :sm)

      controls = items.map do |item|
        if item[:url]
          link_to(item[:label], item[:url], class: classes, "aria-current": ("page" if item[:current]),
                                            data: item[:data])
        else
          button_tag(item[:label], type: "button", class: classes,
                     "aria-pressed": item[:current] ? "true" : "false", data: item[:data])
        end
      end

      wrapper = class_names("segmented", options.delete(:class), "segmented-sm" => size == :sm)
      body = safe_join(controls)

      return tag.nav(body, class: wrapper, "aria-label": label, **options) unless buttons

      tag.div(body, class: wrapper, role: "group", "aria-label": label, **options)
    end

    def dash_close_button(label: "Dismiss", **options)
      tag.button(type: "button", class: class_names("btn-close", options.delete(:class)), "aria-label": label, **options)
    end

    def dash_disclosure(label, open: false, less: nil, bar: false, ruled: false, tone: nil, **options, &block)
      labels = [
        tag.span(label, class: class_names("disclosure-label", "disclosure-closed-only" => less)),
        (tag.span(less, class: "disclosure-label disclosure-open-only") if less)
      ]
      toggle = tag.summary(safe_join([ dash_icon(:chevron_right, size: 12, class_name: "disclosure-chevron"), *labels.compact ]),
                           class: "disclosure-toggle")
      classes = class_names("disclosure", options.delete(:class), "disclosure-bar" => bar, "disclosure-ruled" => ruled,
                            "disclosure-danger" => tone == :danger)

      tag.details(safe_join([ toggle, capture(&block) ]), class: classes, open: open, **options)
    end

    def dash_card_disclosure(title, open: false, hint: nil, **options, &block)
      heading = tag.h2(safe_join([ dash_icon(:chevron_right, size: 14, class_name: "disclosure-chevron"), title ]), class: "card-title")
      side = tag.div(tag.span(hint, class: "g-hint"), class: "card-header-actions") if hint.present?
      summary = tag.summary(safe_join([ heading, side ].compact), class: "card-header")

      tag.details(safe_join([ summary, capture(&block) ]), class: class_names("card card-disclosure disclosure", options.delete(:class)),
                                                         open: open, **options)
    end

    def dash_pager(status, previous: nil, following: nil, label: "Pages", **options)
      parts = [
        (dash_button("Previous", previous, icon: :chevron_left) if previous),
        tag.span(status, class: "pager-status"),
        (dash_button("Next", following, icon_end: :chevron_right) if following)
      ]

      tag.nav(safe_join(parts.compact, " "), class: class_names("pager", options.delete(:class)), "aria-label": label, **options)
    end

    def dash_dialog(key:, title: nil, id: "tm-modal-#{key}", close_label: nil, fit: false, narrow: false, labelledby: nil,
                    title_data: nil, header_actions: nil, **options, &block)
      if title
        heading = dash_dialog_header(title, id: "#{id}-title", close_label: close_label, data: title_data) { header_actions }
      end
      panel = tag.div(safe_join([ heading, capture(&block) ].compact), class: "modal-content dialog-panel")
      frame = tag.div(panel, class: class_names("modal-dialog modal-dialog-scrollable dialog-frame",
                                                "dialog-frame-fit" => fit, "dialog-frame-narrow" => narrow))
      data = { "dash--modal-target": "dialog", "dash--modal-key": key, action: "click->dash--modal#backdrop" }
             .merge(options.delete(:data).to_h)

      tag.div(frame, id: id, class: class_names("modal", options.delete(:class)), role: "dialog", "aria-modal": "true",
                     "aria-labelledby": labelledby || ("#{id}-title" if title), hidden: true, data: data, **options)
    end

    DIALOG_CLOSE_ACTION = "dash--modal#close".freeze

    def dash_dialog_header(title, id:, sub: nil, tooltip: false, title_class: nil, close_label: nil,
                           close_action: DIALOG_CLOSE_ACTION, data: nil, &block)
      heading = tag.h2(title, id: id, class: class_names("modal-title", title_class), title: (title if tooltip), data: data)
      heading = tag.div(safe_join([ heading, tag.p(sub, class: "dialog-sub") ]), class: "dialog-heading") if sub.present?
      actions = capture(&block) if block

      tag.div(safe_join([ heading, (tag.div(actions, class: "dialog-header-actions") if actions.present?),
                          dash_dialog_close(close_label || "Close", action: close_action) ].compact),
              class: "modal-header dialog-header")
    end

    def dash_dialog_close(label = "Close", action: DIALOG_CLOSE_ACTION)
      dash_close_button(label: label, class: "dialog-close", data: { action: action })
    end

    def dash_dialog_body(list: false, **options, &block)
      classes = class_names("modal-body", options.delete(:class), "m-list" => list)

      tag.div(capture(&block), class: classes, **options)
    end

    def dash_dialog_footer(count = nil, &block)
      actions = capture(&block) if block

      tag.div(safe_join([ (tag.span(count, class: "dialog-count", role: "status") unless count.nil?),
                          (tag.div(actions, class: "dialog-footer-actions") if actions.present?) ].compact),
              class: "modal-footer dialog-footer")
    end

    DELTA_WORDS = { good: "better", bad: "worse" }.freeze

    def dash_delta(text:, tone:, direction: nil, title: nil)
      tone = tone.to_sym
      parts = [
        (dash_icon(:up, size: 12) if direction),
        (tag.span("#{direction} ", class: "visually-hidden") if direction),
        text,
        (tag.span(", #{DELTA_WORDS[tone]}", class: "visually-hidden") if DELTA_WORDS.key?(tone))
      ]
      classes = class_names("delta", "delta-#{tone}", "delta-down" => direction.to_s == "down")

      tag.span(safe_join(parts.compact), class: classes, title: title)
    end

    def dash_tiles(label:, element: :div, ruled: false, compact: false, **options, &block)
      classes = class_names("tiles", options.delete(:class), "tiles-ruled" => ruled, "tiles-compact" => compact)
      role = "group" unless element.to_sym == :nav

      content_tag(element, capture(&block), class: classes, role: role, "aria-label": label, **options)
    end

    def dash_tile(label, value, delta: nil, note: nil, note_tone: nil, url: nil, button: false, current: nil,
                  status: false, value_title: nil, **options)
      body = safe_join([
        tag.span(label, class: "tile-label"),
        dash_tile_value(value, status: status, title: value_title),
        (dash_delta(**delta) if delta),
        (tag.span(note, class: class_names("tile-note", "tile-note-#{note_tone}" => note_tone)) if note.present?)
      ].compact, " ")
      classes = class_names("tile", options.delete(:class), "tile-option" => !current.nil?)

      return link_to(body, url, class: classes, "aria-current": ("true" if current), **options) if url
      return button_tag(body, type: "submit", class: classes, "aria-pressed": current.to_s, **options) if button

      tag.div(body, class: classes, **options)
    end

    def dash_menu(id:, label: nil, icon: nil, toggle: :button, caret: true, chevron: false, align: :start, pressed: nil,
                  aria_label: nil, button_id: nil, button_class: nil, menu_class: nil, panel_class: nil, after: nil,
                  **options, &block)
      button_id ||= "#{id}-button"
      body = safe_join([
        (dash_icon(icon, size: 14) if icon),
        tag.span(label),
        (dash_icon(:chevron_down, size: 11) if chevron)
      ].compact)
      classes =
        if toggle == :tab
          class_names("nav-link menu-tab", button_class)
        else
          dash_button_class(extra: [ ("dropdown-toggle" if caret), button_class ])
        end

      button = button_tag(body, type: "button", class: classes, id: button_id,
                                "aria-expanded": "false", "aria-controls": id, "aria-label": aria_label,
                                "aria-pressed": (pressed.to_s unless pressed.nil?),
                                data: { "dash--menu-target": "button", action: "dash--menu#toggle" })
      panel = tag.div(capture(&block), id: id, "aria-labelledby": button_id, data: { "dash--menu-target": "panel" },
                                       class: class_names("dropdown-menu tm-popover", panel_class,
                                                          "dropdown-menu-end" => align == :end))

      tag.div(safe_join([ button, panel, after ].compact), class: class_names("dropdown", menu_class),
              data: { controller: "dash--menu" }.merge(options.delete(:data).to_h), **options)
    end

    def dash_link_menu(id:, label:, items: [], groups: nil, section: nil, icon: nil, menu_class: nil, panel_class: nil,
                       button_class: nil, align: :start)
      dash_menu(id: id, label: label, icon: icon, menu_class: menu_class, button_class: button_class, align: align,
                aria_label: ("#{section}: #{label}" if section.present? && groups.present?),
                panel_class: class_names("tm-scroll", panel_class, "menu-grouped" => groups.present?)) do
        if groups.present?
          dash_menu_groups(groups, id: id)
        else
          safe_join([ (dash_menu_header(section) if section.present?), *items.map { |item| dash_link_menu_item(item) } ].compact)
        end
      end
    end

    def dash_menu_groups(groups, id:)
      sections = groups.each_with_index.map do |(heading, items), index|
        dash_menu_group(heading, id: "#{id}-group-#{index}", first: index.zero?) do
          safe_join(items.map { |item| dash_link_menu_item(item) })
        end
      end

      safe_join(sections)
    end

    def dash_menu_group(heading, id:, first: false, &block)
      body = safe_join([ dash_menu_header(heading, id: id), capture(&block) ])

      safe_join([ (tag.hr(class: "dropdown-divider") unless first),
                  tag.div(body, role: "group", "aria-labelledby": id, class: "menu-group") ].compact)
    end

    def dash_link_menu_item(item)
      dash_menu_item(item[:label], item[:url], current: item[:active], note: item[:note], data: item[:data])
    end

    def dash_menu_item(label = nil, url = nil, current: false, tick: false, note: nil, icon: nil, chevron: false,
                       meta: nil, danger: false, method: nil, form_class: nil, **options, &block)
      marked = current || tick
      main = safe_join([ (dash_icon(icon, size: 13) if icon), (block ? capture(&block) : dash_menu_item_label(label, meta)) ].compact)
      ending = safe_join([
        (tag.span(note) if note.present?),
        (dash_icon(:check, size: 13, class_name: "ck") if marked),
        (dash_icon(:chevron_right, size: 12) if chevron && !marked)
      ].compact)
      body = safe_join([ tag.span(main, class: "menu-item-main"), (tag.span(ending, class: "menu-item-end") if ending.present?) ].compact, " ")
      classes = class_names("dropdown-item menu-item", options.delete(:class),
                            "menu-item-danger" => danger, "menu-item-tall" => meta.present?)

      return button_to(url, method: method, class: classes, form_class: form_class, **options) { body } if method
      return link_to(body, url, class: classes, "aria-current": ("true" if current), **options) if url

      button_tag(body, type: "button", class: classes, **options)
    end

    def dash_menu_header(text, id: nil)
      tag.div(text, class: "dropdown-header menu-header", id: id)
    end

    # A column of pills, for a rail down the side of a dialog or a page.
    def dash_nav_list(**options, &block)
      tag.ul(capture(&block), class: class_names("nav nav-pills flex-column", options.delete(:class)), **options)
    end

    # One pill in dash_nav_list. A url makes it a link and a method a form of
    # one button; neither, or disabled, is a button that is there and cannot be
    # pressed. current marks it: true for a choice, or an aria-current token.
    def dash_nav_item(label, url = nil, icon: nil, current: false, count: nil, method: nil, params: {}, disabled: false,
                      **options)
      classes = class_names("nav-link d-flex align-items-center gap-2 w-100 text-start", options.delete(:class),
                            "active" => current)
      body = safe_join([ (dash_icon(icon, size: 13, class_name: "flex-shrink-0") if icon),
                         tag.span(label, class: "text-truncate flex-grow-1"), count ].compact)
      marked = current == true ? "true" : current.presence

      control =
        if method && !disabled
          button_to(url, method: method, params: params, class: classes, form_class: "m-0", **options) { body }
        elsif url && !disabled
          link_to(body, url, class: classes, "aria-current": marked, **options)
        else
          button_tag(body, type: "button", class: classes, disabled: disabled, **options)
        end

      tag.li(control, class: "nav-item")
    end

    def dash_nav_menu(id:, label:, items:, active: false)
      toggle = link_to(label, "#", class: class_names("nav-link dropdown-toggle", "active" => active), role: "button",
                                   id: "#{id}-button", "aria-expanded": "false", "aria-controls": id,
                                   data: { "dash--menu-target": "button", action: "dash--menu#toggle" })
      entries = items.map do |item|
        tag.li(link_to(item[:label], item[:url], class: class_names("dropdown-item", "active" => item[:active]),
                                                 "aria-current": ("page" if item[:active]),
                                                 data: { "dash--menu-target": "item" }.merge(item[:data].to_h)))
      end
      panel = tag.ul(safe_join(entries), class: "dropdown-menu", id: id, "aria-labelledby": "#{id}-button",
                                         data: { "dash--menu-target": "panel" })

      tag.li(safe_join([ toggle, panel ]), class: "nav-item dropdown", data: { controller: "dash--menu" })
    end

    private

    def dash_menu_item_label(label, meta)
      return tag.span(label, class: "menu-item-label") if meta.blank?

      tag.span(safe_join([ tag.span(label, class: "menu-item-label"), tag.span(meta, class: "menu-item-meta") ], " "),
               class: "menu-item-stack")
    end

    def dash_tile_value(value, status:, title:)
      if value.nil? || value.to_s == "&mdash;"
        return safe_join([ tag.span("&mdash;".html_safe, class: "tile-value tile-empty", "aria-hidden": "true"),
                           tag.span("None", class: "visually-hidden") ])
      end

      tag.span(value, class: status ? "tile-status" : "tile-value", title: title)
    end

    def dash_button_body(content, icon: nil, icon_end: nil)
      safe_join([
        (dash_icon(icon, size: BUTTON_ICON_SIZE) if icon),
        content,
        (dash_icon(icon_end, size: BUTTON_ICON_SIZE) if icon_end)
      ].compact)
    end

    def dash_button_form_options(options, confirm)
      options = { form_class: "d-inline" }.merge(options)
      options[:data] = (options[:data] || {}).merge(tm_confirm: confirm) if confirm
      options
    end
  end
end
