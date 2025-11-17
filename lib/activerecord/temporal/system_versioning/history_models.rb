module ActiveRecord::Temporal
  module SystemVersioning
    module HistoryModels
      class Error < StandardError; end

      extend ActiveSupport::Concern

      class_methods do
        delegate :at_time, :as_of, to: :history

        def history_model
          raise Error, "abstract classes cannot have a history model" if abstract_class?

          [history_model_namespace, name].join("::").constantize
        end

        def history
          ActiveRecord::Relation.create(history_model)
        end

        private

        def history_model_namespace
          History
        end
      end
    end
  end
end
