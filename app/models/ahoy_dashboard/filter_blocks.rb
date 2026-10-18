module AhoyDashboard
  class FilterBlocks
    include Enumerable

    BLOCK = "block".freeze

    attr_reader :to_a

    def self.from_params(params)
      from_entries(AhoyDashboard::Filters.entries(params))
    end

    def self.from_entries(entries)
      buckets = Array(entries).each_with_object({}) do |raw, found|
        entry = AhoyDashboard::FilterEntry.read(raw)
        next if entry.nil?

        (found[entry.block] ||= []) << raw
      end

      new(buckets.values.map { |members| AhoyDashboard::Filters.from_params(filters: members) })
    end

    def initialize(blocks = [])
      @to_a = Array(blocks).select(&:any?).freeze
    end

    delegate :each, :size, :empty?, to: :to_a

    def single?
      size == 1
    end

    def filters
      to_a.flat_map(&:to_a)
    end

    def sentence
      return to_a.first&.sentence.to_s if size <= 1

      to_a.map { |block| block.size > 1 ? "(#{block.sentence})" : block.sentence }.join(" or ")
    end

    def to_param
      return to_a.first&.to_param || [] if size <= 1

      to_a.each_with_index.flat_map do |block, position|
        block.to_param.map { |entry| entry.merge(BLOCK => position) }
      end
    end
  end
end
