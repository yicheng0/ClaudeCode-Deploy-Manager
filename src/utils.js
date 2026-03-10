'use strict';

function normalizeApiBaseUrl(url) {
  if (!url) return null;
  try {
    const u = new URL(url);
    if (!/^https?:$/.test(u.protocol)) return null;

    let pathname = (u.pathname || '').replace(/\/+$/, '');
    if (/\/v1\/messages$/i.test(pathname)) {
      pathname = pathname.replace(/\/v1\/messages$/i, '');
    } else if (/\/v1$/i.test(pathname)) {
      pathname = pathname.replace(/\/v1$/i, '');
    }

    const normalized = `${u.protocol}//${u.host}${pathname}`.replace(/\/+$/, '');
    return normalized;
  } catch (_) {
    return null;
  }
}

function buildAnthropicMessagesUrl(url) {
  const normalized = normalizeApiBaseUrl(url);
  return normalized ? `${normalized}/v1/messages` : null;
}

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

module.exports = { validateRegistryUrl, normalizeApiBaseUrl, buildAnthropicMessagesUrl };
