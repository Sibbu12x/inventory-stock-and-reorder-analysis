\i schema.sql
\copy suppliers FROM 'data/suppliers.csv' CSV HEADER
\copy locations FROM 'data/locations.csv' CSV HEADER
\copy products FROM 'data/products.csv' CSV HEADER
\copy inventory_snapshot FROM 'data/inventory_snapshot.csv' CSV HEADER
\copy daily_demand FROM 'data/daily_demand.csv' CSV HEADER
\copy purchase_orders FROM 'data/purchase_orders.csv' CSV HEADER
\copy reorder_recommendations FROM 'data/reorder_recommendations.csv' CSV HEADER
