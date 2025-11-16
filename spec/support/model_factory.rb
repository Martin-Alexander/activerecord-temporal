module ActiveRecordTemporalTests
  module ModelFactory
    def model(name, super_class = ActiveRecord::Base, as_of: false, &block)
      klass = Class.new(super_class)

      stub_const(name, klass)

      if as_of
        klass.include ActiveRecord::Temporal::Querying
        klass.time_dimensions = :period
      end

      klass.class_eval(&block) if block

      klass
    end

    def system_versioned_model(name, super_class = ActiveRecord::Base, &block)
      klass = Class.new(super_class) do
        include ActiveRecord::Temporal::SystemVersioned

        instance_eval(&block) if block
      end

      stub_const(name, klass)
    end
  end
end
