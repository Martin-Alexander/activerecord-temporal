require "spec_helper"

RSpec.describe ActiveRecord::Temporal do
  describe "::system_versioning" do
    it "includes SystemVersioning" do
      model "ApplicationRecord"

      ApplicationRecord.include described_class
      ApplicationRecord.system_versioning

      expect(ApplicationRecord).to be_include(described_class::SystemVersioning)
    end
  end

  describe "::application_versioning" do
    it "includes ApplicationVersioning" do
      model "ApplicationRecord"

      ApplicationRecord.include described_class
      ApplicationRecord.application_versioning

      expect(ApplicationRecord).to be_include(described_class::ApplicationVersioning)
    end

    it "sets the time dimension" do
      model "ApplicationRecord"

      ApplicationRecord.include described_class
      ApplicationRecord.application_versioning dimensions: :validity

      expect(ApplicationRecord).to be_include(described_class::ApplicationVersioning)
      expect(ApplicationRecord.time_dimensions).to eq([:validity])
    end
  end
end
