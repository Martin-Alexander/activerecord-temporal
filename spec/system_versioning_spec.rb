require "spec_helper"

RSpec.describe ActiveRecord::Temporal::SystemVersioning do
  include ActiveRecord::Temporal

  it "includes HistoryModels" do
    model "ApplicationRecord" do
      include ActiveRecord::Temporal

      system_versioning
    end

    expect(ApplicationRecord).to be_include(SystemVersioning::HistoryModels)
  end

  describe "::system_versioned" do
    it "includes SystemVersioned" do
      model "ApplicationRecord" do
        include ActiveRecord::Temporal

        system_versioning
      end

      model "Cake", ApplicationRecord do
        system_versioned
      end

      expect(Cake).to be_include(SystemVersioning::SystemVersioned)
    end
  end
end
