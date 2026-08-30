<?php
declare(strict_types=1);

namespace Kujo\Cms;

final class KujoCmsException extends \RuntimeException
{
    public function __construct(string $message, public readonly int $status = 0, public readonly string $errorCode = 'request_failed', public readonly array $details = [])
    {
        parent::__construct($message);
    }
}
