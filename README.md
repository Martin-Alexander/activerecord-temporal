# Active Record Temporal

An Active Record plugin for temporal data modeling in PostgreSQL. Record historical data and query it at any point in time using the full power of Active Record.

## Why Temporal Data?

As applications mature, changing business requirements become increasingly complicated by the need to handle historical data. You might need to:

- Update subscriptions plans, but retain existing subscribers' original payment schedules
- Allow users to see information as it was before their view permission was revoked
- Understand why generated financial reports have changed recently
- Restore erroneously updated data

Many Rails applications use a patchwork of approaches:

- **Soft deletes** with a `deleted_at` column, but updates that still permanently overwrite data.
- **Ad-hoc snapshot tables** that lack a unified structure, must each be maintained differently, and require custom handling to associate with other models.
- **Audit gems or JSON columns** that serialize changes. Their data doesn't evolve with schema changes and cannot be easily integrated into Active Record queries, scopes, and associations.
- **Event systems** that are used to fill gaps in the data model and gradually take on responsibilities that are implementation details with no business relevance.

Temporal databases solve these problems by providing a simple and coherent data model to reach for whenever historical data is needed.

This can be a versioning strategy that operates automatically at the database level or one where versioning is used up front as the default method for all CRUD operations on a table.

## Overview

This gem provides both system versioning and application versioning. They can be used alone, in parallel, or in conjunction (e.g., for bitemporal data modelling), and use the same Active Record interface for time-travel queries.

### System Versioning Overview

- Maintained by the database using PostgreSQL triggers and operates out of sight of Active Record
- History tables can be easily added to existing tables to provide temporal features where needed
- Version a subset of a table's columns if storage space is a concern

Read more details [here](#system-versioning).

```ruby
class CreateEmployees < ActiveRecord::Migration[8.1]
  using ActiveRecord::Temporal::Migration

  def change
    create_table :employees, system_versioning: true do |t|
      t.integer :salary
    end
  end
end

module History
  include ActiveRecord::Temporal::HistoryModelNamespace
end

class Employee < ActiveRecord::Base
  include ActiveRecord::Temporal::SystemVersioned
end

Employee.create(salary: 75)            # Executed on 1999-12-31
Employee.create(salary: 100)           # Executed on 2000-01-07
Employee.last.update(salary: 200)      # Executed on 2000-01-14
Employee.last.destroy                  # Executed on 2000-01-28

History::Employee.all
# => [
#   #<History::Employee id: 1, salary: 75, system_period: 1999-12-31...>,
#   #<History::Employee id: 2, salary: 100, system_period: 2000-01-07...2000-01-14>,
#   #<History::Employee id: 2, salary: 200, system_period: 2000-01-14...2000-01-28>
# ]
```

### Application Versioning Overview

- Uses a single table and has the application manage versioning using business-relevant points in time
- Entities are versioned with `#revise`, `#inactivate`, and others.
- Corrections can be made with `#update` and `#destroy`
- Data migrations can be performed "in the future." New data will automatically become current at a set time without the need for coordination with releases or feature flags.

Read more details [here](#application-versioning).

```ruby
class CreateEmployees < ActiveRecord::Migration[8.1]
  def change
    using ActiveRecord::Temporal::Migration

    create_table :employees, application_versioning: :validity do |t|
      t.integer :salary
    end
  end
end

class Employee < ActiveRecord::Base
  include ActiveRecord::Temporal::ApplicationVersioned

  self.time_dimension = :validity
end

time = Time.parse("2000-01-01")

Employee.create(salary: 75, validity_start: time.next_month)
Employee.create(salary: 100, validity_start: time.next_month)
employee = Employee.last
new_version = employee.revise_at(3.months.from_now).with(salary: 200)
new_version.inactive_at(time.next_year)

Employee.all
# => [
#   #<Employee id: 1, version: 1, salary: 75, validity: 2000-02-01...>,
#   #<Employee id: 2, version: 1, salary: 100, validity: 2000-02-01...2000-03-01>,
#   #<Employee id: 2, version: 2, salary: 200, validity: 2000-03-01...2001-01-01>
# ]
```

### Time-travel Queries Overview

- Query the database as it existed at a given point in time using the `as_of` scope
- The time constraint will apply to all joined/preloaded associations
- Loaded records are tagged with the time used and propagate it to subsequent associations
- Use scoped blocks to query at a given time by default

Read more details [here](#time-travel-queries).

```ruby
module History
  include ActiveRecord::Temporal::HistoryModelNamespace
end

class Product < ActiveRecord::Base
  include ActiveRecord::Temporal::SystemVersioned

  has_many :lines
end

class Line < ActiveRecord::Base
  include ActiveRecord::Temporal::SystemVersioned

  belongs_to :product
end

class Order < ActiveRecord::Base
  include ActiveRecord::Temporal::SystemVersioned

  has_many :lines
  has_many :products, through: :lines
end

product = Product.create(price: 50)
order = Order.create(placed_at: Time.current)
order.lines.create(product: product)

Product.first.update(price: 100)            # Product catalogue changed

# Get the order's original price
order = Order.first
order.products.first                        # => #<History::Product price: 100>
order.as_of(order.placed_at).products.first # => #<History::Product price: 50>

products = Product
  .as_of(10.months.ago)
  .includes(lines: :orders)
  .where(lines: {quantity: 1})              # => [#<History::Product>, #<History::Product>]

products.first.categories.first             # => The product's category as it was 10 months ago

Temporal::ScopedQueries.at 1.year.ago do
  products = Product.all                    # => All products as of 1 year ago
  products = Product.as_of(Time.current)    # Ignore scope's default time
end
```

## Requirements

- Active Record >= 8
- PostgreSQL >= 13

## Installation

```ruby
# Gemfile

gem "activerecord-temporal"
```

## Time-travel Queries

Time-travel queries are agnostic towards the process by which records come to be versioned (if they are versioned at all). The only database requirement is that the table have a time range column (either `tsrange`, `tstzrange`, or `daterange`). Application versioning and system versioning are built on top of this feature.

```ruby
create_table :accounts do |t|
  t.tstzrange :lifespan
end

class Account < ActiveRecord::Base
  include ActiveRecord::Temporal::Querying

  self.time_dimension = :lifespan
end

Account.create(lifespan: Time.parse("2030-01-01")...nil)
Account.create(lifespan: Time.parse("2029-08-01")...Time.parse("2035-06-01"))

Account.at_time(Time.parse("2036-03-15"))
# SELECT accounts.* FROM accounts WHERE accounts.lifespan @> '2036-03-15 00:00:00'::timestamptz
```

The `at_time` scope is implemented as a simple `where` query that uses PostgreSQL's contain operation `@>` to efficiently filter rows.

### Temporal Associations

```ruby
class Product < ActiveRecord::Base
  include ActiveRecord::Temporal::Querying

  self.time_dimension = :validity

  has_many :prices, temporal: true
end

Product.as_of(Time.parse("2031-11-09")).includes(:prices).where("prices.amount > 100")
# SELECT products.* FROM products
# JOIN prices ON prices.product_id = products.id AND prices.validity @> '2031-11-09 00:00:00'::timestamptz
# WHERE products.validity @> '2031-11-09 00:00:00'::timestamptz AND prices.amount > 100

product = Product.as_of(Time.parse("2031-11-09")).find_by(sku: "prod_88fa9d")

product.time_tag                        # => 2031-11-09, controls time scope propagation
product.prices                          # => Associated prices as of 2031-11-09
product.as_of(Time.parse("2029-01-01")) # => The same product as of 2029-01-01

Product.first.prices                    # => Associated prices as of `Time.current`
```

Including `Temporal::Querying` adds a `temporal: true` option to association macros which interacts with the `as_of` scope to propagate temporal scopes to associations. In addition to filtering by time, the `as_of` scope tags all loaded records with given timestamp so that subsequent associations on them propagate the scope as well.

- **`at_time`** is a simple scope equivalent to `where("validity @> ?::timestamptz", time)`
- **`as_of`** applies `at_time`  to all temporal associations and tags all loaded records

#### Pseudo-temporal Associations

Models without the underlying time range column can still include `Temporal::Querying` and add `temporal: true` to their associations. Such "pseudo-temporal" associations will propagate temporal scopes, but will be unaffected by them (as if all their records have double unbounded time ranges equivalent to `nil...nil`).

### Compatibility with Existing Scopes

```ruby
class Product < ActiveRecord::Base
  include ActiveRecord::Temporal::Querying

  self.time_dimension = :validity

  has_one :price, -> { where(active: true) }, temporal: true
end
```

Temporal associations are implemented as association scopes and will be merged with the association's non-temporal scope.

### Block-scoped Default Time

```ruby
ActiveRecord::Temporal::ScopedQueries.at Time.parse("2011-04-30") do
  Product.all                                 # => All products as of 2011-04-30
  Product.find_by!(sku: "prod_88fa9d").prices # => All associated prices as of 2011-04-30
  Product.as_of(Time.current)                 # => All current products

  ActiveRecord::Temporal::ScopedQueries.at Time.parse("1990-06-07") do
    Product.all                               # => All products as of 1990-06-07
  end
end
```

A block can be passed to `Temporal::ScopedQueries.at` to apply a default temporal scope to all queries made inside. It works similarly to Active Record's [`scoping`](https://api.rubyonrails.org/classes/ActiveRecord/Relation.html#method-i-scoping) class method.

### Global Default Time

```ruby
class ApplicationController < ActionController::Base
  around_action do |controller, action|
    ActiveRecord::Temporal::ScopedQueries.at(Time.current, &action)
  end
end

class ApplicationRecord < ActiveRecord::Base
  include ActiveRecord::Temporal::Querying

  self.time_dimension = :validity

  default_scope -> { at_time(Time.current) }
end
```

Although temporal associations are scoped to the current time by default, non-association queries (e.g., `Product.all`) are unscoped. If you typically only need current records, you can scope controller actions to `Time.current`, which roughly equates to the time when a request was received. Active Record's `default_scope` can also be used.

So far, everything shown works with or without versioning.

## System Versioning

The temporal model of this gem is based on the SQL specification. It's also roughly the same model used by RDMSs like [MarianaDB](https://mariadb.com/docs/server/reference/sql-structure/temporal-tables/system-versioned-tables) and [Microsoft SQL Server](https://learn.microsoft.com/en-us/sql/relational-databases/tables/temporal-tables?view=sql-server-ver17), and by the PostgreSQL extension [Temporal Tables Extension](https://github.com/arkhipov/temporal_tables) and its PL/pgSQL version [Temporal Tables](https://github.com/nearform/temporal_tables).

Rows in the history table (or partition, view, etc.) represent rows that existed in the source table over a particular period of time. For PostgreSQL implementations this period of time is typically stored in a `tstzrange` column that this gem calls `system_period`.

### Inserts

Rows inserted into the source table will be also inserted into the history table with `system_period` beginning at the current time and ending at infinity.

```sql
-- Transaction start time: 2000-01-01

INSERT INTO products (name, price) VALUES ('Glow & Go Set', 29900), ('Zepbound', 34900)

/* products
┌────┬───────────────┬───────┐
│ id │     name      │ price │
├────┼───────────────┼───────┤
│  1 │ Glow & Go Set │ 29900 │
│  2 │ Zepbound      │ 34900 │
└────┴───────────────┴───────┘*/

/* products_history
┌────┬───────────────┬───────┬──────────────────────────────────┐
│ id │     name      │ price │          system_period           │
├────┼───────────────┼───────┼──────────────────────────────────┤
│  1 │ Glow & Go Set │ 29900 │ ["2000-01-01 00:00:00",infinity) │
│  2 │ Zepbound      │ 34900 │ ["2000-01-01 00:00:00",infinity) │
└────┴───────────────┴───────┴──────────────────────────────────┘*/
```

### Updates

Rows updated in the source table will:

1. Update the matching row in the history table by ending `system_period` with the current time.
2. Insert a row into the history table that matches the new state in the source table and beginning `system_period` at the current time and ending at infinity.

```sql
-- Transaction start time: 2000-01-02

UPDATE products SET price = 14900 WHERE id = 1

/* products
┌────┬───────────────┬───────┐
│ id │     name      │ price │
├────┼───────────────┼───────┤
│  1 │ Glow & Go Set │ 14900 │
│  2 │ Zepbound      │ 34900 │
└────┴───────────────┴───────┘*/

/* products_history
┌────┬───────────────┬───────┬───────────────────────────────────────────────┐
│ id │     name      │ price │                 system_period                 │
├────┼───────────────┼───────┼───────────────────────────────────────────────┤
│  1 │ Glow & Go Set │ 29900 │ ["2000-01-01 00:00:00","2000-01-02 00:00:00") │
│  2 │ Zepbound      │ 34900 │ ["2000-01-01 00:00:00",infinity)              │
│  1 │ Glow & Go Set │ 14900 │ ["2000-01-02 00:00:00",infinity)              │
└────┴───────────────┴───────┴───────────────────────────────────────────────┘*/
```

### Deletes

Rows deleted in the source table will update the matching row in the history table by ending `system_period` with the current time.

```sql
-- Transaction start time: 2000-01-03

DELETE FROM products WHERE id = 2

/* products
┌────┬───────────────┬───────┐
│ id │     name      │ price │
├────┼───────────────┼───────┤
│  1 │ Glow & Go Set │ 14900 │
└────┴───────────────┴───────┘*/

/* products_history
┌────┬───────────────┬───────┬───────────────────────────────────────────────┐
│ id │     name      │ price │                 system_period                 │
├────┼───────────────┼───────┼───────────────────────────────────────────────┤
│  1 │ Glow & Go Set │ 29900 │ ["2000-01-01 00:00:00","2000-01-02 00:00:00") │
│  2 │ Zepbound      │ 34900 │ ["2000-01-01 00:00:00","2000-01-03 00:00:00") │
│  1 │ Glow & Go Set │ 14900 │ ["2000-01-02 00:00:00",infinity)              │
└────┴───────────────┴───────┴───────────────────────────────────────────────┘*/
```

<!--
SELECT * FROM (
  VALUES (1, 'Glow & Go Set', 29900), (2, 'Zepbound', 34900)
) AS products(id, name, price);

SELECT * FROM (VALUES
  (1, 'Glow & Go Set', 29900, tsrange('2000-01-01', 'infinity')),
  (2, 'Zepbound', 34900, tsrange('2000-01-01', 'infinity'))
) AS products(id, name, price, system_period);

SELECT * FROM (
  VALUES (1, 'Glow & Go Set', 14900), (2, 'Zepbound', 34900)
) AS products(id, name, price);

SELECT * FROM (VALUES
  (1, 'Glow & Go Set', 29900, tsrange('2000-01-01', '2000-01-02')),
  (2, 'Zepbound', 34900, tsrange('2000-01-01', 'infinity')),
  (1, 'Glow & Go Set', 14900, tsrange('2000-01-02', 'infinity')),
) AS products(id, name, price, system_period);

SELECT * FROM (
  VALUES (1, 'Glow & Go Set', 14900)
) AS products(id, name, price);

SELECT * FROM (VALUES
  (1, 'Glow & Go Set', 29900, tsrange('2000-01-01', '2000-01-02')),
  (2, 'Zepbound', 34900, tsrange('2000-01-01', '2000-01-03')),
  (1, 'Glow & Go Set', 14900, tsrange('2000-01-02', 'infinity')),
) AS products(id, name, price, system_period);
-->

### Create a History Table

Using `Temporal::SchemaStatements` adds the `system_versioning` option to `create_table`. This will automatically create a matching history table and the PostgreSQL triggers.

```ruby
class CreateProducts < ActiveRecord::Base
  using ActiveRecord::Temporal::Migration

  def change
    create_table :products, system_versioning: true do |t|
      t.string :sku, null: false
      t.string :name
      t.references :price, null: false, foreign_key: true
    end
  end
end
```

The `system_versioning: true` option will create a history table that:
- Has `tstzrange` columns called `system_period`
- Has a composite primary key composed of the source table's primary key and `system_period`
- Includes all columns names and types from the source table
- Excludes all foreign key and uniqueness constraints
- Calls `create_versioning_hook` to connect the source and history table

The code above is equivalent to:

```ruby
class CreateProducts < ActiveRecord::Base
  def change
    create_table :products do |t|
      t.string :sku, null: false
      t.string :name
      t.references :price, null: false, foreign_key: true
    end

    create_table :products_history, primary_key: [:id, :system_period] do |t|
      t.bigint :id, null: false
      t.string :sku, null: false
      t.string :name
      t.references :price, null: false
      t.tstzrange :system_period, null: false
    end

    create_versioning_hook :products, :products_history
  end
end
```

The key to system versioning is the `create_versioning_hook` method. It creates three sets of PostgreSQL triggers and PL/pgSQL functions that watch for `INSERT`, `UPDATE`, and `DELETE` actions on the source table and update the history table accordingly. PostgreSQL triggers share the same transaction as the statement that triggered them and are thus atomic.

The simplest of these triggers is the `INSERT` trigger and it looks like this:

```pgsql
CREATE FUNCTION public.sys_ver_fn_7722e802d8() RETURNS trigger LANGUAGE plpgsql AS $$
  BEGIN
    INSERT INTO "products_history" ("id", "sku", "name", "price_id", system_period)
    VALUES (NEW."id", NEW."sku", NEW."name", NEW."price_id", tstzrange(NOW(), 'infinity'));

    RETURN NULL;
  END;
$$;

CREATE TRIGGER sys_ver_insert_trigger AFTER INSERT ON public.products
FOR EACH ROW EXECUTE FUNCTION public.sys_ver_fn_7722e802d8();
```

Note that `NOW()` gets the time from the start of the current transaction. So all changes to the source table made in one transaction will use the same timestamp.

### Foreign Key Constraints

Given an existing source table, the requirements for a history table are:
1. A composite primary key made up of a column matching a unique column (or set of columns) in the source table (usually just `id`) and `system_period` of the type `tstzrange`
2. No columns that share a name with columns in the source table but have a different type (e.g., `id INTEGER` and `id BIGINT`)

There are other restrictions on history tables that fall into the category of things that are conceptually incompatible with history tables. This would be things like unique constraints on columns used to track changes or triggers that update other versioned tables. Most of these should be pretty obvious and are not part of Active Record's DDL DSL anyways.

Foreign key constraints to other history tables (e.g., between `history_products` and `history_prices`) can only be used with the `WITHOUT OVERLAPS`/`PERIOD` feature added in PostgreSQL 18. Otherwise custom triggers are needed to achieve the same effect.

Foreign key constraints are discussed further below.

### Active Record Models

```ruby
class Product < ActiveRecord::Base
  belongs_to :price
end

class HistoryProduct < Product
  include ActiveRecord::Temporal::SystemVersioned
end

HistoryProduct.primary_key            # => ["id", "system_period"]
HistoryProduct.table_name             # => "products_history", detected from SQL comment on triggers

time = Time.parse("2027-12-23")

products = HistoryProduct.as_of(time) # => Products as of 2027-12-23
products.first.price                  # => Inherited associations are temporal by default

HistoryProduct.sti_name               # => "Product", compatible with single-table inheritance
HistoryProduct.time_dimension         # => ["system_period"]
```

Regular Active Record models can be used for history tables without any help from this gem. But to create a temporal version of the source model just inherit from it and include `Temporal::SystemVersioned`. This module automatically includes `Temporal::Querying`, adds `temporal: true` to the inherited associations, and ensures that single-table inheritance is properly supported.

### Models not Backed by a History Table

```ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end

class Product < ApplicationRecord
  belongs_to :price
end

class Price < ApplicationRecord
  has_many :products
end

Product.table_name                 # => "products"
Price.table_name                   # => "prices"

table_exists?("products_history")  # => true
table_exists?("prices_history")    # => false

class HistoryProduct < Product
  include Temporal::SystemVersioned
end

class HistoryPrice < Price
  include Temporal::SystemVersioned
end

HistoryProduct.table_name          # => "products_history"
HistoryPrice.table_name            # => "prices"
```

In the same way that `Temporal::Querying` can be included in models that don't have a time range column, the `Temporal::SystemVersioned` module can be included in models that aren't backed by a history table. They will still have their inherited associations temporalized, but as their table lacks the time range column their associations will be "pseudo-temporal" (i.e., they will propagate time scopes, but not be affected by them).

This comes in handy when using the system versioning namespace to perform this process for all of your Active Record models automatically.

### System Versioning Model Namespace

```ruby
module History
  include Temporal::SystemVersioningNamespace

  base ApplicationRecord
end

History::Product                   # => History::Product(id: integer, system_period: tstzrange, name: string, sku: string)
History::Price                     # => History::Price(id: integer, amount: integer)

History::Product.table_name        # => "products_history"
History::Price.table_name          # => "prices"

History::Product.primary_key       # => ["id", "system_period"]
History::Price.primary_key         # => "id"

products = History::Product.as_of(Time.parse("2027-12-23"))
product = products.first           # => #<History::Product id: 1, system_period: 2027-11-07...2027-12-28, name: "Toy", sku: "prod_88fa9d">
product.name                       # => "Toy"
product.price                      # => #<History::Price id: 1, amount: 100>

products = History::Product.as_of(Time.parse("2028-01-03"))
product = products.first           # => #<History::Product id: 1, system_period: 2027-12-28..., name: "Toy (NEW!)", sku: "prod_88fa9d">
product.name                       # => "Toy (NEW!)"
product.price                      # => #<History::Price id: 2, amount: 125>
```

Including the `Temporal::SystemVersioningNamespace` effectively create a hierarchy of system versioned models that mirrors the hierarchy specified with the `base` method. Associations in these models will point to other models in the namespace (if they exist, otherwise they'll point to original model).

This means that even if only one table is system versioned ("products", in this example), important time-travel queries that join non-versioned tables can still be made using existing Active Record associations.

```ruby
order = Order.find_by(id: 1721)

# Select products included in an order as they were at the time the order was placed
History::Product
  .as_of(order.placed_at)
  .joins(:order_line_items)
  .where(order_line_items: {order_id: order.id})

# SELECT products_history.* FROM products_history
# JOIN order_line_items ON order_line_items.product_id = products_history.id
# WHERE products_history.system_period @> '2027-11-07 00:00:00'::timestamptz
#   AND order_line_items.order_id = 1721
```

### Schema Migrations

```ruby
create_table :products, primary_key: :entity_id do |t|
  t.string :sku, null: false
  t.string :name, null: false
  t.references :price, null: false, foreign_key: true
end

create_table :products_history, primary_key: [:entity_id, :system_period] do |t|
  t.bigint :entity_id, null: false
  t.string :name, null: false
  t.references :price, null: false
  t.tstzrange :system_period, null: false
end

create_versioning_hook :products,
  :products_history,
  columns: [:entity_id, :name],             # Exclude the sku from system versioning
  primary_key: [:entity_id]                 # Defaults to `id`, but products uses `entity_id`

add_column :products_history, :sku, :string # Add it later if you change your mind

change_versioning_hook :products,           # And update the triggers to start tracking it
  :products_history,
  add_columns: [:sku]

change_versioning_hook :products,           # Keep the name column, but stop tracking it
  :products_history,
  remove_columns: [:name]

drop_versioning_hook :products,             # Keep the table, but disable system versioning
  :products_history

drop_versioning_hook :products,             # Or specify the state of the hook when dropping
  :products_history,                        # it in order to make the migration reversible
  columns: [:entity_id, :sku],
  primary_key: [:entity_id]

drop_table :products_history                # Drop history table like any other table
```

The behaviour of the database triggers can be changed alongside other changes to the database's schema. The methods `create_versioning_hook`, `drop_versioning_hook`, and `change_versioning_hook` use SQL comments on the functions to expose their current state to the migration methods. Otherwise, if you removed these comments, you'd have to drop and fully respecify the hook on every change.

## Application Versioning