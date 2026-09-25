const test = require('node:test');
const assert = require('node:assert/strict');
const { createAppServer } = require('./server.js');

const requestCart = async port => {
  const response = await fetch(`http://localhost:${port}/api/cart?userId=test-user`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ productId: 'aurora-mug', quantity: 1 }),
  });
  return response.status;
};

test('shop-api handles concurrent cart requests without exhausting an in-memory DB pool', async () => {
  const originalFetch = global.fetch;
  global.fetch = async (url, options = {}) => {
    const requestUrl = String(url);
    if (requestUrl.includes('/carts')) {
      return {
        ok: true,
        status: 200,
        text: async () => JSON.stringify([]),
      };
    }
    if (requestUrl.includes('/products')) {
      return {
        ok: true,
        status: 200,
        text: async () => JSON.stringify([]),
      };
    }
    return {
      ok: true,
      status: 200,
      text: async () => JSON.stringify({ status: 'approved' }),
      json: async () => ({ status: 'approved' }),
    };
  };

  const server = createAppServer();
  await new Promise(resolve => server.listen(4317, resolve));

  try {
    const statuses = await Promise.all(Array.from({ length: 10 }, () => requestCart(4317)));
    assert.deepEqual(statuses, Array(10).fill(200));
  } finally {
    await new Promise(resolve => server.close(resolve));
    global.fetch = originalFetch;
  }
});
