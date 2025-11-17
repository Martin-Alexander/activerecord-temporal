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
        namespace "SystemB" do
          namespace "Deprecated"
        end
      end
    end)

    model "MyApp::Post"
    model "MyApp::SystemB::Account"
    model "MyApp::SystemB::Deprecated::User"

    expect { History::MyApp::Post }.not_to raise_error
    expect(History::MyApp::Post).to be < MyApp::Post
    expect(History::MyApp::Post).to be < SystemVersioning::HistoryModel

    expect { History::MyApp::SystemB::Account }.not_to raise_error
    expect(History::MyApp::SystemB::Account).to be < MyApp::SystemB::Account
    expect(History::MyApp::SystemB::Account).to be < SystemVersioning::HistoryModel

    expect { History::MyApp::SystemB::Deprecated::User }.not_to raise_error
    expect(History::MyApp::SystemB::Deprecated::User).to be < MyApp::SystemB::Deprecated::User
    expect(History::MyApp::SystemB::Deprecated::User).to be < SystemVersioning::HistoryModel
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
end
