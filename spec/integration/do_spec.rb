RSpec.describe(Dry::Monads::Do) do
  include Dry::Monads

  let(:klass) do
    spec = self

    Class.new do
      include Dry::Monads::Do.for(:call)
      include Dry::Monads
    end
  end

  let(:instance) { klass.new }

  context 'with Result' do
    context 'successful case' do
      before do
        klass.class_eval do
          def call
            m1 = Success(1)
            m2 = Success(2)

            one = yield m1
            two = yield m2

            Success(one + two)
          end
        end
      end

      it 'returns result of a statement' do
        expect(instance.call).to eql(Success(3))
      end
    end

    context 'first failure' do
      before do
        klass.class_eval do
          def call
            m1 = Failure(:no_one)
            m2 = Success(2)

            one = yield m1
            two = yield m2

            Success(one + two)
          end
        end
      end

      it 'returns failure' do
        expect(instance.call).to eql(Failure(:no_one))
      end
    end

    context 'second failure' do
      before do
        klass.class_eval do
          def call
            m1 = Success(1)
            m2 = Failure(:no_two)

            one = yield m1
            two = yield m2

            Success(one + two)
          end
        end
      end

      it 'returns failure' do
        expect(instance.call).to eql(Failure(:no_two))
      end
    end
  end
end