insert into public.stores (
  id,
  owner_id,
  name,
  category,
  address,
  is_active,
  is_open
)
values (
  '77777777-7777-7777-7777-777777777772',
  null,
  'Luumoh Fresh Market',
  'grocery',
  '8 Allen Avenue, Ikeja, Lagos',
  true,
  true
)
on conflict (id) do update
set name = excluded.name,
    category = excluded.category,
    address = excluded.address,
    is_active = excluded.is_active,
    is_open = excluded.is_open,
    updated_at = now();

insert into public.products (
  id,
  store_id,
  name,
  description,
  price,
  category,
  image_url,
  is_available
)
values
  (
    '88888888-8888-8888-8888-888888888887',
    '77777777-7777-7777-7777-777777777772',
    'Peak Milk Powder Sachet',
    'Single-serve powdered milk sachet for tea, cereal, and baking.',
    650,
    'dairy',
    'https://images.unsplash.com/photo-1550583724-b2692b85b150?auto=format&fit=crop&w=900&q=80',
    true
  ),
  (
    '88888888-8888-8888-8888-888888888888',
    '77777777-7777-7777-7777-777777777772',
    'Dano Full Cream Milk 400g',
    'Full cream powdered milk tin for family breakfasts and drinks.',
    5200,
    'dairy',
    'https://images.unsplash.com/photo-1563636619-e9143da7973b?auto=format&fit=crop&w=900&q=80',
    true
  ),
  (
    '88888888-8888-8888-8888-888888888889',
    '77777777-7777-7777-7777-777777777772',
    'Granulated Sugar 1kg',
    'Everyday white sugar for drinks, cooking, and baking.',
    1800,
    'pantry',
    'https://images.unsplash.com/photo-1581441363689-1f3c3c414635?auto=format&fit=crop&w=900&q=80',
    true
  ),
  (
    '88888888-8888-8888-8888-888888888890',
    '77777777-7777-7777-7777-777777777772',
    'Cabin Biscuits Pack',
    'Crisp cabin biscuits for tea, school snacks, and quick bites.',
    900,
    'snacks',
    'https://images.unsplash.com/photo-1590080875515-8a3a8dc5735e?auto=format&fit=crop&w=900&q=80',
    true
  ),
  (
    '88888888-8888-8888-8888-888888888891',
    '77777777-7777-7777-7777-777777777772',
    'Digestive Biscuits',
    'Classic digestive biscuits with a lightly sweet crunch.',
    1800,
    'snacks',
    'https://images.unsplash.com/photo-1558961363-fa8fdf82db35?auto=format&fit=crop&w=900&q=80',
    true
  ),
  (
    '88888888-8888-8888-8888-888888888892',
    '77777777-7777-7777-7777-777777777772',
    'Red Palm Oil 1L',
    'Rich red palm oil for soups, stews, beans, and native dishes.',
    2500,
    'cooking_oil',
    'https://images.unsplash.com/photo-1474979266404-7eaacbcd87c5?auto=format&fit=crop&w=900&q=80',
    true
  ),
  (
    '88888888-8888-8888-8888-888888888893',
    '77777777-7777-7777-7777-777777777772',
    'Vegetable Oil 1L',
    'Everyday vegetable oil for frying, cooking, and baking.',
    2800,
    'cooking_oil',
    'https://images.unsplash.com/photo-1620706857370-e1b9770e8bb1?auto=format&fit=crop&w=900&q=80',
    true
  ),
  (
    '88888888-8888-8888-8888-888888888894',
    '77777777-7777-7777-7777-777777777772',
    'Golden Penny Spaghetti 500g',
    'Dry spaghetti pack for fast weekday meals.',
    950,
    'pantry',
    'https://images.unsplash.com/photo-1551892374-ecf8754cf8b0?auto=format&fit=crop&w=900&q=80',
    true
  ),
  (
    '88888888-8888-8888-8888-888888888895',
    '77777777-7777-7777-7777-777777777772',
    'Local Rice 5kg',
    'Clean local rice packed for family meals.',
    8500,
    'grocery',
    'https://images.unsplash.com/photo-1536304993881-ff6e9eefa2a6?auto=format&fit=crop&w=900&q=80',
    true
  )
on conflict (id) do update
set store_id = excluded.store_id,
    name = excluded.name,
    description = excluded.description,
    price = excluded.price,
    category = excluded.category,
    image_url = excluded.image_url,
    is_available = excluded.is_available,
    updated_at = now();

insert into public.inventory_items (
  product_id,
  sku,
  quantity_on_hand,
  reorder_level
)
values
  ('88888888-8888-8888-8888-888888888887', 'DEMO-MARKET-PEAK-MILK-SACHET', 80, 20),
  ('88888888-8888-8888-8888-888888888888', 'DEMO-MARKET-DANO-MILK-400G', 25, 8),
  ('88888888-8888-8888-8888-888888888889', 'DEMO-MARKET-SUGAR-1KG', 60, 15),
  ('88888888-8888-8888-8888-888888888890', 'DEMO-MARKET-CABIN-BISCUITS', 90, 20),
  ('88888888-8888-8888-8888-888888888891', 'DEMO-MARKET-DIGESTIVE-BISCUITS', 45, 12),
  ('88888888-8888-8888-8888-888888888892', 'DEMO-MARKET-PALM-OIL-1L', 35, 10),
  ('88888888-8888-8888-8888-888888888893', 'DEMO-MARKET-VEG-OIL-1L', 40, 10),
  ('88888888-8888-8888-8888-888888888894', 'DEMO-MARKET-SPAGHETTI-500G', 75, 20),
  ('88888888-8888-8888-8888-888888888895', 'DEMO-MARKET-LOCAL-RICE-5KG', 28, 8)
on conflict (product_id) do update
set sku = excluded.sku,
    quantity_on_hand = excluded.quantity_on_hand,
    reorder_level = excluded.reorder_level,
    updated_at = now();
