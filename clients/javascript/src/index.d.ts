export interface ClientOptions { baseUrl: string; token?: string; session?: string; fetchImpl?: typeof fetch }
export class KujoCmsError extends Error { status: number; code: string; details: Record<string, unknown> }
export class KujoCmsClient {
  constructor(options: ClientOptions); withAuth(auth?: {token?: string; session?: string}): KujoCmsClient; request(method: string, path: string, body?: unknown): Promise<any>;
  createSession(input: unknown): Promise<any>; exchangeProvider(input: unknown): Promise<any>; me(): Promise<any>; revokeSession(): Promise<any>;
  listEntries(query?: Record<string,string>): Promise<any>; getEntry(id: string|number): Promise<any>; createEntry(entry: Record<string, unknown>, termIds?: number[]): Promise<any>; composeEntry(id: string|number, workflow: unknown): Promise<any>; bulkTerms(id: string|number, terms: unknown[]): Promise<any>;
  ingestMedia(filename: string, altText?: string): Promise<any>; uploadMedia(filename: string, dataBase64: string, altText?: string): Promise<any>; mediaFile(objectKey: string): Promise<any>; registerExternalMedia(input: unknown): Promise<any>; seoInventory(query?: Record<string,string>): Promise<any>; updateEntrySeo(id: string|number, changes: unknown): Promise<any>; bulkUpdateSeo(ids: number[], changes: unknown): Promise<any>;
  socialSharing(): Promise<any>; updateSocialSharing(settings: unknown): Promise<any>; extensionCatalog(): Promise<any>; extensionNavigation(): Promise<any>; ingestExtension(filename: string, activate?: boolean): Promise<any>; uploadExtension(dataBase64: string, activate?: boolean): Promise<any>;
  abilities(category?: string): Promise<any>; runAbility(name: string, input?: unknown): Promise<any>; setAbility(name: string, enabled: boolean): Promise<any>; connectors(): Promise<any>; setConnector(key: string, enabled: boolean): Promise<any>; connectorHealth(key: string): Promise<any>; mcpTools(): Promise<any>; webMcpManifest(): Promise<any>;
}
export function buildShareUrl(network: string, input: {url: string; title?: string; text?: string; account?: string; media?: string}): string;
export function resolveAdminNavigation(coreItems?: any[], extensionItems?: any[], capabilities?: string[]): any[];
