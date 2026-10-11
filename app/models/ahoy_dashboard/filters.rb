module AhoyDashboard
  # An ordered, immutable set of filters. Everything that changes it hands back a
  # new one, so a link that adds a filter cannot mutate the view it was built from.
  class Filters
    include Enumerable

    GROUP = "group".freeze

    attr_reader :groups, :to_a

    # The "changed their mind" rule from #replacing is applied as the set is read,
    # not only where a row was clicked, because a filter modal can apply several
    # at once and the query string can carry anything: two "is" filters on one
    # dimension ask for rows holding two values at once, which is nothing, so the
    # last one wins. Any other operator ands, since "not /a" and "not /b" is a
    # question with an answer.
    def self.from_params(params)
      buckets = {}

      entries(params).reduce(new) do |filters, attrs|
        filter = build(attrs)
        next filters if filter.nil?

        key = group_key(attrs)
        if key.nil?
          next filters.add(filter) unless filter.operator == Filter::DEFAULT_OPERATOR

          next filters.replacing(filter.dimension.key, filter)
        end

        anchor = buckets[key]
        if anchor
          filters.adding_to_group(anchor, filter)
        else
          buckets[key] = filter
          filters.add(filter)
        end
      end
    end

    def self.grouped(groups)
      new(Array(groups).map { |group| group.is_a?(FilterGroup) ? group : FilterGroup.new(group) })
    end

    def self.entries(params)
      raw = params.respond_to?(:key?) ? (params[:filters] || params["filters"]) : nil

      case raw
      when Array then raw
      when Hash, ActionController::Parameters
        raw.key?(:dimension) || raw.key?("dimension") ? [ raw ] : raw.values
      else []
      end
    end

    def self.build(attrs)
      return nil unless attrs.respond_to?(:key?)

      dimension = Dimension.find_by_key(attrs[:dimension] || attrs["dimension"])
      return nil if dimension.nil?

      value = (attrs[:value] || attrs["value"]).to_s
      return nil if value.blank?

      Filter.new(dimension: dimension, operator: attrs[:operator] || attrs["operator"] || Filter::DEFAULT_OPERATOR,
                 value: value)
    end

    def self.group_key(attrs)
      raw = attrs[:group] || attrs[GROUP]
      text = raw.to_s.strip

      text.match?(/\A\d{1,6}\z/) ? text.to_i : nil
    end

    def self.readable_entry?(entry)
      return false unless entry.respond_to?(:[])

      raw_group = entry[GROUP]
      AhoyDashboard::Dimension.find_by_key(entry["dimension"]).present? &&
        AhoyDashboard::Filter::OPERATORS.key?(entry["operator"].to_s) &&
        entry["value"].to_s.present? &&
        (raw_group.nil? || raw_group.to_s.match?(/\A\d{1,6}\z/))
    end

    private_class_method :build, :group_key

    def initialize(items = [])
      groups = Array(items).map { |item| item.is_a?(FilterGroup) ? item : FilterGroup.new([ item ]) }
      @groups = groups.reject(&:empty?).uniq(&:to_param).freeze
      @to_a = @groups.flat_map(&:to_a).freeze
    end

    def each(&block)
      to_a.each(&block)
    end

    def size
      to_a.size
    end
    alias_method :length, :size

    def empty?
      to_a.empty?
    end

    def [](index)
      to_a[index]
    end

    def grouped?
      groups.any? { |group| !group.single? }
    end

    def add(filter)
      self.class.new(groups + [ FilterGroup.new([ filter ]) ])
    end

    def group_at(index)
      anchor = to_a[index.to_i]
      anchor && groups.find { |group| group.to_a.any? { |filter| filter.equal?(anchor) } }
    end

    def group_starts
      position = 0

      groups.map do |group|
        start = position
        position += group.size
        start
      end
    end

    # Clicking a second country when one is already filtered means the reader
    # changed their mind. Keeping both asks for rows that are in two countries
    # at once, which is nothing, and it is two clicks away from the drilldown.
    def replacing(dimension_key, filter)
      kept = groups.reject do |group|
        group.single? && group.to_a.first.dimension.key == dimension_key &&
          group.to_a.first.operator == Filter::DEFAULT_OPERATOR
      end

      self.class.new(kept + [ FilterGroup.new([ filter ]) ])
    end

    def without(index)
      target = to_a[index.to_i]
      return self if target.nil? || index.to_s !~ /\A-?\d+\z/ || index.to_i.negative?

      self.class.new(groups.map { |group| group.without(target) })
    end

    def without_dimension(key)
      self.class.new(groups.reject { |group| group.any? { |filter| filter.dimension.key == key } })
    end

    def pinned
      groups.select(&:single?).map { |group| group.to_a.first }.select { |filter| filter.operator == Filter::DEFAULT_OPERATOR }
    end

    def pinned_index(dimension_key, value)
      pin = pinned.find { |filter| filter.dimension.key == dimension_key && filter.value == value }
      pin && to_a.index { |filter| filter.equal?(pin) }
    end

    def sentence
      return groups.first&.label.to_s if groups.size <= 1

      groups.map { |group| group.single? ? group.label : "(#{group.label})" }.join(" and ")
    end

    def labels
      groups.map(&:label)
    end

    def to_param
      groups.each_with_index.flat_map do |group, position|
        group.to_a.map do |filter|
          group.single? ? filter.to_param : filter.to_param.merge(GROUP => position)
        end
      end
    end

    def adding_to_group(anchor, filter)
      return add(filter) unless groups.any? { |group| group.to_a.any? { |candidate| candidate.equal?(anchor) } }

      self.class.new(groups.map do |group|
        group.to_a.any? { |candidate| candidate.equal?(anchor) } ? group.add(filter) : group
      end)
    end
  end
end
