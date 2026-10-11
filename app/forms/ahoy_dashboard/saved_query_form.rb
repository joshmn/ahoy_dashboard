module AhoyDashboard
  class SavedQueryForm < AhoyDashboard::Form
    FIELDS = %i[name pinned].freeze
    QUESTION_FIELD = "saved_query[params]".freeze

    attribute :name, :string
    attribute :pinned, :boolean, default: false
    # The question itself, as the query string carries it. Not typed into the
    # form: it comes off whichever Explore was open when Save was pressed, so
    # the record and the URL cannot disagree.
    attribute :params, default: -> { {} }

    validates :name, presence: true
    validate :has_a_question

    def self.from_record(record)
      new(name: record.name, pinned: record.pinned, params: record.params)
    end

    def name
      super().to_s.strip.presence
    end

    def question
      AhoyDashboard::SavedQuery.clean(params)
    end

    def record_attributes
      { name: name, pinned: pinned, params: question }
    end

    def question_fields(prefix = QUESTION_FIELD)
      question.flat_map do |key, value|
        next [ [ "#{prefix}[#{key}]", value ] ] unless value.is_a?(Array)

        value.each_with_index.flat_map do |entry, index|
          entry.map { |field, part| [ "#{prefix}[#{key}][#{index}][#{field}]", part ] }
        end
      end
    end

    private

    def has_a_question
      return if question.present?

      errors.add(:params, "need a question to save, and this one is empty")
    end
  end
end
