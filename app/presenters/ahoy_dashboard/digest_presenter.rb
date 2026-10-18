module AhoyDashboard
  class DigestPresenter
    attr_reader :result, :host

    def initialize(result, host:)
      @result = result
      @host = host
    end

    def empty?
      result.empty?
    end

    def period
      result.window.period
    end

    def cadence
      period.to_s.capitalize
    end

    def period_heading
      case period
      when :daily then day(window.starts_on, weekday: true)
      when :weekly then "#{day(window.starts_on, weekday: true)} to #{day(window.ends_on, weekday: true)}"
      when :monthly then window.starts_on.strftime("%B %Y")
      end
    end

    def footer
      "You get this #{period} because #{noun} emails are on for #{host}."
    end

    private

    def noun
      raise NotImplementedError
    end

    def window
      result.window
    end

    def day(date, weekday: false)
      date.strftime(weekday ? "%a, %b %-d" : "%b %-d")
    end

    def count(number, word)
      AhoyDashboard::Counted.call(number, noun: word)
    end
  end
end
