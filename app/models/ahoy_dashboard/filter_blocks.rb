module AhoyDashboard
  class FilterBlocks
    include Enumerable

    BLOCK = "block".freeze
    BLOCK_FORMAT = /\A\d{1,6}\z/

    attr_reader :to_a

    def self.from_params(params)
      from_entries(AhoyDashboard::Filters.entries(params))
    end

    def self.from_entries(entries)
      buckets = Array(entries).each_with_object({}) do |entry, found|
        next unless entry.respond_to?(:[])

        (found[block_of(entry)] ||= []) << entry
      end

      new(buckets.values.map { |members| AhoyDashboard::Filters.from_params(filters: members) })
    end

    def self.block_of(entry)
      raw = (entry[BLOCK] || entry[BLOCK.to_sym]).to_s.strip

      raw.match?(BLOCK_FORMAT) ? raw.to_i : 0
    end

    def initialize(blocks = [])
      @to_a = Array(blocks).select(&:any?).freeze
    end

    def each(&block)
      to_a.each(&block)
    end

    def size
      to_a.size
    end

    def empty?
      to_a.empty?
    end

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
