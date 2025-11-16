require "spec_helper"

RSpec.describe ActiveRecord::Temporal::SystemVersioning::HistoryModelNamespace do
  before do
    conn.enable_extension(:btree_gist)

    stub_const("History", Module.new do
      include SystemVersioning::HistoryModelNamespace
    end)
  end

  after do
    drop_all_tables
    drop_all_versioning_hooks
    conn.disable_extension(:btree_gist)
  end

  it "raises an error when loading a constant that isn't an AR model" do
    model "Author"
    stub_const "Num", 1

    expect { History::Author }.not_to raise_error
    expect { History::Foo }.to raise_error(NameError, "uninitialized constant History::Foo")
    expect { History::File }.to raise_error(NameError, "File is not a descendent of ActiveRecord::Base")
    expect { History::Kernel }.to raise_error(NameError, "Kernel is not a descendent of ActiveRecord::Base")
    expect { History::Num }.to raise_error(NameError, "1 is not a descendent of ActiveRecord::Base")
  end

  it "finds nested history models" do
    stub_const("History", Module.new do
      include SystemVersioning::HistoryModelNamespace

      namespace "MyApp" do
        namespace "SystemB"
      end
    end)

    model "MyApp::SystemB::User"

    expect { History::MyApp::SystemB::User }.not_to raise_error
    expect(History::MyApp::SystemB::User).to be < MyApp::SystemB::User
    expect(History::MyApp::SystemB::User).to be < SystemVersioning::HistoryModel
  end

  it "doesn't interfere with custom history classes" do
    model "Cake"
    model "History::Cake" do
      def self.message = "hi"
    end

    expect(History::Cake).to respond_to(:message)
  end

  it "finds subclasses" do
    model "Desert"
    model "CoolWhip", Desert

    expect(History::Desert).to be < ActiveRecord::Base
    expect(History::CoolWhip).to be < Desert
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

      expect(History::Author.count).to eq(4)

      expect(History::Author.first)
        .to have_attributes(name: "Will", system_period: t1...t2)
      expect(History::Author.second)
        .to have_attributes(name: "Bob", system_period: t2...t3)
      expect(History::Author.third)
        .to have_attributes(name: "Sam", system_period: t4...t5)
      expect(History::Author.fourth)
        .to have_attributes(name: "Egbert", system_period: t5...)
    end
  end

  context "source table has no history table" do
    before do
      conn.create_table :authors do |t|
        t.string :name
      end

      model "Author"
    end

    it "sets table_name to source table" do
      expect(History::Author.table_name).to eq("authors")
    end

    it "sets primary_key to source table primary key" do
      expect(History::Author.primary_key).to eq("id")
    end
  end

  context "source table primary key is 'id'" do
    before do
      system_versioned_table :authors do |t|
        t.string :name
      end
      model "Author" do
        include ActiveRecord::Temporal::SystemVersioned
      end
    end

    include_examples "versions records"

    it "sets table_name to history table" do
      expect(History::Author.table_name).to eq("authors_history")
    end

    it "sets primary_key to source table primary key" do
      expect(History::Author.primary_key).to eq(%w[id system_period])
    end
  end

  context "source table primary key is (id, author_number)" do
    before do
      system_versioned_table :authors, primary_key: [:id, :author_number] do |t|
        t.bigserial :id, null: false
        t.bigserial :author_number, null: false
        t.string :name
      end
      model "Author" do
        include ActiveRecord::Temporal::SystemVersioned
      end
    end

    it "sets primary_key to source table primary key" do
      expect(History::Author.primary_key).to eq(%w[id author_number system_period])
    end

    include_examples "versions records"
  end
end
