# rubocop:disable Layout/SpaceAroundOperators

require "spec_helper"

RSpec.describe ActiveRecord::Temporal::ApplicationVersioning::ApplicationVersioned do
  before do
    conn.enable_extension(:btree_gist)

    application_versioned_table :users do |t|
      t.string :name
    end

    application_versioned_table :tasks do |t|
      t.string :name
      t.boolean :done
      t.references :user
    end

    model "ApplicationRecord" do
      self.abstract_class = true

      include ActiveRecord::Temporal

      application_versioning dimensions: :validity
    end

    model "User", ApplicationRecord do
      application_versioned

      has_many :tasks, temporal: true
    end

    model "Task", ApplicationRecord do
      application_versioned

      belongs_to :user, temporal: true
    end
  end

  after { drop_all_tables }

  t = Time.utc(2000)
  current_time = t

  around do |example|
    travel_to(current_time, &example)
  end

  let(:user) { User.create!(id_value: 1, name: "Bob", validity: t-1...nil) }

  describe "#revise_at" do
    it "creates a revision at the given time" do
      new_user = user.revise_at(t+1).with(name: "Sam")

      expect(User.count).to eq(2)

      expect(user).to have_attributes(
        id_value: 1,
        name: "Bob",
        version: 1,
        validity: t-1...t+1
      )
      expect(new_user).to have_attributes(
        id_value: 1,
        name: "Sam",
        version: 2,
        validity: t+1...nil
      )
    end

    it "it creates a revision at the given time in a time scope" do
      new_user = nil

      Querying::Scoping.at({validity: t+1}) do
        new_user = user.revise_at(t+2).with(name: "Sam")
      end

      expect(user).to have_attributes(validity: t-1...t+2)
      expect(new_user).to have_attributes(validity: t+2...nil)
    end

    it "raises an error if revision is not the head" do
      user = User.create!(id_value: 1, name: "Bob", validity: t-1...t)

      expect { user.revise_at(t+1).with(name: "Sam") }
        .to raise_error(
          ActiveRecord::Temporal::ApplicationVersioning::ClosedRevisionError,
          /Cannot revise closed version/
        )
    end
  end

  describe "#revise" do
    it "creates a revision at the current time" do
      new_user = user.revise.with(name: "Sam")

      expect(user).to have_attributes(
        id_value: 1,
        name: "Bob",
        version: 1,
        validity: t-1...Time.current
      )
      expect(new_user).to have_attributes(
        id_value: 1,
        name: "Sam",
        version: 2,
        validity: Time.current...nil
      )
    end

    it "it creates a revision at the global time if set" do
      new_user = nil

      Querying::Scoping.at({validity: t+1}) do
        new_user = user.revise.with(name: "Sam")
      end

      expect(user).to have_attributes(validity: t-1...t+1)
      expect(new_user).to have_attributes(validity: t+1...nil)
    end
  end

  describe "#revision_at" do
    it "initializes a revision at the given time" do
      new_user = user.revision_at(t+1).with(name: "Sam")

      expect(user.changes).to eq("validity" => [t-1...nil, t-1...t+1])
      expect(new_user).to_not be_persisted
      expect(new_user).to have_attributes(
        id_value: 1,
        name: "Sam",
        version: 2,
        validity: t+1...nil
      )
    end

    it "it creates a revision at the given time in a time scope" do
      new_user = nil

      Querying::Scoping.at({validity: t+1}) do
        new_user = user.revision_at(t+2).with(name: "Sam")
      end

      expect(user).to have_attributes(validity: t-1...t+2)
      expect(new_user).to have_attributes(validity: t+2...nil)
    end

    it "raises an error if revision is not the head" do
      user = User.create!(id_value: 1, name: "Bob", validity: t-1...t)

      expect { user.revision_at(t+1).with(name: "Sam") }
        .to raise_error(
          ActiveRecord::Temporal::ApplicationVersioning::ClosedRevisionError,
          /Cannot revise closed version/
        )
    end
  end

  describe "#revision" do
    it "initializes a revision at the current time" do
      new_user = user.revision.with(name: "Sam")

      expect(user.changes).to eq("validity" => [t-1...nil, t-1...Time.current])
      expect(new_user).to_not be_persisted
      expect(new_user).to have_attributes(
        id_value: 1,
        name: "Sam",
        version: 2,
        validity: Time.current...nil
      )
    end

    it "it initializes a revision at the global time if set" do
      new_user = nil

      ActiveRecord::Temporal::Querying::Scoping.at({validity: t+1}) do
        new_user = user.revision.with(name: "Sam")
      end

      expect(user).to have_attributes(validity: t-1...t+1)
      expect(new_user).to have_attributes(validity: t+1...nil)
    end
  end

  describe "#inactivate_at" do
    it "inactivates a record at a given time" do
      expect { user.inactivate_at(t+2) }
        .to(change { user.reload.validity }.from(t-1...nil).to(t-1...t+2))
    end

    it "it inactivates a record at the given time in a time scope" do
      Querying::Scoping.at({validity: t+1}) do
        user.inactivate_at(t+2)
      end

      expect(user).to have_attributes(validity: t-1...t+2)
    end

    it "raises an error if revision is not the head" do
      user = User.create!(id_value: 1, name: "Bob", validity: t-1...t)

      expect { user.inactivate_at(t+1).with(name: "Sam") }
        .to raise_error(
          ActiveRecord::Temporal::ApplicationVersioning::ClosedRevisionError,
          /Cannot inactivate closed version/
        )
    end
  end

  describe "#inactivate" do
    it "inactivates a record at a current time" do
      user.inactivate

      expect(user.reload.validity).to eq(t-1...t)
    end

    it "inactivates a record at the global time if set" do
      ActiveRecord::Temporal::Querying::Scoping.at({validity: t+1}) do
        user.inactivate

        expect(user.reload.validity).to eq(t-1...t+1)
      end
    end
  end

  describe "::original_at" do
    it "instantiates new record at the given time" do
      user = User.original_at(t+1).with(name: "Alice")

      expect(user).to have_attributes(name: "Alice", validity: t+1...nil)
    end

    it "instantiates new record at the given time in a time scope" do
      user = ActiveRecord::Temporal::Querying::Scoping.at({validity: t+1}) do
        User.original_at(t+1).with(name: "Alice")
      end

      expect(user).to have_attributes(name: "Alice", validity: t+1...nil)
    end
  end

  describe "::original" do
    it "instantiates new record at the current time" do
      user = User.original.with(name: "Alice")

      expect(user)
        .to have_attributes(name: "Alice", validity: current_time...nil)
        .and be_new_record
    end

    it "instantiates new record at the global time if set" do
      user = ActiveRecord::Temporal::Querying::Scoping.at({validity: t+1}) do
        User.original.with(name: "Alice")
      end

      expect(user)
        .to have_attributes(name: "Alice", validity: t+1...nil)
        .and be_new_record
    end
  end

  describe "::originate_at" do
    it "creates a new record at the given time" do
      user = User.originate_at(t+1).with(name: "Alice")

      expect(user)
        .to have_attributes(name: "Alice", validity: t+1...nil)
        .and be_persisted
    end

    it "creates a new record at the given time in a time scope" do
      user = ActiveRecord::Temporal::Querying::Scoping.at({validity: t+1}) do
        User.originate_at(t+1).with(name: "Alice")
      end

      expect(user)
        .to have_attributes(name: "Alice", validity: t+1...nil)
        .and be_persisted
    end
  end

  describe "::originate" do
    it "instantiates new record at the current time" do
      user = User.originate.with(name: "Alice")

      expect(user)
        .to have_attributes(name: "Alice", validity: current_time...nil)
        .and be_persisted
    end

    it "instantiates new record at the global time if set" do
      user = ActiveRecord::Temporal::Querying::Scoping.at({validity: t+1}) do
        User.originate.with(name: "Alice")
      end

      expect(user)
        .to have_attributes(name: "Alice", validity: t+1...nil)
        .and be_persisted
    end
  end
end

# rubocop:enable Layout/SpaceAroundOperators
