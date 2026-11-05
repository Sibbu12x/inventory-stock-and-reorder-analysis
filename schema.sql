CREATE TABLE suppliers (
  supplier_id text PRIMARY KEY, supplier_name text NOT NULL,
  lead_time_days integer NOT NULL CHECK (lead_time_days > 0),
  minimum_order_qty integer NOT NULL CHECK (minimum_order_qty >= 0),
  contact_email text, active boolean NOT NULL
);
CREATE TABLE locations (location_id text PRIMARY KEY, location_name text NOT NULL, region text NOT NULL);
CREATE TABLE products (
  sku text PRIMARY KEY, product_name text NOT NULL, category text NOT NULL,
  supplier_id text NOT NULL REFERENCES suppliers(supplier_id),
  unit_cost numeric(12,2) NOT NULL CHECK (unit_cost >= 0),
  unit_price numeric(12,2) NOT NULL CHECK (unit_price >= 0),
  unit_of_measure text NOT NULL, active boolean NOT NULL
);
CREATE TABLE inventory_snapshot (
  snapshot_date date NOT NULL, sku text NOT NULL REFERENCES products(sku),
  location_id text NOT NULL REFERENCES locations(location_id),
  on_hand_qty integer NOT NULL CHECK (on_hand_qty >= 0),
  reserved_qty integer NOT NULL CHECK (reserved_qty >= 0 AND reserved_qty <= on_hand_qty),
  incoming_qty integer NOT NULL CHECK (incoming_qty >= 0),
  safety_stock_qty integer NOT NULL CHECK (safety_stock_qty >= 0),
  PRIMARY KEY(snapshot_date,sku,location_id)
);
CREATE TABLE daily_demand (
  sale_date date NOT NULL, sku text NOT NULL REFERENCES products(sku),
  location_id text NOT NULL REFERENCES locations(location_id),
  units_sold integer NOT NULL CHECK (units_sold >= 0),
  unit_price numeric(12,2) NOT NULL CHECK (unit_price >= 0),
  PRIMARY KEY(sale_date,sku,location_id)
);
CREATE TABLE purchase_orders (
  po_id text PRIMARY KEY, sku text NOT NULL REFERENCES products(sku),
  location_id text NOT NULL REFERENCES locations(location_id),
  supplier_id text NOT NULL REFERENCES suppliers(supplier_id),
  order_date date NOT NULL, expected_date date NOT NULL CHECK (expected_date >= order_date),
  ordered_qty integer NOT NULL CHECK (ordered_qty > 0),
  received_qty integer NOT NULL CHECK (received_qty >= 0 AND received_qty <= ordered_qty),
  status text NOT NULL CHECK (status IN ('open','received','cancelled'))
);
CREATE TABLE reorder_recommendations (
  as_of_date date NOT NULL, sku text NOT NULL REFERENCES products(sku),
  location_id text NOT NULL REFERENCES locations(location_id),
  supplier_id text NOT NULL REFERENCES suppliers(supplier_id),
  avg_daily_demand_14d numeric(12,3) NOT NULL CHECK (avg_daily_demand_14d >= 0),
  lead_time_days integer NOT NULL CHECK (lead_time_days > 0),
  safety_stock_qty integer NOT NULL CHECK (safety_stock_qty >= 0),
  available_qty integer NOT NULL, reorder_point_qty integer NOT NULL CHECK (reorder_point_qty >= 0),
  recommended_order_qty integer NOT NULL CHECK (recommended_order_qty >= 0), reason text NOT NULL,
  PRIMARY KEY(as_of_date,sku,location_id)
);

CREATE INDEX daily_demand_sku_location_date_idx ON daily_demand(sku,location_id,sale_date);
CREATE INDEX purchase_orders_open_sku_location_idx ON purchase_orders(sku,location_id) WHERE status = 'open';
