module ActiveRecord::Temporal
  module Querying
    class Scoping
      class << self
        def at(time_or_time_coords, &block)
          if time_or_time_coords.is_a?(Hash)
            with_global_constraint(time_or_time_coords, &block)
          else
            without_global_constraints do
              with_universal_global_constraint_time(time_or_time_coords, &block)
            end
          end
        end

        def as_of(time_coords, &block)
          with_association_constraints(time_coords) do
            with_association_tags(time_coords, &block)
          end
        end

        private

        def with_association_constraints(time_coords, &block)
          original = ScopeRegistry.association_constraints
          ScopeRegistry.set_association_constraints(time_coords)

          block.call
        ensure
          ScopeRegistry.association_constraints = original
        end

        def with_association_tags(time_coords, &block)
          original = ScopeRegistry.association_tags
          ScopeRegistry.set_association_tags(time_coords)

          block.call
        ensure
          ScopeRegistry.association_tags = original
        end

        def with_global_constraint(value, &block)
          original = ScopeRegistry.global_constraints
          ScopeRegistry.set_global_constraints(value)

          block.call
        ensure
          ScopeRegistry.global_constraints = original
        end

        def without_global_constraints(&block)
          original = ScopeRegistry.global_constraints
          ScopeRegistry.global_constraints = {}

          block.call
        ensure
          ScopeRegistry.global_constraints = original
        end

        def with_universal_global_constraint_time(time, &block)
          original = ScopeRegistry.universal_global_constraint_time
          ScopeRegistry.universal_global_constraint_time = time

          block.call
        ensure
          ScopeRegistry.universal_global_constraint_time = original
        end
      end
    end
  end
end
