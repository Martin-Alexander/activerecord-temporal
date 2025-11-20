require "spec_helper"

RSpec.describe SystemVersioning::SchemaCreation do
  subject { described_class.new(ActiveRecord::Base.connection) }

  it "InsertHookDefinition returns the correct SQL" do
    object = SystemVersioning::InsertHookDefinition.new(
      :books,
      :books_history,
      [:id, :title, :pages, :published_at],
      "0.99.0"
    )

    function_id = Digest::SHA256.hexdigest("books_insert").first(10)
    expected_function_name = "sys_ver_func_" + function_id
    expected_function_comment = JSON.generate(
      verb: :insert,
      source_table: :books,
      history_table: :books_history,
      columns: %i[id title pages published_at],
      gem_version: "0.99.0"
    )

    sql = subject.accept(object)

    expect(sql.squish).to eq(<<~SQL.squish)
      CREATE FUNCTION #{expected_function_name}() RETURNS TRIGGER AS $$
        BEGIN
          INSERT INTO "books_history" ("id", "title", "pages", "published_at", system_period)
          VALUES (NEW."id", NEW."title", NEW."pages", NEW."published_at", tstzrange(NOW(), 'infinity'));

          RETURN NULL;
        END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER versioning_insert_trigger AFTER INSERT ON "books"
        FOR EACH ROW EXECUTE PROCEDURE #{expected_function_name}();

      COMMENT ON FUNCTION #{expected_function_name}() IS '#{expected_function_comment}';
    SQL
  end

  it "UpdateHookDefinition returns the correct SQL" do
    object = SystemVersioning::UpdateHookDefinition.new(
      :books,
      :books_history,
      [:id, :title, :pages],
      :id,
      "0.99.0"
    )

    sql = subject.accept(object)

    function_id = Digest::SHA256.hexdigest("books_update").first(10)
    expected_function_name = "sys_ver_func_" + function_id
    expected_function_comment = JSON.generate(
      verb: :update,
      source_table: :books,
      history_table: :books_history,
      columns: [:id, :title, :pages],
      primary_key: :id,
      gem_version: "0.99.0"
    )

    expect(sql.squish).to eq(<<~SQL.squish)
      CREATE FUNCTION #{expected_function_name}() RETURNS trigger AS $$
        BEGIN
          IF OLD IS NOT DISTINCT FROM NEW THEN
            RETURN NULL;
          END IF;

          UPDATE "books_history"
          SET system_period = tstzrange(lower(system_period), NOW())
          WHERE "id" = OLD."id" AND upper(system_period) = 'infinity' AND lower(system_period) < NOW();

          INSERT INTO "books_history" ("id", "title", "pages", system_period)
          VALUES (NEW."id", NEW."title", NEW."pages", tstzrange(NOW(), 'infinity'))
          ON CONFLICT ("id", system_period) DO UPDATE SET "id" = EXCLUDED."id", "title" = EXCLUDED."title", "pages" = EXCLUDED."pages";

          RETURN NULL;
        END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER versioning_update_trigger AFTER UPDATE ON "books"
        FOR EACH ROW EXECUTE PROCEDURE #{expected_function_name}();

      COMMENT ON FUNCTION #{expected_function_name}() IS '#{expected_function_comment}';
    SQL
  end

  it "UpdateHookDefinition returns correct SQL given composite primary key" do
    object = SystemVersioning::UpdateHookDefinition.new(
      :books,
      :books_history,
      [:id, :title, :pages],
      [:id, :title],
      "0.99.0"
    )

    sql = subject.accept(object)

    expect(sql).to include(<<~SQL)
      WHERE "id" = OLD."id" AND "title" = OLD."title" AND upper(system_period) = 'infinity' AND lower(system_period) < NOW();
    SQL

    expect(sql).to include(<<~SQL)
      ON CONFLICT ("id", "title", system_period) DO UPDATE SET "id" = EXCLUDED."id", "title" = EXCLUDED."title", "pages" = EXCLUDED."pages";
    SQL
  end

  it "DeleteHookDefinition returns the correct SQL" do
    object = SystemVersioning::DeleteHookDefinition.new(
      :books,
      :books_history,
      :id,
      "0.99.0"
    )

    function_id = Digest::SHA256.hexdigest("books_delete").first(10)
    expected_function_name = "sys_ver_func_" + function_id
    expected_function_comment = JSON.generate(
      verb: :delete,
      source_table: :books,
      history_table: :books_history,
      primary_key: :id,
      gem_version: "0.99.0"
    )

    sql = subject.accept(object)

    expect(sql.squish).to eq(<<~SQL.squish)
      CREATE FUNCTION #{expected_function_name}() RETURNS TRIGGER AS $$
        BEGIN
          DELETE FROM "books_history"
          WHERE "id" = OLD."id" AND system_period = tstzrange(NOW(), 'infinity');

          UPDATE "books_history"
          SET system_period = tstzrange(lower(system_period), NOW())
          WHERE "id" = OLD."id" AND upper(system_period) = 'infinity';

          RETURN NULL;
        END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER versioning_delete_trigger AFTER DELETE ON "books"
        FOR EACH ROW EXECUTE PROCEDURE #{expected_function_name}();

      COMMENT ON FUNCTION #{expected_function_name}() IS '#{expected_function_comment}';
    SQL
  end

  it "DeleteHookDefinition returns the correct SQL given composite primary key" do
    object = SystemVersioning::DeleteHookDefinition.new(
      :books,
      :books_history,
      [:id, :title],
      "0.99.0"
    )

    sql = subject.accept(object)

    expect(sql).to include(<<~SQL)
      WHERE "id" = OLD."id" AND "title" = OLD."title" AND system_period = tstzrange(NOW(), 'infinity');
    SQL

    expect(sql).to include(<<~SQL)
      WHERE "id" = OLD."id" AND "title" = OLD."title" AND upper(system_period) = 'infinity';
    SQL
  end

  it "VersioningHookDefinition returns the correct SQL" do
    columns = [:id, :title, :pages, :published_at]
    source_pk = :id

    object = ActiveRecord::Temporal::SystemVersioning::VersioningHookDefinition.new(
      :books,
      :books_history,
      columns: columns,
      primary_key: source_pk,
      gem_version: "0.99.0"
    )

    sql = subject.accept(object)

    insert_hook_definition = SystemVersioning::InsertHookDefinition.new(
      :books,
      :books_history,
      columns,
      "0.99.0"
    )

    update_hook_definition = SystemVersioning::UpdateHookDefinition.new(
      :books,
      :books_history,
      columns,
      source_pk,
      "0.99.0"
    )

    delete_hook_definition = SystemVersioning::DeleteHookDefinition.new(
      :books,
      :books_history,
      source_pk,
      "0.99.0"
    )

    expect(sql).to eq(
      [
        subject.accept(insert_hook_definition),
        subject.accept(update_hook_definition),
        subject.accept(delete_hook_definition)
      ].join(" ")
    )
  end
end
