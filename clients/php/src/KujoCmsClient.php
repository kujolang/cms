<?php
declare(strict_types=1);

namespace Kujo\Cms;

final class KujoCmsClient
{
    public function __construct(private readonly string $baseUrl, private readonly string $token = '', private readonly string $session = '', private readonly ?\Closure $transport = null) {}

    public function request(string $method, string $path, ?array $body = null): mixed
    {
        $headers = ['Accept: application/json'];
        if ($this->token !== '') $headers[] = 'Authorization: Bearer '.$this->token;
        if ($this->session !== '') $headers[] = 'X-CMS-Session: '.$this->session;
        if ($body !== null) $headers[] = 'Content-Type: application/json';
        [$status, $text] = $this->transport ? ($this->transport)($method, rtrim($this->baseUrl, '/').$path, $headers, $body) : $this->curl($method, rtrim($this->baseUrl, '/').$path, $headers, $body);
        $payload = $text === '' ? null : json_decode($text, true, flags: JSON_THROW_ON_ERROR);
        if ($status < 200 || $status >= 300 || ($payload['ok'] ?? true) === false) {
            $error = $payload['error'] ?? [];
            throw new KujoCmsException($error['message'] ?? "CMS request failed with HTTP {$status}", $status, $error['code'] ?? 'request_failed', $error['details'] ?? []);
        }
        return is_array($payload) && array_key_exists('data', $payload) ? $payload['data'] : $payload;
    }

    private function curl(string $method, string $url, array $headers, ?array $body): array
    {
        $handle = curl_init($url);
        curl_setopt_array($handle, [CURLOPT_CUSTOMREQUEST => $method, CURLOPT_HTTPHEADER => $headers, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 30]);
        if ($body !== null) curl_setopt($handle, CURLOPT_POSTFIELDS, json_encode($body, JSON_THROW_ON_ERROR));
        $text = curl_exec($handle);
        if ($text === false) throw new KujoCmsException(curl_error($handle), 0, 'transport_error');
        return [curl_getinfo($handle, CURLINFO_RESPONSE_CODE), $text];
    }

    public function createSession(array $input): mixed { return $this->request('POST', '/v1/auth/sessions', $input); }
    public function exchangeProvider(array $input): mixed { return $this->request('POST', '/v1/auth/providers/exchange', $input); }
    public function me(): mixed { return $this->request('GET', '/v1/auth/me'); }
    public function createEntry(array $entry, array $termIds = []): mixed { return $this->request('POST', '/v1/entries', array_merge($entry, ['term_ids' => $termIds])); }
    public function composeEntry(int $id, array $workflow): mixed { return $this->request('PATCH', "/v1/entries/{$id}/compose", $workflow); }
    public function bulkTerms(int $taxonomyId, array $terms): mixed { return $this->request('POST', "/v1/taxonomies/{$taxonomyId}/terms/bulk", ['terms' => $terms]); }
    public function seoInventory(array $query = []): mixed { return $this->request('GET', '/v1/seo/entries?'.http_build_query($query)); }
    public function updateEntrySeo(int $id, array $changes): mixed { return $this->request('PATCH', "/v1/entries/{$id}/seo", $changes); }
    public function socialSharing(): mixed { return $this->request('GET', '/v1/settings/social-sharing'); }
    public function updateSocialSharing(array $settings): mixed { return $this->request('PATCH', '/v1/settings/social-sharing', $settings); }
    public function extensionNavigation(): mixed { return $this->request('GET', '/v1/extensions/navigation'); }
    public function ingestExtension(string $filename, bool $activate = false): mixed { return $this->request('POST', '/v1/extensions/packages/ingest', compact('filename', 'activate')); }
    public function uploadExtension(string $dataBase64, bool $activate = false): mixed { return $this->request('POST', '/v1/extensions/packages/upload', ['data_base64' => $dataBase64, 'activate' => $activate]); }
    public function abilityDefinitions(): mixed { return $this->request('GET', '/v1/abilities/definitions'); }
    public function runAbility(string $name, array $input = []): mixed { [$namespace, $ability] = explode('/', $name, 2); return $this->request('POST', "/v1/abilities/{$namespace}/{$ability}/run", compact('input')); }
    public function connectorHealth(string $key): mixed { return $this->request('POST', '/v1/ai/connectors/'.rawurlencode($key).'/health', []); }
    public function ingestMedia(string $filename, string $altText = ''): mixed { return $this->request('POST', '/v1/media/ingest', ['filename' => $filename, 'alt_text' => $altText]); }
    public function uploadMedia(string $filename, string $dataBase64, string $altText = ''): mixed { return $this->request('POST', '/v1/media/upload', ['filename' => $filename, 'data_base64' => $dataBase64, 'alt_text' => $altText]); }
    public function mediaFile(string $objectKey): mixed { return $this->request('GET', '/v1/media/files/'.rawurlencode($objectKey)); }
    public function registerExternalMedia(array $input): mixed { return $this->request('POST', '/v1/media/register-external', $input); }

    public static function shareUrl(string $network, array $input): string
    {
        $url = (string)($input['url'] ?? ''); if ($url === '') throw new \InvalidArgumentException('url is required');
        $title = (string)($input['title'] ?? ''); $text = (string)($input['text'] ?? $title); $account = ltrim((string)($input['account'] ?? ''), '@'); $media = (string)($input['media'] ?? '');
        $query = static fn(string $base, array $values): string => $base.'?'.http_build_query(array_filter($values, static fn($value) => $value !== ''));
        return match ($network) {
            'x' => $query('https://x.com/intent/post', ['url' => $url, 'text' => $text, 'via' => $account]),
            'bluesky' => $query('https://bsky.app/intent/compose', ['text' => trim("{$text} {$url} ".($account ? "@{$account}" : ''))]),
            'linkedin' => $query('https://www.linkedin.com/sharing/share-offsite/', ['url' => $url]),
            'facebook' => $query('https://www.facebook.com/sharer/sharer.php', ['u' => $url]),
            'reddit' => $query('https://www.reddit.com/submit', ['url' => $url, 'title' => $title]),
            'whatsapp' => $query('https://wa.me/', ['text' => trim("{$text} {$url}")]),
            'pinterest' => $query('https://www.pinterest.com/pin/create/button/', ['url' => $url, 'description' => $text, 'media' => $media]),
            'email' => $query('mailto:', ['subject' => $title, 'body' => trim("{$text}\n\n{$url}")]),
            default => throw new \InvalidArgumentException("Unsupported sharing network: {$network}"),
        };
    }

    public static function resolveNavigation(array $core, array $extensions, array $capabilities): array
    {
        $allowed = array_fill_keys($capabilities, true); $items = [];
        foreach ($core as $item) $items[$item['key']] = $item;
        foreach ($extensions as $item) { if (($item['capability'] ?? '') !== '' && !isset($allowed['*']) && !isset($allowed[$item['capability']])) continue; $items[$item['key']] = isset($items[$item['key']]) ? array_replace($items[$item['key']], ['order' => $item['order'] ?? 500]) : $item; }
        $items = array_values(array_filter($items, static fn($item) => ($item['capability'] ?? '') === '' || isset($allowed['*']) || isset($allowed[$item['capability']])));
        usort($items, static fn($a, $b) => (($a['order'] ?? 500) <=> ($b['order'] ?? 500)) ?: strcmp((string)($a['label'] ?? ''), (string)($b['label'] ?? '')));
        return $items;
    }
}
