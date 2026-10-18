module AhoyDashboard
  class Filters
    include Enumerable

    GROUP = "group".freeze

    attr_reader :groups, :to_a

    def self.from_params(params)
      buckets = {}

      entries(params).reduce(new) do |filters, raw|
        entry = FilterEntry.read(raw)
        filter = build(entry)
        next filters if filter.nil?

        key = entry.group
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

    def self.build(entry)
      dimension = entry && entry.dimension
      return nil if dimension.nil? || entry.value.blank?

      Filter.new(dimension: dimension, operator: entry.operator || Filter::DEFAULT_OPERATOR, value: entry.value)
    end

    def self.readable_entry?(raw)
      entry = FilterEntry.read(raw)
      return false if entry.nil?

      entry.dimension.present? && Filter::OPERATORS.key?(entry.operator.to_s) && entry.value.present? &&
        entry.group_ok?
    end

    private_class_method :build

    def initialize(items = [])
      groups = Array(items).map { |item| item.is_a?(FilterGroup) ? item : FilterGroup.new([ item ]) }
      @groups = groups.reject(&:empty?).uniq(&:to_param).freeze
      @to_a = @groups.flat_map(&:to_a).freeze
    end

    delegate :each, :size, :empty?, to: :to_a
    alias_method :length, :size

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
