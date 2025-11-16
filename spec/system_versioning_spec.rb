require "spec_helper"

RSpec.describe "system versioning" do
  before do
    conn.enable_extension(:btree_gist)

    stub_const("Version", Module.new do
      include SystemVersioning::Namespace
    end)

    model "ApplicationRecord" do
      self.abstract_class = true

      include SystemVersioning

      system_versioning
    end
  end

  after do
    drop_all_tables
    drop_all_versioning_hooks
    conn.disable_extension(:btree_gist)
  end

  it "raises an error when loading a constant that isn't an AR model" do
    model "Author", ApplicationRecord
    stub_const "Num", 1

    expect { Version::Author }.not_to raise_error
    expect { Version::Foo }.to raise_error(NameError, "uninitialized constant Version::Foo")
    expect { Version::File }.to raise_error(NameError, "File is not a descendent of ActiveRecord::Base")
    expect { Version::Kernel }.to raise_error(NameError, "Kernel is not a descendent of ActiveRecord::Base")
    expect { Version::Num }.to raise_error(NameError, "1 is not a descendent of ActiveRecord::Base")
  end

  it "raises an error when AR model is not system versioned" do
    model "Pie"

    expect { Version::Pie }.to raise_error(NameError, "Pie is not system versioned")
  end

  it "finds nested history models" do
    stub_const("Version", Module.new do
      include SystemVersioning::Namespace

      namespace "MyApp" do
        namespace "SystemB"
      end
    end)

    model "MyApp::SystemB::User", ApplicationRecord

    expect { Version::MyApp::SystemB::User }.not_to raise_error
    expect(Version::MyApp::SystemB::User).to be < MyApp::SystemB::User
    expect(Version::MyApp::SystemB::User).to be < SystemVersioning::SystemVersioned
  end

  it "finds subclasses" do
    model "Desert", ApplicationRecord
    model "CoolWhip", Desert

    expect(Version::Desert).to be < ActiveRecord::Base
    expect(Version::CoolWhip).to be < Desert
  end

  shared_examples "versions records" do
    it "versions records" do
      t1 = transaction_time { Author.create!(name: "Will") }
      t2 = transaction_time { Author.first.update!(name: "Bob") }
      t3 = transaction_time { Author.first.destroy }
      t4 = transaction_time { Author.create!(name: "Sam") }
      t5 = transaction_time do
        Author.last.update(name: "Bill")
        Author.last.update(name: "Egbert")
      end

      expect(Version::Author.count).to eq(4)

      expect(Version::Author.first)
        .to have_attributes(name: "Will", system_period: t1...t2)
      expect(Version::Author.second)
        .to have_attributes(name: "Bob", system_period: t2...t3)
      expect(Version::Author.third)
        .to have_attributes(name: "Sam", system_period: t4...t5)
      expect(Version::Author.fourth)
        .to have_attributes(name: "Egbert", system_period: t5...)
    end
  end

  context "source table has no history table" do
    before do
      conn.create_table :authors do |t|
        t.string :name
      end

      model "Author", ApplicationRecord
    end

    it "sets table_name to source table" do
      expect(Version::Author.table_name).to eq("authors")
    end

    it "sets primary_key to source table primary key" do
      expect(Version::Author.primary_key).to eq("id")
    end
  end

  context "source table primary key is 'id'" do
    before do
      conn.create_table :authors do |t|
        t.string :name
      end

      conn.create_table :authors_history, primary_key: [:id, :system_period] do |t|
        t.bigint :id, null: false
        t.string :name
        t.tstzrange :system_period, null: false
      end

      conn.create_versioning_hook(
        :authors,
        :authors_history,
        columns: [:id, :name]
      )

      model "Author", ApplicationRecord
    end

    include_examples "versions records"

    it "sets table_name to history table" do
      expect(Version::Author.table_name).to eq("authors_history")
    end

    it "sets primary_key to source table primary key" do
      expect(Version::Author.primary_key).to eq(%w[id system_period])
    end
  end

  context "source table primary key is (id, author_number)" do
    before do
      conn.create_table :authors, primary_key: [:id, :author_number] do |t|
        t.bigserial :id, null: false
        t.bigserial :author_number, null: false
        t.string :name
      end

      conn.create_table :authors_history, primary_key: [:id, :author_number, :system_period] do |t|
        t.bigint :id, null: false
        t.bigint :author_number, null: false
        t.string :name
        t.tstzrange :system_period, null: false
      end

      conn.create_versioning_hook(
        :authors,
        :authors_history,
        columns: [:id, :name, :author_number],
        primary_key: [:id, :author_number]
      )

      model "Author", ApplicationRecord
    end

    it "sets primary_key to source table primary key" do
      expect(Version::Author.primary_key).to eq(%w[id author_number system_period])
    end

    include_examples "versions records"
  end
end
