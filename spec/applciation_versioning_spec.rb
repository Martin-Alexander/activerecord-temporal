require "spec_helper"

RSpec.describe ActiveRecord::Temporal::ApplicationVersioning do
  describe "::application_versioned" do
    it "includes ApplicationVersioned" do
      model "ApplicationRecord" do
        include ActiveRecord::Temporal

        application_versioning dimensions: :validity
      end

      model "Cake", ApplicationRecord do
        application_versioned
      end

      expect(Cake).to be_include(described_class::ApplicationVersioned)
    end
  end
end
