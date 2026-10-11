require "set"
require "yaml"

module AhoyDashboardComponentKit
  ROOT = AhoyDashboard::Engine.root
  BASELINE = Pathname(__dir__).join("component_kit_baseline.yml")

  RETIRED = %w[
    pri danger dim icon-btn txt-btn dash-why dash-unavailable
    field inp sel opt f-hint f-err f-grid f-actions form-card fc-hd
    seg seg-btn set-seg tm-seg chk
    set-notice set-notice--warn set-notice--error seo-notice
    toast-x tk
    b-ok b-err b-warn b-mut b-ev b-pg b-site
    ph ph-main ph-kicker ph-lede ph-actions ph-title ph-back
    p-hd p-tabs p-tab p-ft card-note
    t-head t-row t-num t-actions t-confirm tc-msg t-scroll t-min
    stats s-top s-lbl s-val s-delta sc-stat__label
    empty--fill empty--compact m-empty
    pop-item pop-g pi-l pi-r bs-menu pop-meta pop-item--segment set-more__danger tm-menu__button-label tm-menu__item-label
    m-panel m-hd m-ft m-x m-count m-dialog m-ft__acts m-sub ask-hd ask-x
    jr-trace seo-more seo-more--ruled seo-more__open seo-more__less seo-details set-details set-details__chev set-details__title set-pager
  ].to_set.freeze

  AMBIGUOUS = %w[pri danger dim field inp sel opt seg chk tk ph stats].to_set.freeze

  BOOTSTRAP = %w[
    btn btn-sm btn-lg btn-primary btn-secondary btn-link btn-outline-danger btn-close btn-group btn-check
    form-control form-select form-label form-text form-check form-check-input form-check-label form-switch
    is-invalid invalid-feedback input-group input-group-text
    badge alert alert-primary alert-warning alert-danger alert-success
    card card-header card-body card-footer card-title
    dropdown dropdown-menu dropdown-item dropdown-header dropdown-divider dropdown-toggle
    modal modal-dialog modal-content modal-header modal-body modal-footer modal-title
    nav nav-link nav-pills nav-tabs
    table table-responsive pagination page-item page-link
    toast toast-body list-group list-group-item progress progress-bar
  ].to_set.freeze

  COMPONENT_PATHS = %w[
    app/helpers/ahoy_dashboard/components_helper.rb
    app/helpers/ahoy_dashboard/components/
    app/views/ahoy_dashboard/components/
  ].freeze

  MAIL_PATHS = %w[
    app/views/ahoy_dashboard/alert_mailer/
    app/views/ahoy_dashboard/report_mailer/
    app/views/layouts/ahoy_dashboard/mailer
  ].freeze

  THEME_FILES = %w[
    assets/stylesheets/ahoy_dashboard.scss
    assets/stylesheets/ahoy_dashboard/_tokens.scss
  ].freeze

  RETIRED_GLOBS = %w[
    app/views/**/*.erb app/helpers/**/*.rb app/presenters/**/*.rb app/decorators/**/*.rb
    app/controllers/**/*.rb app/forms/**/*.rb app/commands/**/*.rb app/services/**/*.rb app/models/**/*.rb
    assets/javascript/**/*.js assets/stylesheets/**/*.scss
  ].freeze

  MARKUP_GLOBS = %w[
    app/views/**/*.erb app/helpers/**/*.rb app/presenters/**/*.rb app/decorators/**/*.rb
  ].freeze

  CLASS_KEYWORD = /\b(?:class|class_name|css):\s*|\bclass_names\(/

  KINDS = %w[retired bootstrap stylesheet].freeze

  module_function

  def counts(kind)
    case kind
    when "retired" then tally(RETIRED_GLOBS) { |path, text| retired_tokens(path, text) }
    when "bootstrap" then tally(MARKUP_GLOBS, skip: COMPONENT_PATHS + MAIL_PATHS) { |_path, text| bootstrap_tokens(text) }
    when "stylesheet" then tally(%w[assets/stylesheets/**/*.scss], skip: THEME_FILES) { |_path, text| literal_tokens(text) }
    end
  end

  def tally(globs, skip: [])
    globs.flat_map { |glob| Dir[ROOT.join(glob)] }.uniq.sort.each_with_object({}) do |path, result|
      relative = Pathname(path).relative_path_from(ROOT).to_s
      next if skip.any? { |prefix| relative.start_with?(prefix) }

      found = yield(relative, File.read(path)).group_by { |item| item }.transform_values(&:size)
      result[relative] = found.sort.to_h if found.any?
    end
  end

  def retired_tokens(path, text)
    case File.extname(path)
    when ".scss" then selector_tokens(strip_css_comments(text)).select { |token| RETIRED.include?(token) }
    when ".js" then script_tokens(text).select { |token| RETIRED.include?(token) }
    else
      literals = class_literals(text)
      class_positions = literals.keys.to_set
      code_literals(path, text).each { |position, value| literals[position] ||= value unless class_positions.include?(position) }
      literals.flat_map do |position, value|
        words(value).select do |token|
          RETIRED.include?(token) && (class_positions.include?(position) || !AMBIGUOUS.include?(token))
        end
      end
    end
  end

  def bootstrap_tokens(text)
    tokens = class_literals(text).values.flat_map { |value| words(value) }.select { |token| BOOTSTRAP.include?(token) }
    tokens + text.scan(/<table\b|\btag\.table\b/).map { "<table>" }
  end

  def literal_tokens(text)
    css = strip_css_comments(text)
    declarations = css.scan(/[\w-]+\s*:[^;{}]*;?/).join("\n")
    declarations.scan(/#\h{3,8}\b/).map { "hex colour" } +
      declarations.scan(/\brgba?\(/).map { "rgb colour" } +
      css.scan(/\bborder(?:-[a-z]+)*-radius\s*:(?!\s*var\()[^;{}]+/).map { "radius literal" }
  end

  def class_literals(text)
    literals = {}
    text.scan(/class="/) do
      start = Regexp.last_match.end(0) - 1
      attribute_literals(text, start).each { |position, value| literals[position] = value }
    end
    text.scan(CLASS_KEYWORD) do
      match = Regexp.last_match
      keyword_literals(text, match).each { |position, value| literals[position] ||= value }
    end
    literals
  end

  def attribute_literals(text, quote)
    found = {}
    plain = +""
    index = quote + 1
    while index < text.length
      if text[index, 2] == "<%"
        close = text.index("%>", index) || text.length
        quoted_strings(text[index + 2...close], offset: index + 2).each { |position, value| found[position] = value }
        index = close + 2
      elsif text[index] == '"' || text[index] == "\n"
        break
      else
        plain << text[index]
        index += 1
      end
    end
    found[quote] = plain
    found
  end

  def keyword_literals(text, match)
    found = {}
    wrapped = match[0].start_with?("class_names")
    depth = wrapped ? 1 : 0
    index = match.end(0)
    while index < text.length
      char = text[index]
      if char == '"' || char == "'"
        close = closing_quote(text, index)
        found[index] = text[index + 1...close]
        index = close + 1
        next
      end
      break if text[index, 2] == "%>"

      if "([{".include?(char)
        depth += 1
      elsif ")]}".include?(char)
        break if depth.zero?

        depth -= 1
        break if wrapped && depth.zero?
      elsif depth.zero? && (char == "," || char == "\n")
        break
      end
      index += 1
    end
    found
  end

  def code_literals(path, text)
    return quoted_strings(text) unless path.end_with?(".erb")

    found = {}
    text.scan(/<%(.*?)%>/m) do
      start = Regexp.last_match.begin(1)
      quoted_strings(Regexp.last_match(1), offset: start).each { |position, value| found[position] = value }
    end
    found
  end

  def quoted_strings(code, offset: 0)
    found = {}
    index = 0
    while (index = code.index(/["']/, index))
      close = closing_quote(code, index)
      found[offset + index] = code[index + 1...close]
      index = close + 1
    end
    found
  end

  def closing_quote(text, index)
    quote = text[index]
    cursor = index + 1
    cursor += text[cursor] == "\\" ? 2 : 1 while cursor < text.length && text[cursor] != quote && text[cursor] != "\n"
    cursor
  end

  def script_tokens(text)
    literals = text.scan(/(["'`])((?:\\.|(?!\1)[^\\])*)\1/m).map(&:last)
    literals.flat_map { |value| selector_tokens(value) } +
      text.scan(/classList\.(?:add|remove|toggle|contains)\(\s*["']([^"']+)["']/).flat_map { |(value)| words(value) } +
      class_literals(text).values.flat_map { |value| words(value) }
  end

  def selector_tokens(css)
    css.scan(/(?<!\d)\.([A-Za-z][\w-]*)/).flatten
  end

  def strip_css_comments(text)
    text.gsub(%r{/\*.*?\*/}m, "").gsub(%r{(?<!:)//[^\n]*}, "")
  end

  def words(value)
    value.gsub(/#\{[^}]*\}/, " ").scan(/[A-Za-z][\w-]*/)
  end

  def baseline
    BASELINE.exist? ? YAML.safe_load(BASELINE.read) : {}
  end

  def compare(kind)
    allowed = baseline.fetch(kind, {})
    current = counts(kind)
    grown = []
    stale = []
    (allowed.keys | current.keys).sort.each do |path|
      was = allowed.fetch(path, {})
      now = current.fetch(path, {})
      (was.keys | now.keys).sort.each do |token|
        before = was.fetch(token, 0)
        after = now.fetch(token, 0)
        grown << "#{path}: #{token} #{before} -> #{after}" if after > before
        stale << "#{path}: #{token} #{before} -> #{after}" if after < before
      end
    end
    [ grown, stale ]
  end

  def update_baseline!(mode)
    data = baseline
    KINDS.each do |kind|
      current = counts(kind)
      data[kind] =
        if mode == "create" || !data.key?(kind)
          current
        else
          lowered(data.fetch(kind), current)
        end
    end
    BASELINE.write(YAML.dump(data.sort.to_h))
  end

  def lowered(allowed, current)
    allowed.each_with_object({}) do |(path, tokens), result|
      kept = tokens.map do |token, count|
        now = current.dig(path, token).to_i
        [ token, [ count, now ].min ] if now.positive?
      end.compact
      result[path] = kept.to_h if kept.any?
    end
  end
end
