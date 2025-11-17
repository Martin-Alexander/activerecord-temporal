module ActiveRecord::Temporal
  module Querying
    class AssociationScope
      class << self
        def build(block)
          scope = merge_scopes(block)

          def scope.temporal_scope? = true

          scope
        end

        private

        def merge_scopes(block)
          temporal_scope = build_temporal_scope

          if !block
            return ->(owner = nil) do
              instance_exec(owner, all, &temporal_scope)
            end
          end

          if block.arity != 0
            return ->(owner) do
              base = instance_exec(owner, &block)
              instance_exec(owner, base, &temporal_scope)
            end
          end

          ->(owner = nil) do
            base = instance_exec(&block)
            instance_exec(owner, base, &temporal_scope)
          end
        end

        def build_temporal_scope
          ->(owner, base) do
            registry_constraints = ScopeRegistry
              .association_constraints_for(time_dimensions)

            registry_time_tags = ScopeRegistry
              .association_tags_for(time_dimensions)

            owner_time_tags = owner&.time_tags_for(time_dimensions) || {}

            base
              .at_time(registry_constraints.merge(owner_time_tags))
              .time_tags(owner_time_tags.merge(registry_time_tags))
          end
        end
      end
    end
  end
end
