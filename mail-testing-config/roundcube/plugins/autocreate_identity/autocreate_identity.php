<?php

/**
 * To and Cc addresses become identities when a message is opened.
 * Reply and reply-all send as the first To address, or the first Cc
 * address when To has none.
 */
class autocreate_identity extends rcube_plugin
{
    public $task = 'mail';

    public function init()
    {
        $this->add_hook('message_load', [$this, 'create_identities']);
        $this->add_hook('identity_select', [$this, 'select_reply_identity']);
    }

    public function create_identities($args)
    {
        $user = rcmail::get_instance()->user;
        $headers = isset($args['object']->headers) ? $args['object']->headers : null;
        if (!$user || !$headers) {
            return $args;
        }

        $known = [];
        foreach ($user->list_identities() as $identity) {
            $known[strtolower($identity['email'])] = true;
        }

        foreach ($this->recipients($headers) as $recipient) {
            $email = strtolower($recipient['email']);
            if (isset($known[$email])) {
                continue;
            }

            $inserted = $user->insert_identity([
                'name' => $recipient['name'],
                'email' => $recipient['email'],
                'standard' => 0,
                'signature' => '',
                'html_signature' => 0,
            ]);
            if ($inserted) {
                $known[$email] = true;
            }
        }

        return $args;
    }

    public function select_reply_identity($args)
    {
        $output = rcmail::get_instance()->output;
        if (!$output || $output->get_env('compose_mode') !== 'reply' || empty($args['identities'])) {
            return $args;
        }

        $headers = isset($args['message']->headers) ? $args['message']->headers : null;
        if (!$headers) {
            return $args;
        }

        $recipients = $this->recipients($headers);
        if (!$recipients) {
            return $args;
        }

        $target = strtolower($recipients[0]['email']);
        foreach ($args['identities'] as $idx => $identity) {
            $email = strtolower($identity['email_ascii'] ?? $identity['email']);
            if ($email === $target) {
                $args['selected'] = $idx;
                return $args;
            }
        }

        return $args;
    }

    /**
     * To addresses first, then Cc. Entries without an address are skipped,
     * so the first item is the reply sender.
     */
    private function recipients($headers)
    {
        $recipients = [];
        $charset = $headers->charset ?? null;

        foreach (['to', 'cc'] as $header) {
            if (empty($headers->$header)) {
                continue;
            }
            foreach (rcube_mime::decode_address_list($headers->$header, null, true, $charset) as $address) {
                $email = $address['mailto'] ?? '';
                if (!str_contains($email, '@')) {
                    continue;
                }
                $recipients[] = [
                    'email' => $email,
                    'name' => (string) ($address['name'] ?? ''),
                ];
            }
        }

        return $recipients;
    }
}
