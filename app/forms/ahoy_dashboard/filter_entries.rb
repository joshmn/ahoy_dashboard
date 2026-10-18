module AhoyDashboard
  module FilterEntries
    extend ActiveSupport::Concern

    FIELDS = %i[dimension operator value group block].freeze
    ROW_FIELDS = [ :dimension, :operator, :block, :values_text, { values: [], entries: FIELDS } ].freeze
    PERMITTED = { filters: FIELDS, rows: ROW_FIELDS }.freeze
    SET_SLOT = /\Aset:(\d{1,6})\z/
    SHOWN = 3

    Row = Data.define(:key, :dimension, :operator, :values, :members, :block) do
      def initialize(key:, dimension:, operator:, values:, members:, block: 0)
        super
      end

      def mixed?
        members.any?
      end

      def negative?
        AhoyDashboard::Filter::NEGATIVE_OPERATORS.include?(operator)
      end

      def operator_options
        AhoyDashboard::Filter.operator_options
      end

      def found
        AhoyDashboard::Dimension.find_by_key(dimension)
      end

      def label
        found&.filter_label || dimension
      end

      def negative_or?
        mixed? && members.count { |member| AhoyDashboard::Filter::NEGATIVE_OPERATORS.include?(member["operator"]) } > 1
      end

      def summary
        members.map do |member|
          name = AhoyDashboard::Dimension.find_by_key(member["dimension"])&.filter_label || member["dimension"]
          "#{name} #{AhoyDashboard::Filter::OPERATORS.fetch(member['operator'], member['operator'])} #{member['value']}"
        end.join(" or ")
      end

      def to_members
        return members if mixed?

        values.map { |value| { "dimension" => dimension, "operator" => operator, "value" => value } }
      end

      def alternatives?
        mixed? || !negative?
      end

      def shown
        values.first(SHOWN)
      end

      def hidden_count
        [ values.size - SHOWN, 0 ].max
      end

      def values_text
        values.join("\n")
      end
    end

    included do
      attribute :rows
      attribute :filters

      validate :every_filter_is_readable
    end

    def entries
      rows.nil? ? filter_entries : entries_from(filter_rows)
    end

    def to_filters
      AhoyDashboard::Filters.from_params(filters: entries)
    end

    def filter_rows
      rows.nil? ? rows_from_entries(filter_entries) : rows_from_param
    end

    def blocks?
      false
    end

    def filter_blocks
      filter_rows.group_by(&:block).values
    end

    def to_blocks
      AhoyDashboard::FilterBlocks.from_entries(entries)
    end

    def without_slot(slot)
      current = filter_rows
      set = slot.to_s[SET_SLOT, 1]
      remaining =
        if set
          current.reject { |row| row.block == set.to_i }
        else
          current.reject { |row| row.key == slot.to_s }
        end
      return self if remaining.size == current.size

      self.filters = entries_from(remaining)
      self.rows = nil
      self
    end

    private

    def entries_from(rows)
      group = -1
      blocks = rows.map(&:block).uniq

      rows.flat_map do |row|
        members = row.to_members.map { |member| member.except("group", "block") }
        members = members.map { |member| member.merge("block" => blocks.index(row.block)) } if blocks?
        next members unless row.alternatives? && members.size > 1

        group += 1
        members.map { |member| member.merge("group" => group) }
      end
    end

    def rows_from_entries(entries)
      by_block = entries.group_by { |entry| blocks? ? entry.fetch("block", 0) : 0 }
      by_block.values.each_with_index.flat_map do |members, number|
        rows_from_block(members, number)
      end.each_with_index.map { |row, index| row.with(key: index.to_s) }
    end

    def rows_from_block(entries, number)
      entry_blocks(entries).each_with_object([]) do |block, found|
        first = block.first
        previous = found.last

        if block.one? && previous && !previous.mixed? && previous.negative? &&
           previous.dimension == first["dimension"] && previous.operator == first["operator"]
          found[-1] = previous.with(values: (previous.values + [ first["value"] ]).uniq)
        elsif block.one? || (uniform?(block) && !AhoyDashboard::Filter::NEGATIVE_OPERATORS.include?(first["operator"]))
          found << Row.new(key: found.size.to_s, dimension: first["dimension"], operator: first["operator"],
                           values: block.map { |entry| entry["value"] }.uniq, members: [], block: number)
        else
          found << Row.new(key: found.size.to_s, dimension: first["dimension"], operator: first["operator"],
                           values: [], members: block.map { |entry| entry.except("group", "block") }, block: number)
        end
      end
    end

    def rows_from_param
      pairs(rows).map do |key, raw|
        entry = AhoyDashboard::FilterEntry.read(raw)
        next if entry.nil?

        block = blocks? ? entry.block : 0
        members = list(entry.field(:entries)).map { |member| filter_row(member)&.except("group", "block") }.select { |value| value }
        next row_of(key, members).with(block: block) if members.any?

        values = typed_values(entry)
        next if values.empty?

        Row.new(key: key.to_s, dimension: entry.dimension_key.strip, operator: operator_of(entry),
                values: values, members: [], block: block)
      end.select { |value| value }
    end

    def typed_values(entry)
      text = entry.field(:values_text)
      source = text.nil? ? list(entry.field(:values)) : text.to_s.split(/\r?\n/)

      source.map { |value| value.to_s.strip }.reject(&:blank?).uniq
    end

    def row_of(key, members)
      first = members.first
      return Row.new(key: key.to_s, dimension: first["dimension"], operator: first["operator"],
                     values: [ first["value"] ], members: []) if members.one?

      Row.new(key: key.to_s, dimension: first["dimension"], operator: first["operator"], values: [], members: members)
    end

    def entry_blocks(entries)
      entries.each_with_index.each_with_object({}) do |(entry, index), found|
        key = entry.key?("group") ? "group-#{entry['group']}" : "row-#{index}"
        (found[key] ||= []) << entry
      end.values
    end

    def uniform?(block)
      block.map { |entry| [ entry["dimension"], entry["operator"] ] }.uniq.one?
    end

    def filter_entries
      raw_entries.map { |entry| filter_row(entry) }.select { |value| value }
    end

    def pairs(raw)
      return raw.each_pair.to_a if raw.respond_to?(:each_pair)

      Array(raw).each_with_index.map { |row, index| [ index.to_s, row ] }
    end

    def list(raw)
      return [] if raw.nil?
      return raw.each_pair.map(&:last) if raw.respond_to?(:each_pair)

      Array(raw)
    end

    def raw_entries
      AhoyDashboard::Filters.entries(filters: filters)
    end

    def filter_row(raw)
      entry = AhoyDashboard::FilterEntry.read(raw)
      return nil if entry.nil?

      value = entry.value.strip
      return nil if value.blank?

      row = { "dimension" => entry.dimension_key.strip, "operator" => operator_of(entry), "value" => value }
      group = entry.group
      row["group"] = group if group
      row["block"] = entry.block if blocks?
      row
    end

    def operator_of(entry)
      entry.field(:operator).to_s.strip.presence || AhoyDashboard::Filter::DEFAULT_OPERATOR
    end

    def every_filter_is_readable
      return if entries.none?
      return if entries.all? { |entry| AhoyDashboard::Filters.readable_entry?(entry) }

      errors.add(:filters, "name a property or a match this dashboard does not have")
    end
  end
end
