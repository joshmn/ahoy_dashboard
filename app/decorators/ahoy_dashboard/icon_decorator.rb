# frozen_string_literal: true

module AhoyDashboard

  class IconDecorator
    SHAPES = {
      chevron_down: "M4.5 6.5 L8 10 L11.5 6.5",
      chevron_up: "M4.5 9.5 L8 6 L11.5 9.5",
      chevron_right: "M6.25 4 L10.25 8 L6.25 12",
      chevron_left: "M9.75 4 L5.75 8 L9.75 12",
      back: "M9.5 3.5 L5 8 L9.5 12.5",
      close: "M4.5 4.5 L11.5 11.5 M11.5 4.5 L4.5 11.5",
      check: "M3.5 8.25 L6.5 11.25 L12.5 4.75",
      plus: "M8 3.75 L8 12.25 M3.75 8 L12.25 8",
      filter: "M2.75 4 L13.25 4 L9.25 8.75 L9.25 12.75 L6.75 11.25 L6.75 8.75 Z",
      download: "M8 3.5 L8 10.5 M4.75 7.5 L8 10.75 L11.25 7.5 M3.5 12.5 L12.5 12.5",
      expand: "M6.25 2.75 L2.75 2.75 L2.75 6.25 M9.75 2.75 L13.25 2.75 L13.25 6.25 " \
              "M6.25 13.25 L2.75 13.25 L2.75 9.75 M9.75 13.25 L13.25 13.25 L13.25 9.75",
      collapse: "M2.75 6.25 L6.25 6.25 L6.25 2.75 M13.25 6.25 L9.75 6.25 L9.75 2.75 " \
                "M2.75 9.75 L6.25 9.75 L6.25 13.25 M13.25 9.75 L9.75 9.75 L9.75 13.25",
      empty: "M2.5 12.5 L13.5 12.5 M5 12.5 L5 9.5 M8 12.5 L8 6.5 M11 12.5 L11 10.5",
      gear: [
        "M6.8 2.4h2.4l.3 1.7a4.3 4.3 0 0 1 1.5.9l1.6-.6 1.2 2.1-1.3 1.1a4.4 4.4 0 0 1 0 1.8l1.3 1.1" \
        "-1.2 2.1-1.6-.6a4.3 4.3 0 0 1-1.5.9l-.3 1.7H6.8l-.3-1.7a4.3 4.3 0 0 1-1.5-.9l-1.6.6-1.2-2.1" \
        "1.3-1.1a4.4 4.4 0 0 1 0-1.8L2.2 6.5l1.2-2.1 1.6.6a4.3 4.3 0 0 1 1.5-.9Z",
        "M9.8 8a1.8 1.8 0 1 1-3.6 0 1.8 1.8 0 1 1 3.6 0"
      ],
      search: [ "M11.6 7.2a4.4 4.4 0 1 1-8.8 0 4.4 4.4 0 0 1 8.8 0", "M10.6 10.6 14 14" ],
      exit: "M6.2 3H3.5v10h2.7M10.2 5.2 13 8l-2.8 2.8M13 8H6.8",
      cal: [ { rect: [ 2.5, 3.5, 11, 10, 2 ] }, "M2.5 6.8h11M5.6 2v2.6M10.4 2v2.6" ],
      file: [ "M4.5 2h4.6l3.4 2.9V14h-8V2Z", "M9.1 2v3h3.4" ],
      globe: [
        { circle: [ 8, 8, 5.6 ] },
        "M2.4 8h11.2M8 2.4c1.7 1.5 2.6 3.4 2.6 5.6S9.7 12.1 8 13.6C6.3 12.1 5.4 10.2 5.4 8S6.3 3.9 8 2.4Z"
      ],
      pin: [ "M8 14.2S12.6 10 12.6 6.6a4.6 4.6 0 1 0-9.2 0C3.4 10 8 14.2 8 14.2Z", { circle: [ 8, 6.6, 1.7 ] } ],
      monitor: [ { rect: [ 2, 3, 12, 8.2, 1.6 ] }, "M6 14h4M8 11.2V14" ],
      target: [ { circle: [ 8, 8, 5.6 ] }, { circle: [ 8, 8, 2.4 ] } ],
      compass: [ { circle: [ 8, 8, 5.6 ] }, "M10.4 5.6 9.1 9.1 5.6 10.4 6.9 6.9Z" ],
      share: "M4 12 12 4M6.5 4H12v5.5",
      layers: [ "M8 2.2 14 5.3 8 8.4 2 5.3Z", "m2.4 8.3 5.6 2.9 5.6-2.9", "m2.4 11.1 5.6 2.9 5.6-2.9" ],
      user: [ { circle: [ 8, 5.3, 2.6 ] }, "M3.2 13.6c.7-2.5 2.6-3.9 4.8-3.9s4.1 1.4 4.8 3.9" ],
      tag: [ "M2.5 2.5h4.9l6.1 6.1a1.35 1.35 0 0 1 0 1.9l-3 3a1.35 1.35 0 0 1-1.9 0L2.5 7.4Z",
             { circle: [ 5.5, 5.5, 1.05 ] } ],
      bookmark: "M4.5 2.5h7a.8.8 0 0 1 .8.8v10.2L8 10.6l-4.3 2.9V3.3a.8.8 0 0 1 .8-.8Z",
      chat: "M13.5 8.4c0 2.6-2.5 4.7-5.5 4.7-.7 0-1.4-.1-2-.3L2.5 14l1.2-2.6A4.4 4.4 0 0 1 2.5 8.4" \
            "c0-2.6 2.5-4.7 5.5-4.7s5.5 2.1 5.5 4.7Z",
      up: "M8 12.75 L8 3.75 M4.25 7.5 L8 3.75 L11.75 7.5",
      enter: [ "M9.8 3H13v10H9.8", "M2.8 8h7", "M7.4 5.4 10 8l-2.6 2.6" ],
      link: [ "M6.9 9.1 9.1 6.9", "M8.6 4.8l.9-.9a2.3 2.3 0 0 1 3.3 3.3l-.9.9", "M7.4 11.2l-.9.9a2.3 2.3 0 0 1-3.3-3.3l.9-.9" ],
      nodes: [ { circle: [ 4.5, 8, 1.8 ] }, { circle: [ 11.5, 4.2, 1.8 ] }, { circle: [ 11.5, 11.8, 1.8 ] },
               "M6.1 7.1 9.9 5.1M6.1 8.9 9.9 10.9" ],
      mail: [ { rect: [ 2.5, 3.75, 11, 8.5, 1.5 ] }, "M3 4.75 8 8.5l5-3.75" ],
      sparkle: "M8 2.5C8.5 5.8 10.2 7.5 13.5 8 10.2 8.5 8.5 10.2 8 13.5 7.5 10.2 5.8 8.5 2.5 8 5.8 7.5 7.5 5.8 8 2.5Z",
      home: [ "M2.8 7.3 8 3l5.2 4.3V13H2.8Z", "M6.5 13v-3h3v3" ],
      mail_square: [ "M2.5 4h11v8h-11Z", "m2.5 4.4 5.5 4.3 5.5-4.3" ],
      bell: [ "M12.4 11.2H3.6l.9-1.6V7.3a3.5 3.5 0 0 1 7 0v2.3Z", "M6.6 13.2a1.5 1.5 0 0 0 2.8 0" ],
      funnel: [ "M2.5 3h11L9.6 8.2v4.6L6.4 14V8.2Z" ],
      rank: [ "M2.75 13.25h10.5", "M4.5 13.25V8.75", "M8 13.25V3.5", "M11.5 13.25V6.25" ],
      flag: [ "M4.2 14V2.6", "M4.2 3h7.3l-1.7 2.5 1.7 2.5H4.2" ],
      clock: [ "M13.6 8a5.6 5.6 0 1 1-11.2 0 5.6 5.6 0 1 1 11.2 0", "M8 4.8V8l2.2 1.6" ],
      switch: [ "M5.5 4.5h5a3.5 3.5 0 0 1 0 7h-5a3.5 3.5 0 0 1 0-7Z", "M12.5 8a2 2 0 1 1-4 0 2 2 0 1 1 4 0" ],
      sliders: [ "M2.5 4.5h6.6M11.9 4.5h1.6", "M11.9 4.5a1.4 1.4 0 1 1-2.8 0 1.4 1.4 0 1 1 2.8 0",
                 "M2.5 8h1.6M6.9 8h6.6", "M6.9 8a1.4 1.4 0 1 1-2.8 0 1.4 1.4 0 1 1 2.8 0",
                 "M2.5 11.5h5.1M10.4 11.5h3.1", "M10.4 11.5a1.4 1.4 0 1 1-2.8 0 1.4 1.4 0 1 1 2.8 0" ]
    }.freeze

    STROKE = {
      fill: "none", stroke: "currentColor",
      "stroke-width": "1.5", "stroke-linecap": "round", "stroke-linejoin": "round"
    }.freeze

    BODIES = SHAPES.transform_values do |shapes|
      helpers = ActionController::Base.helpers
      nodes = Array(shapes).map do |shape|
        if !shape.is_a?(Hash)
          helpers.tag.path(nil, d: shape, **STROKE)
        elsif (circle = shape[:circle])
          helpers.tag.circle(nil, cx: circle[0], cy: circle[1], r: circle[2], **STROKE)
        else
          rect = shape.fetch(:rect)
          helpers.tag.rect(nil, x: rect[0], y: rect[1], width: rect[2], height: rect[3], rx: rect[4], **STROKE)
        end
      end
      helpers.safe_join(nodes).freeze
    end.freeze

    def initialize(name)
      @name = name
    end

    def body
      BODIES.fetch(name.to_sym)
    end

    private

    attr_reader :name
  end
end
