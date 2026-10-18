module AhoyDashboard
  class FeatureState
    BADGE = "Not installed".freeze

    attr_reader :names

    def self.for(*names)
      new(names.flatten)
    end

    def initialize(names)
      @names = names.map(&:to_sym)
    end

    def features
      names.map { |name| Installation.fetch(name) }
    end

    def installed?
      Installation.any_installed?(names)
    end

    def label
      features.map(&:label).to_sentence(two_words_connector: " or ", last_word_connector: ", or ")
    end

    def title
      "Not installed yet"
    end

    def detail
      if features.one?
        "#{label} has no tables in this app's database. Run these from the app's folder, then reload this page."
      else
        "This needs #{label}, and none of them has tables in this app's database yet. " \
          "Install whichever you want, run the migration, then reload this page."
      end
    end

    def commands
      Installation.install_commands(names)
    end

    def terminal_line
      "#{label.downcase} is not installed. #{Schedule.install_steps(names)}"
    end

    def badge
      BADGE
    end
  end
end
