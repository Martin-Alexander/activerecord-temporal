module ActiveRecord::Temporal
  module Patches
    # This is a copy of a fix from https://github.com/rails/rails/pull/56088 that
    # impacts this gem. I has been merged and backported to supported stable
    # versions of Active Record, but until those patches are released it's included
    # here.
    module JoinDependency
      def instantiate(result_set, strict_loading_value, &block)
        primary_key = Array(join_root.primary_key).map { |column| aliases.column_alias(join_root, column) }

        seen = Hash.new { |i, parent|
          i[parent] = Hash.new { |j, child_class|
            j[child_class] = {}
          }
        }.compare_by_identity

        model_cache = Hash.new { |h, klass| h[klass] = {} }
        parents = model_cache[join_root]

        column_aliases = aliases.column_aliases(join_root)
        column_names = []

        result_set.columns.each do |name|
          column_names << name unless /\At\d+_r\d+\z/.match?(name)
        end

        if column_names.empty?
          column_types = {}
        else
          column_types = result_set.column_types
          unless column_types.empty?
            attribute_types = join_root.attribute_types
            column_types = column_types.slice(*column_names).delete_if { |k, _| attribute_types.key?(k) }
          end
          column_aliases += column_names.map! { |name| Aliases::Column.new(name, name) }
        end

        message_bus = ActiveSupport::Notifications.instrumenter

        payload = {
          record_count: result_set.length,
          class_name: join_root.base_klass.name
        }

        message_bus.instrument("instantiation.active_record", payload) do
          result_set.each { |row_hash|
            parent_key = primary_key.empty? ? row_hash : row_hash.values_at(*primary_key)
            parent = parents[parent_key] ||= join_root.instantiate(row_hash, column_aliases, column_types, &block)
            construct(parent, join_root, row_hash, seen, model_cache, strict_loading_value)
          }
        end

        parents.values
      end
    end
  end
end
