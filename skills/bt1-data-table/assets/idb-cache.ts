/**
 * Tiny IndexedDB key/value cache with per-entry TTL.
 *
 * Used by the optional stale-while-revalidate layer (see references/caching.md):
 * a table can show cached rows instantly on revisit while the remote function
 * refetches in the background. Every operation is best-effort — failures
 * resolve to `null` / no-op rather than throwing, so the cache can never break
 * the page.
 *
 * Rename `DB_NAME` per app to avoid collisions across projects on the same origin.
 */
const DB_NAME = 'app-query-cache'
const STORE = 'entries'
const DB_VERSION = 1

interface Entry<T> {
  data: T
  ts: number
  ttl: number
}

let _db: IDBDatabase | null = null

function openDb(): Promise<IDBDatabase> {
  if (_db) return Promise.resolve(_db)
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION)
    req.onupgradeneeded = () => req.result.createObjectStore(STORE)
    req.onsuccess = () => {
      _db = req.result
      resolve(_db)
    }
    req.onerror = () => reject(req.error)
  })
}

/** Returns the cached value, or `null` if missing / expired / unavailable. */
export async function idbGet<T>(key: string): Promise<T | null> {
  try {
    const db = await openDb()
    return new Promise(resolve => {
      const req = db.transaction(STORE, 'readonly').objectStore(STORE).get(key)
      req.onsuccess = () => {
        const entry = req.result as Entry<T> | undefined
        if (!entry || Date.now() > entry.ts + entry.ttl) return resolve(null)
        resolve(entry.data)
      }
      req.onerror = () => resolve(null)
    })
  } catch {
    return null
  }
}

/** Stores `data` under `key` with a time-to-live of `ttlMs`. Best-effort. */
export async function idbSet<T>(key: string, data: T, ttlMs: number): Promise<void> {
  try {
    const db = await openDb()
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(STORE, 'readwrite')
      tx.objectStore(STORE).put({ data, ts: Date.now(), ttl: ttlMs } satisfies Entry<T>, key)
      tx.oncomplete = () => resolve()
      tx.onerror = () => reject(tx.error)
    })
  } catch {
    // writes are best-effort
  }
}

/** Removes a single entry. Best-effort. */
export async function idbDelete(key: string): Promise<void> {
  try {
    const db = await openDb()
    await new Promise<void>(resolve => {
      const tx = db.transaction(STORE, 'readwrite')
      tx.objectStore(STORE).delete(key)
      tx.oncomplete = () => resolve()
      tx.onerror = () => resolve()
    })
  } catch {}
}
