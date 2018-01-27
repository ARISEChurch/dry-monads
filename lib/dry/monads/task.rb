require 'concurrent/promise'

require 'dry/monads/curry'

module Dry
  module Monads
    class Task
      class Promise < Concurrent::Promise
        public :on_fulfill, :on_reject
      end
      private_constant :Promise

      class << self
        def new(promise = nil, &block)
          if promise
            super(promise, &block)
          else
            super(Promise.execute(&block))
          end
        end

        def [](executor, &block)
          new(Promise.execute(executor: executor, &block))
        end

        def pure(value)
          new(Promise.fulfill(value))
        end
      end

      attr_reader :promise
      protected :promise

      def initialize(promise)
        @promise = promise
      end

      def value!
        promise.wait

        if promise.fulfilled?
          promise.value
        else
          raise UnwrapError.new(self)
        end
      end

      def fmap(&block)
        self.class.new(promise.then(&block))
      end

      def bind(&block)
        self.class.new(promise.flat_map { |value| block.(value).promise })
      end

      def to_result
        promise.wait

        if promise.fulfilled?
          Result::Success.new(promise.value)
        else
          Result::Failure.new(promise.reason)
        end
      end

      def to_maybe
        Maybe.coerce(promise.wait.value)
      end

      def to_s
        state, internal = case promise.state
                          when :fulfilled
                            ['resolved', " value=#{ value!.inspect }"]
                          when :rejected
                            ['rejected', " error=#{ promise.reason.inspect }"]
                          else
                            'pending'
                          end

        "Task(state=#{ state }#{ internal })"
      end
      alias_method :inspect, :to_s

      def or_fmap(&block)
        self.class.new(promise.rescue(&block))
      end

      def or(&block)
        child = Promise.new(
          parent: promise,
          executor: Concurrent::ImmediateExecutor.new
        )

        promise.on_error do |v|
          begin
            inner = block.(v).promise
            inner.execute
            inner.on_success { |r| child.on_fulfill(r) }
            inner.on_error { |e| child.on_reject(e) }
          rescue => e
            child.on_reject(e)
          end
        end
        promise.on_success  { |v| child.on_fulfill(v) }

        self.class.new(child)
      end

      def value_or(&block)
        promise.rescue(&block).wait.value
      end

      def wait(timeout = nil)
        promise.wait(timeout)
        self
      end

      def ==(other)
        return true if equal?(other)
        return false unless self.class == other.class
        compare_promises(promise, other.promise) { |x, y| x == y }
      end

      def eql?(other)
        return true if equal?(other)
        return false unless self.class == other.class
        compare_promises(promise, other.promise) { |x, y| x.eql?(y) }
      end

      def complete?
        promise.complete?
      end

      def monad
        Task
      end

      def apply(arg)
        bind do |callable|
          arg.fmap { |v| curry(callable).(v) }
        end
      end

      private

      def curry(value)
        if defined?(@curried)
          if @curried[0].equal?(value)
            @curried[1]
          else
            Curry.(value)
          end
        else
          @curried = [value, Curry.(value)]
          @curried[1]
        end
      end

      def compare_promises(x, y)
        x.equal?(y) ||
          x.fulfilled? && y.fulfilled? && yield(x.value, y.value) ||
          x.rejected? && y.rejected? && yield(x.reason, y.reason)
      end

      module Mixin
        Task = Dry::Monads::Task

        def self.[](executor)
          Module.new do
            include Mixin

            define_method(:Task) do |&block|
              Task[executor, &block]
            end
          end
        end

        def Task(&block)
          Task.new(&block)
        end
      end
    end
  end
end
