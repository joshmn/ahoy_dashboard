module AhoyDashboard
  # Writes. Callers pass a block of on(:event) handlers, evaluated in the
  # caller's own context, and .call hands back the events hash so a caller with
  # no block can still read what happened.
  class Command
    class Router
      attr_reader :events

      def initialize(caller_context)
        @caller_context = caller_context
        @handlers = {}
        @events = {}
      end

      def on(event, &handler)
        @handlers[event] = handler
      end

      def fire(event, *args)
        @events[event] = args.size == 1 ? args.first : args
        handler = @handlers[event]
        return unless handler

        if @caller_context
          @caller_context.instance_exec(*args, &handler)
        else
          handler.call(*args)
        end
      end
    end

    def self.call(*args, **kwargs, &block)
      instance = kwargs.empty? ? new(*args) : new(*args, **kwargs)
      caller_context = block ? eval("self", block.binding, __FILE__, __LINE__) : nil
      router = Router.new(caller_context)
      router.instance_eval(&block) if block
      instance.instance_variable_set(:@_router, router)
      instance.call
      router.events
    end

    private

    def broadcast(event, *args)
      @_router.fire(event, *args)
    end
  end
end
