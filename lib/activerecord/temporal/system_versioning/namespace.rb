module ActiveRecord::Temporal
  module SystemVersioning
    module Namespace
      extend ActiveSupport::Concern

      class_methods do
        def const_missing(name)
          model = join(@root, name).constantize
        rescue NameError
          super
        else
          unless model.is_a?(Class) && model < ActiveRecord::Base
            raise NameError, "#{model} is not a descendent of ActiveRecord::Base"
          end

          unless model < SystemVersioning
            raise NameError, "#{model} is not system versioned"
          end

          version_model = Class.new(model) do
            include SystemVersioned
          end

          const_set(name, version_model)
        end

        def namespace(name, &block)
          new_namespace = Module.new do
            include Namespace
          end

          const_set(name, new_namespace)

          new_namespace.root(join(@root, name))

          new_namespace.instance_eval(&block) if block
        end

        def root(name)
          @root = name
        end

        def join(base, name)
          [base, name].compact.join("::")
        end
      end
    end
  end
end
