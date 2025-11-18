module ActiveRecordTemporalTests
  class TestConnectionAdapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    PlPgsqlFunction = Struct.new(:name, :body)

    class TableWrapper
      delegate :inspect, :to_s, to: :table_name

      attr_reader :conn, :table_name

      def initialize(conn, table_name)
        @conn = conn
        @table_name = table_name
      end

      def respond_to_missing?(method_name, ...)
        table_method?(method_name)
      end

      def method_missing(method_name, *args, **kwargs, &block)
        super unless table_method?(method_name)

        conn.send(method_name, *([table_name] + args), **kwargs, &block)
      end

      private

      def table_method?(method_name)
        conn.respond_to?(method_name) &&
          conn.method(method_name).parameters.dig(0, 1) == :table_name
      end
    end

    def table(table_name)
      TableWrapper.new(self, table_name) if table_exists?(table_name)
    end

    def function_exists?(name)
      result = execute(<<~SQL)
        SELECT 1 as exists
        FROM pg_proc
        WHERE proname = '#{name}'
      SQL

      result.count > 0
    end

    def trigger_exists?(table_name, name)
      result = execute(<<~SQL)
        SELECT 1 as exists
        FROM pg_trigger t 
        WHERE t.tgname = '#{name}'
          AND t.tgrelid = '#{table_name}'::regclass::oid
        LIMIT 1
      SQL

      result.count > 0
    end

    def triggers(table_name)
      result = execute(<<~SQL)
        SELECT tgname
        FROM pg_trigger t 
        WHERE t.tgrelid = '#{table_name}'::regclass::oid
      SQL

      result.map { _1["tgname"] }
    end

    def plpgsql_functions
      rows = execute(<<~SQL.squish)
        SELECT p.proname AS function_name,
          pg_get_functiondef(p.oid) AS function_definition
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE p.prolang = (SELECT oid FROM pg_language WHERE lanname = 'plpgsql')
            AND n.nspname NOT IN ('pg_catalog', 'information_schema');
      SQL

      rows.map { |row| PlPgsqlFunction.new(*row.values) }
    end
  end
end
