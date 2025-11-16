module ActiveRecord::Temporal
  module SystemVersioning
    module HistoryModelNamespace
      extend ActiveSupport::Concern

      class_methods do
        def const_missing(model_name)
          model = join(@root, model_name).constantize
        rescue NameError
          super
        else
          unless model.is_a?(Class) && model < ActiveRecord::Base
            raise NameError, "#{model} is not a descendent of ActiveRecord::Base"
          end

          history_model = Class.new(model) do
            include HistoryModel
          end

          namespace_name = name

          model.define_singleton_method(:history_model) do
            "#{namespace_name}::#{name}".constantize
          end

          const_set(model_name, history_model)
        end

        def namespace(name, &block)
          new_namespace = Module.new do
            include HistoryModelNamespace
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
