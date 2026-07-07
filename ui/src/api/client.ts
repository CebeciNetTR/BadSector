import type { ManagedWafResponse } from '../types/managedWaf'
import type { RateLimitResponse } from '../types/rateLimit'
import type { Policy, PolicyPayload } from '../types/policy'
import type { PipelineStagePayload } from '../types/pipeline'
import type { PipelineStage, Site, SiteDetail, SitePayload } from '../types/site'
import type { ModuleStageResponse } from '../types/securityModules'
import { authHeaders } from '../lib/auth'

const BASE = import.meta.env.VITE_API_URL ?? '/api/v1'

export interface LoginResponse {
  token: string
  expires_at: string
  role: string
}

export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
  ) {
    super(message)
    this.name = 'ApiError'
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    headers: {
      'Content-Type': 'application/json',
      ...authHeaders(),
      ...init?.headers,
    },
    ...init,
  })

  if (!res.ok) {
    let message = res.statusText
    try {
      const body = await res.json()
      message = body.message ?? body.error ?? message
    } catch {
      // ignore
    }
    throw new ApiError(message, res.status)
  }

  if (res.status === 204) return undefined as T
  return res.json()
}

export const api = {
  login: (username: string, password: string) =>
    request<LoginResponse>('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ username, password }),
    }),

  listSites: () => request<Site[]>('/sites'),

  getSite: (id: string) => request<SiteDetail>(`/sites/${id}`),

  createSite: (body: SitePayload) =>
    request<Site>('/sites', { method: 'POST', body: JSON.stringify(body) }),

  updateSite: (id: string, body: SitePayload) =>
    request<Site>(`/sites/${id}`, { method: 'PUT', body: JSON.stringify(body) }),

  deleteSite: (id: string) =>
    request<void>(`/sites/${id}`, { method: 'DELETE' }),

  getPipeline: (siteId: string) =>
    request<PipelineStage[]>(`/sites/${siteId}/pipeline`),

  updatePipeline: (siteId: string, stages: PipelineStagePayload[]) =>
    request<PipelineStage[]>(`/sites/${siteId}/pipeline`, {
      method: 'PUT',
      body: JSON.stringify(stages),
    }),

  listPolicies: (siteId: string) =>
    request<Policy[]>(`/sites/${siteId}/policies`),

  createPolicy: (siteId: string, body: PolicyPayload) =>
    request<Policy>(`/sites/${siteId}/policies`, {
      method: 'POST',
      body: JSON.stringify(body),
    }),

  updatePolicy: (siteId: string, policyId: string, body: PolicyPayload) =>
    request<Policy>(`/sites/${siteId}/policies/${policyId}`, {
      method: 'PUT',
      body: JSON.stringify(body),
    }),

  deletePolicy: (siteId: string, policyId: string) =>
    request<void>(`/sites/${siteId}/policies/${policyId}`, { method: 'DELETE' }),

  getRateLimits: (siteId: string) =>
    request<RateLimitResponse>(`/sites/${siteId}/rate-limits`),

  saveRateLimits: (siteId: string, body: RateLimitResponse) =>
    request<RateLimitResponse>(`/sites/${siteId}/rate-limits`, {
      method: 'PUT',
      body: JSON.stringify(body),
    }),

  getManagedWaf: (siteId: string) =>
    request<ManagedWafResponse>(`/sites/${siteId}/managed-waf`),

  saveManagedWaf: (siteId: string, body: ManagedWafResponse) =>
    request<ManagedWafResponse>(`/sites/${siteId}/managed-waf`, {
      method: 'PUT',
      body: JSON.stringify(body),
    }),

  reloadRuntime: () =>
    request<{ status: string }>('/runtime/reload', { method: 'POST' }),

  listTraces: (siteId: string, limit = 50) =>
    request<RequestTrace[]>(`/sites/${siteId}/traces?limit=${limit}`),

  getDashboardMetrics: () =>
    request<import('../types/metrics').DashboardMetrics>('/metrics/dashboard'),

  getGeoipStatus: () => request<import('../types/securityModules').GeoipStatus>('/geoip/status'),

  getGeoip: (siteId: string) => request<ModuleStageResponse>(`/sites/${siteId}/geoip`),
  saveGeoip: (siteId: string, body: ModuleStageResponse) =>
    request<ModuleStageResponse>(`/sites/${siteId}/geoip`, { method: 'PUT', body: JSON.stringify(body) }),

  getAsn: (siteId: string) => request<ModuleStageResponse>(`/sites/${siteId}/asn`),
  saveAsn: (siteId: string, body: ModuleStageResponse) =>
    request<ModuleStageResponse>(`/sites/${siteId}/asn`, { method: 'PUT', body: JSON.stringify(body) }),

  getHeaderValidation: (siteId: string) =>
    request<ModuleStageResponse>(`/sites/${siteId}/header-validation`),
  saveHeaderValidation: (siteId: string, body: ModuleStageResponse) =>
    request<ModuleStageResponse>(`/sites/${siteId}/header-validation`, {
      method: 'PUT',
      body: JSON.stringify(body),
    }),

  getBurstDetection: (siteId: string) =>
    request<ModuleStageResponse>(`/sites/${siteId}/burst-detection`),
  saveBurstDetection: (siteId: string, body: ModuleStageResponse) =>
    request<ModuleStageResponse>(`/sites/${siteId}/burst-detection`, {
      method: 'PUT',
      body: JSON.stringify(body),
    }),

  getJsChallenge: (siteId: string) =>
    request<ModuleStageResponse>(`/sites/${siteId}/js-challenge`),
  saveJsChallenge: (siteId: string, body: ModuleStageResponse) =>
    request<ModuleStageResponse>(`/sites/${siteId}/js-challenge`, {
      method: 'PUT',
      body: JSON.stringify(body),
    }),

  getCookieChallenge: (siteId: string) =>
    request<ModuleStageResponse>(`/sites/${siteId}/cookie-challenge`),
  saveCookieChallenge: (siteId: string, body: ModuleStageResponse) =>
    request<ModuleStageResponse>(`/sites/${siteId}/cookie-challenge`, {
      method: 'PUT',
      body: JSON.stringify(body),
    }),

  getCustomRules: (siteId: string) => request<ModuleStageResponse>(`/sites/${siteId}/custom-rules`),
  saveCustomRules: (siteId: string, body: ModuleStageResponse) =>
    request<ModuleStageResponse>(`/sites/${siteId}/custom-rules`, {
      method: 'PUT',
      body: JSON.stringify(body),
    }),

  listCertificates: () => request<import('../types/securityModules').CertificateRecord[]>('/certificates'),
  listSiteCertificates: (siteId: string) =>
    request<import('../types/securityModules').CertificateRecord[]>(`/sites/${siteId}/certificates`),
  createCertificate: (
    siteId: string,
    body: { domain: string; email?: string; auto_renew?: boolean; issue?: boolean },
  ) =>
    request<import('../types/securityModules').CertificateRecord>(`/sites/${siteId}/certificates`, {
      method: 'POST',
      body: JSON.stringify(body),
    }),
  issueCertificate: (certId: string) =>
    request<import('../types/securityModules').CertificateRecord>(`/certificates/${certId}/issue`, {
      method: 'POST',
    }),
  renewCertificate: (certId: string) =>
    request<import('../types/securityModules').CertificateRecord>(`/certificates/${certId}/renew`, {
      method: 'POST',
    }),
  deleteCertificate: (certId: string) =>
    request<void>(`/certificates/${certId}`, { method: 'DELETE' }),
}
