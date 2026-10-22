// SPDX-License-Identifier: GPL-3.0-only
// Reads an App Store order for murmur Pro (ios/prd.json IOS-025): an iPhone
// buyer sends the order id from Apple's receipt, and LaBroi confirms it with
// Apple before issuing a desktop key. Apple's Look Up Order ID, checked
// 2026-10-22: a JWT signed ES256 with an In-App Purchase key, and an answer
// of { status, signedTransactions } whose payloads name the bundle id,
// product id, purchase date, and any refund.
const { createPrivateKey, sign } = require('node:crypto')

const b64 = (value) => Buffer.from(typeof value === 'string' ? value : JSON.stringify(value)).toString('base64url')

/** The bearer token for the App Store Server API, good for 20 minutes. */
function serverToken({ keyPem, keyId, issuer, bundleId, now = Math.floor(Date.now() / 1000) }) {
  const head = b64({ alg: 'ES256', kid: keyId, typ: 'JWT' })
  const body = b64({ iss: issuer, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1', bid: bundleId })
  const key = createPrivateKey(keyPem)
  const sig = sign('sha256', Buffer.from(`${head}.${body}`), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url')
  return `${head}.${body}.${sig}`
}

/** A signed transaction's payload, or null when it cannot be read. The
 *  answer came from Apple over TLS on our own key, so the payload is read
 *  without checking Apple's certificate chain. */
function payloadOf(signed) {
  const part = typeof signed === 'string' ? signed.split('.')[1] : undefined
  if (!part) return null
  try {
    const payload = JSON.parse(Buffer.from(part, 'base64url').toString('utf8'))
    return payload && typeof payload === 'object' ? payload : null
  } catch {
    return null
  }
}

/** Whether an order holds murmur Pro, still paid for, in plain words. */
function orderVerdict(answer, { bundleId, productId }) {
  if (!answer || answer.status !== 0) {
    return { confirmed: false, reason: 'Apple says this is not an order id it knows. Ask the buyer for the order id on their App Store receipt.' }
  }
  const signed = Array.isArray(answer.signedTransactions) ? answer.signedTransactions : []
  if (signed.length === 0) return { confirmed: false, reason: 'Apple found the order, but it holds no purchases.' }
  const payloads = signed.map(payloadOf)
  const ours = payloads.filter((p) => p && p.bundleId === bundleId && p.productId === productId)
  const paid = ours.find((p) => !p.revocationDate)
  if (paid) {
    const purchased = new Date(Number(paid.purchaseDate)).toISOString().slice(0, 10)
    return { confirmed: true, reason: `murmur Pro, bought ${purchased}, not refunded.`, purchased, transactionId: String(paid.transactionId) }
  }
  if (ours.length > 0) return { confirmed: false, reason: 'murmur Pro was bought in this order, then refunded.' }
  if (payloads.every((p) => p === null)) return { confirmed: false, reason: 'Apple answered, but its purchases could not be read.' }
  return { confirmed: false, reason: 'This order holds no murmur Pro purchase.' }
}

module.exports = { orderVerdict, serverToken }
