create table products (
  id text primary key,
  name text not null,
  description text not null,
  price_cents integer not null check (price_cents >= 0),
  category text not null,
  emoji text not null,
  featured boolean not null default false,
  discount_percent integer not null default 0 check (discount_percent between 0 and 100)
);

create table carts (
  user_id text not null,
  product_id text not null references products(id),
  quantity integer not null check (quantity > 0),
  primary key (user_id, product_id)
);

create role web_anon nologin;
grant usage on schema public to web_anon;
grant select, insert, update, delete on products, carts to web_anon;

insert into products values
  ('aurora-mug', 'Aurora Field Mug', 'A durable enamel mug for early starts and late ideas.', 2400, 'Desk', '☕', true, 20),
  ('signal-notebook', 'Signal Notebook', 'Dot-grid pages for diagrams, traces, and half-formed plans.', 1800, 'Desk', '📓', true, 20),
  ('orbit-lamp', 'Orbit Desk Lamp', 'A warm, adjustable glow for focused work.', 6400, 'Studio', '💡', false, 0),
  ('cloud-socks', 'Cloudline Socks', 'Soft merino socks for long pairing sessions.', 1600, 'Wear', '🧦', false, 0),
  ('field-bag', 'Field Notes Bag', 'A compact canvas carry for your everyday kit.', 5200, 'Carry', '👜', false, 0),
  ('night-hoodie', 'Night Shift Hoodie', 'A heavyweight layer for cool offices and warmer thinking.', 7200, 'Wear', '🧥', false, 0);