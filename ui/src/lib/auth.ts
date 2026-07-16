const TOKEN_KEY = 'badsector_token'

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY)
}

export function setToken(token: string): void {
  localStorage.setItem(TOKEN_KEY, token)
}

export function clearToken(): void {
  localStorage.removeItem(TOKEN_KEY)
}

export function authHeaders(): Record<string, string> {
  const token = getToken()
  if (!token) return {}
  return { Authorization: `Bearer ${token}` }
}

const UNAUTHORIZED_EVENT = 'badsector:unauthorized'

// Fired by the API client on a 401 so the app can drop back to the login screen.
export function notifyUnauthorized(): void {
  window.dispatchEvent(new Event(UNAUTHORIZED_EVENT))
}

export function onUnauthorized(cb: () => void): () => void {
  window.addEventListener(UNAUTHORIZED_EVENT, cb)
  return () => window.removeEventListener(UNAUTHORIZED_EVENT, cb)
}
