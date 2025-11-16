require "spec_helper"

RSpec.describe "sti" do
  before do
    system_versioned_table :vehicles do |t|
      t.string :name
      t.string :type, :string
    end

    history_model_namespace

    system_versioned_model "Vehicle"
    system_versioned_model "Car", Vehicle
    system_versioned_model "Truck", Vehicle
  end

  after do
    drop_all_tables
    drop_all_versioning_hooks
  end

  it "::instantiate returns version class for type" do
    expect(History::Vehicle.instantiate({"type" => "Car"}).class)
      .to eq(History::Car)

    expect(History::Vehicle.instantiate({"type" => "Truck"}).class)
      .to eq(History::Truck)

    expect(History::Vehicle.find_sti_class("Car")).to eq(History::Car)
    expect(History::Vehicle.find_sti_class("Truck")).to eq(History::Truck)
  end

  it "records are instantiated with the correct class" do
    Car.create!
    Truck.create!

    car_version = History::Car.sole
    truck_version = History::Truck.sole

    expect(car_version.type).to eq("Car")
    expect(truck_version.type).to eq("Truck")
  end

  it "queries are filtered by their type" do
    Car.create!
    Truck.create!

    expect(History::Vehicle.all.count).to eq(2)
    expect(History::Car.all.count).to eq(1)
    expect(History::Truck.all.count).to eq(1)
  end

  context "when using a different namespace" do
    before do
      history_model_namespace "Versions"
    end

    it "::instantiate returns version class for type" do
      expect(Versions::Vehicle.instantiate({"type" => "Car"}).class)
        .to eq(Versions::Car)

      expect(Versions::Vehicle.instantiate({"type" => "Truck"}).class)
        .to eq(Versions::Truck)

      expect(Versions::Vehicle.find_sti_class("Car")).to eq(Versions::Car)
      expect(Versions::Vehicle.find_sti_class("Truck")).to eq(Versions::Truck)
    end

    it "records are instantiated with the correct class" do
      Car.create!
      Truck.create!

      car_version = Versions::Car.sole
      truck_version = Versions::Truck.sole

      expect(car_version.type).to eq("Car")
      expect(truck_version.type).to eq("Truck")
    end

    it "queries are filtered by their type" do
      Car.create!
      Truck.create!

      expect(Versions::Vehicle.all.count).to eq(2)
      expect(Versions::Car.all.count).to eq(1)
      expect(Versions::Truck.all.count).to eq(1)
    end
  end
end
