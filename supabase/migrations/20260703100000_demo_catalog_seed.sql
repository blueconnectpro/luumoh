insert into public.stores (
  id,
  owner_id,
  name,
  category,
  address,
  is_active,
  is_open
)
values
  (
    '77777777-7777-7777-7777-777777777771',
    null,
    'Luumoh Demo Kitchen',
    'restaurant',
    '14 Admiralty Way, Lekki Phase 1, Lagos',
    true,
    true
  ),
  (
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
    '88888888-8888-8888-8888-888888888881',
    '77777777-7777-7777-7777-777777777771',
    'Smoky Jollof Rice',
    'Party-style jollof rice with grilled chicken and plantain.',
    4200,
    'rice',
    'https://images.unsplash.com/photo-1604329760661-e71dc83f8f26?auto=format&fit=crop&w=900&q=80',
    true
  ),
  (
    '88888888-8888-8888-8888-888888888882',
    '77777777-7777-7777-7777-777777777771',
    'Peppered Chicken Pack',
    'Spicy grilled chicken portions with house pepper sauce.',
    3800,
    'protein',
    'https://images.unsplash.com/photo-1598515214211-89d3c73ae83b?auto=format&fit=crop&w=900&q=80',
    true
  ),
  (
    '88888888-8888-8888-8888-888888888883',
    '77777777-7777-7777-7777-777777777771',
    'Ofada Sauce Bowl',
    'Local ofada sauce with rice, egg, and assorted beef.',
    5000,
    'rice',
    null,
    false
  ),
  (
    '88888888-8888-8888-8888-888888888884',
    '77777777-7777-7777-7777-777777777772',
    'Fresh Fruit Box',
    'Seasonal fruit selection packed for same-day delivery.',
    6500,
    'fresh produce',
    'https://images.unsplash.com/photo-1619566636858-adf3ef46400b?auto=format&fit=crop&w=900&q=80',
    true
  ),
  (
    '88888888-8888-8888-8888-888888888885',
    '77777777-7777-7777-7777-777777777772',
    'Breakfast Groceries',
    'Bread, eggs, milk, tea, and butter bundle.',
    7200,
    'grocery bundle',
    'https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=900&q=80',
    true
  ),
  (
    '88888888-8888-8888-8888-888888888886',
    '77777777-7777-7777-7777-777777777772',
    'Yam Tubers Pack',
    'Clean medium yam tubers from the morning market.',
    9000,
    'fresh produce',
    null,
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
  ('88888888-8888-8888-8888-888888888881', 'DEMO-KITCHEN-JOLLOF', 30, 8),
  ('88888888-8888-8888-8888-888888888882', 'DEMO-KITCHEN-CHICKEN', 18, 6),
  ('88888888-8888-8888-8888-888888888883', 'DEMO-KITCHEN-OFADA', 12, 4),
  ('88888888-8888-8888-8888-888888888884', 'DEMO-MARKET-FRUIT', 22, 5),
  ('88888888-8888-8888-8888-888888888885', 'DEMO-MARKET-BREAKFAST', 15, 5),
  ('88888888-8888-8888-8888-888888888886', 'DEMO-MARKET-YAM', 0, 5)
on conflict (product_id) do update
set sku = excluded.sku,
    quantity_on_hand = excluded.quantity_on_hand,
    reorder_level = excluded.reorder_level,
    updated_at = now();
