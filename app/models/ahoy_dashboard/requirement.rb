module AhoyDashboard
  class Requirement
    Blocker = Data.define(:reason, :fix, :state, :commands) do
      def initialize(reason:, fix: nil, state: :blocked, commands: [])
        super
      end

      def not_installed?
        state == :not_installed
      end
    end

    attr_reader :reason, :fix, :state, :commands

    class << self
      def first_blocker(requirements)
        requirements.find { |requirement| !requirement.met? }&.blocker
      end
    end

    def initialize(ok:, reason:, fix: nil, state: :blocked, commands: [])
      @ok = ok
      @reason = reason
      @fix = fix
      @state = state
      @commands = commands
      freeze
    end

    def met?
      @ok.call
    end

    def blocker
      Blocker.new(reason: resolve(reason), fix: resolve(fix), state: state, commands: commands)
    end

    private

    def resolve(value)
      value.respond_to?(:call) ? value.call : value
    end
  end
end
