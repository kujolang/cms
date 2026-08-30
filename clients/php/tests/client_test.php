<?php
declare(strict_types=1);

require __DIR__.'/../src/KujoCmsException.php';
require __DIR__.'/../src/KujoCmsClient.php';

use Kujo\Cms\KujoCmsClient;

$transport = static fn(string $method, string $url, array $headers, ?array $body): array => [200, '{"ok":true,"data":{"method":"'.$method.'"}}'];
$client = new KujoCmsClient('https://cms.test', transport: $transport(...));
assert($client->me()['method'] === 'GET');
foreach (['x','linkedin','facebook','bluesky','reddit','whatsapp','email','pinterest'] as $network) assert(str_contains(KujoCmsClient::shareUrl($network, ['url' => 'https://example.test/post', 'title' => 'Hello']), 'example'));
$navigation = KujoCmsClient::resolveNavigation([['key'=>'content','label'=>'Content','order'=>200,'capability'=>'view_content']], [['key'=>'content','order'=>100,'capability'=>'view_content'],['key'=>'forms','label'=>'Forms','order'=>150,'capability'=>'manage_extensions']], ['view_content']);
assert(array_column($navigation, 'key') === ['content']);
echo "PHP client tests passed\n";
