require "active_support/core_ext/hash/deep_transform_values"

module ActiveRecord::Temporal
  module SystemVersioning
    class SchemaCreation
      def initialize(conn)
        @conn = conn
      end

      def accept(o)
        m = "visit_#{o.class.name.split("::").last}"
        send m, o
      end

      delegate :quote_table_name, :quote_column_name, :quote_string, :versioning_function_name, to: :@conn, private: true

      private

      def visit_VersioningHookDefinition(o)
        [o.insert_hook, o.update_hook, o.delete_hook].map { |t| accept(t) }.join(" ")
      end

      def visit_InsertHookDefinition(o)
        column_names = o.columns.map { |c| quote_column_name(c) }
        fields = column_names.join(", ")
        values = column_names.map { |c| "NEW.#{c}" }.join(", ")
        function_name = versioning_function_name(o.source_table, :insert)

        metadata = {
          verb: :insert,
          source_table: o.source_table,
          history_table: o.history_table,
          columns: o.columns,
          gem_version: o.gem_version
        }

        <<~SQL
          CREATE FUNCTION #{function_name}() RETURNS TRIGGER AS $$
            BEGIN
              INSERT INTO #{quote_table_name(o.history_table)} (#{fields}, system_period)
              VALUES (#{values}, tstzrange(NOW(), 'infinity'));

              RETURN NULL;
            END;
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER versioning_insert_trigger AFTER INSERT ON #{quote_table_name(o.source_table)}
            FOR EACH ROW EXECUTE PROCEDURE #{function_name}();

          #{create_metadata_comment(function_name, metadata)}
        SQL
      end

      def visit_UpdateHookDefinition(o)
        column_names = o.columns.map { |c| quote_column_name(c) }
        primary_key_quoted = Array(o.primary_key).map { |c| quote_column_name(c) }
        fields = column_names.join(", ")
        values = column_names.map { |c| "NEW.#{c}" }.join(", ")
        update_pk_predicates = primary_key_quoted.map { |c| "#{c} = OLD.#{c}" }.join(" AND ")
        on_conflict_constraint = (primary_key_quoted + [:system_period]).join(", ")
        on_conflict_sets = column_names.map { |c| "#{c} = EXCLUDED.#{c}" }.join(", ")
        function_name = versioning_function_name(o.source_table, :update)
        metadata = {
          verb: :update,
          source_table: o.source_table,
          history_table: o.history_table,
          columns: o.columns,
          primary_key: o.primary_key,
          gem_version: o.gem_version
        }

        <<~SQL
          CREATE FUNCTION #{function_name}() RETURNS trigger AS $$
            BEGIN
              IF OLD IS NOT DISTINCT FROM NEW THEN
                RETURN NULL;
              END IF;

              UPDATE #{quote_table_name(o.history_table)}
              SET system_period = tstzrange(lower(system_period), NOW())
              WHERE #{update_pk_predicates} AND upper(system_period) = 'infinity' AND lower(system_period) < NOW();

              INSERT INTO #{quote_table_name(o.history_table)} (#{fields}, system_period)
              VALUES (#{values}, tstzrange(NOW(), 'infinity'))
              ON CONFLICT (#{on_conflict_constraint}) DO UPDATE SET #{on_conflict_sets};

              RETURN NULL;
            END;
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER versioning_update_trigger AFTER UPDATE ON #{quote_table_name(o.source_table)}
            FOR EACH ROW EXECUTE PROCEDURE #{function_name}();

          #{create_metadata_comment(function_name, metadata)}
        SQL
      end

      def visit_DeleteHookDefinition(o)
        primary_key_quoted = Array(o.primary_key).map { |c| quote_column_name(c) }
        function_name = versioning_function_name(o.source_table, :delete)
        pk_predicates = primary_key_quoted.map { |c| "#{c} = OLD.#{c}" }.join(" AND ")
        metadata = {
          verb: :delete,
          source_table: o.source_table,
          history_table: o.history_table,
          primary_key: o.primary_key,
          gem_version: o.gem_version
        }

        <<~SQL
          CREATE FUNCTION #{function_name}() RETURNS TRIGGER AS $$
            BEGIN
              DELETE FROM #{quote_table_name(o.history_table)}
              WHERE #{pk_predicates} AND system_period = tstzrange(NOW(), 'infinity');

              UPDATE #{quote_table_name(o.history_table)}
              SET system_period = tstzrange(lower(system_period), NOW())
              WHERE #{pk_predicates} AND upper(system_period) = 'infinity';

              RETURN NULL;
            END;
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER versioning_delete_trigger AFTER DELETE ON #{quote_table_name(o.source_table)}
            FOR EACH ROW EXECUTE PROCEDURE #{function_name}();

          #{create_metadata_comment(function_name, metadata)}
        SQL
      end

      private

      def create_metadata_comment(function_name, metadata)
        quoted_metadata = metadata.deep_transform_values do |v|
          if v.is_a?(Array)
            v.map { quote_string(_1.to_s) }
          else
            quote_string(v.to_s)
          end
        end

        json = JSON.generate(quoted_metadata)

        <<~SQL
          COMMENT ON FUNCTION #{function_name}() IS '#{json}';
        SQL
      end
    end
  end
end
