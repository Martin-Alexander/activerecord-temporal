module ActiveRecord::Temporal
  module SystemVersioning
    module SchemaStatements
      def create_versioning_hook(source_table, history_table, **options)
        options.assert_valid_keys(:columns, :primary_key)

        column_names = if (columns = options.fetch(:columns)) == :all
          columns(source_table).map(&:name)
        else
          Array(columns).map(&:to_s)
        end

        primary_key = options.fetch(:primary_key, :id)

        primary_key = if primary_key.is_a?(Array) && primary_key.length == 1
          primary_key.first
        else
          primary_key
        end

        ensure_table_exists!(source_table)
        ensure_table_exists!(history_table)
        ensure_columns_match!(source_table, history_table, column_names)
        ensure_columns_exists!(source_table, Array(primary_key))

        schema_creation = SchemaCreation.new(self)

        hook_definition = VersioningHookDefinition.new(
          source_table,
          history_table,
          columns: column_names,
          primary_key: primary_key
        )

        execute schema_creation.accept(hook_definition)
      end

      def drop_versioning_hook(source_table, history_table, **options)
        options.assert_valid_keys(:columns, :primary_key, :if_exists)

        %i[insert update delete].each do |verb|
          function_name = versioning_function_name(source_table, verb)

          sql = "DROP FUNCTION"
          sql << " IF EXISTS" if options[:if_exists]
          sql << " #{function_name}() CASCADE"

          execute sql
        end
      end

      def versioning_hook(source_table)
        update_function_name = versioning_function_name(source_table, :update)

        row = execute(<<~SQL.squish).first
          SELECT
            pg_proc.proname as function_name,
            obj_description(pg_proc.oid, 'pg_proc') as comment
          FROM pg_proc
          JOIN pg_namespace ON pg_proc.pronamespace = pg_namespace.oid
          WHERE pg_namespace.nspname NOT IN ('pg_catalog', 'information_schema')
            AND pg_proc.proname = '#{update_function_name}'
        SQL

        return unless row

        metadata = JSON.parse(row["comment"])

        VersioningHookDefinition.new(
          metadata["source_table"],
          metadata["history_table"],
          columns: metadata["columns"],
          primary_key: metadata["primary_key"]
        )
      end

      def change_versioning_hook(source_table, history_table, options)
        options.assert_valid_keys(:add_columns, :remove_columns)

        add_columns = (options[:add_columns] || []).map(&:to_s)
        remove_columns = (options[:remove_columns] || []).map(&:to_s)

        ensure_table_exists!(source_table)
        ensure_table_exists!(history_table)
        ensure_columns_match!(source_table, history_table, add_columns)

        hook_definition = versioning_hook(source_table)

        ensure_hook_has_columns!(hook_definition, remove_columns)

        drop_versioning_hook(source_table, history_table)

        new_columns = hook_definition.columns + add_columns - remove_columns

        create_versioning_hook source_table,
          history_table,
          columns: new_columns,
          primary_key: hook_definition.primary_key
      end

      def history_table(source_table)
        hook_definition = versioning_hook(source_table)

        hook_definition&.history_table
      end

      def versioning_function_name(source_table, verb)
        identifier = "#{source_table}_#{verb}"
        hashed_identifier = Digest::SHA256.hexdigest(identifier).first(10)

        "sys_ver_func_#{hashed_identifier}"
      end

      private

      def validate_create_versioning_hook_options!(options)
      end

      def ensure_table_exists!(table_name)
        return if table_exists?(table_name)

        raise ArgumentError, "table '#{table_name}' does not exist"
      end

      def ensure_columns_match!(source_table, history_table, column_names)
        ensure_columns_exists!(source_table, column_names)
        ensure_columns_exists!(history_table, column_names)

        column_names.each do |column|
          source_column = columns(source_table).find { _1.name == column }
          history_column = columns(history_table).find { _1.name == column }

          if source_column.type != history_column.type
            raise ArgumentError, "table '#{history_table}' does not have column '#{column}' of type '#{source_column.type}'"
          end
        end
      end

      def ensure_columns_exists!(table_name, column_names)
        column_names.each do |column|
          next if column_exists?(table_name, column)

          raise ArgumentError, "table '#{table_name}' does not have column '#{column}'"
        end
      end

      def ensure_hook_has_columns!(hook, column_names)
        column_names.each do |column_name|
          next if hook.columns.include?(column_name)

          raise ArgumentError, "versioning hook between '#{hook.source_table}' and '#{hook.history_table}' does not have column '#{column_name}'"
        end
      end
    end
  end
end
