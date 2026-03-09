'use strict';

function validateRegistryUrl(registry) {
  if (!registry) return null;
  try {
    const u = new URL(registry);
    if (!/^https?:$/.test(u.protocol)) return null;
    return u.toString().replace(/\/$/, '');
  } catch (_) {
    return null;
  }
}

module.exports = { validateRegistryUrl };

