module ActiveRecord::Temporal
  module SystemVersioning
    class VersioningHookDefinition
      attr_accessor :source_table, :history_table, :columns, :primary_key, :gem_version

      def initialize(
        source_table,
        history_table,
        columns:,
        primary_key:,
        gem_version:
      )
        @source_table = source_table
        @history_table = history_table
        @columns = columns
        @primary_key = primary_key
        @gem_version = gem_version
      end

      def insert_hook
        InsertHookDefinition.new(@source_table, @history_table, @columns, @gem_version)
      end

      def update_hook
        UpdateHookDefinition.new(@source_table, @history_table, @columns, @primary_key, @gem_version)
      end

      def delete_hook
        DeleteHookDefinition.new(@source_table, @history_table, @primary_key, @gem_version)
      end
    end

    InsertHookDefinition = Struct.new(:source_table, :history_table, :columns, :gem_version)

    UpdateHookDefinition = Struct.new(:source_table, :history_table, :columns, :primary_key, :gem_version)

    DeleteHookDefinition = Struct.new(:source_table, :history_table, :primary_key, :gem_version)
  end
end
