<?php

class autocreate_identity extends rcube_plugin
{
    public $task = 'mail';

    function init()
    {
        $this->add_hook('message_load', array($this, 'create_identity_from_message'));
    }

    function create_identity_from_message($args)
    {
        // Only process if we have headers and it's a message object
        if (!isset($args['object']) || !isset($args['object']->headers)) {
            return $args;
        }

        $rcmail = rcmail::get_instance();
        $user = $rcmail->user;

        // Get existing identities
        $existing_emails = array();
        foreach ($user->list_identities() as $identity) {
            $existing_emails[] = strtolower($identity['email']);
        }

        // Get To and Cc addresses
        $recipients = array();
        if (!empty($args['object']->headers->to)) {
            $recipients = array_merge($recipients, rcube_mime::decode_address_list($args['object']->headers->to));
        }
        if (!empty($args['object']->headers->cc)) {
            $recipients = array_merge($recipients, rcube_mime::decode_address_list($args['object']->headers->cc));
        }

        foreach ($recipients as $recipient) {
            $email = $recipient['mailto'];
            if (!in_array(strtolower($email), $existing_emails)) {
                $user->insert_identity(array(
                    'name' => $recipient['name'] ?: '',
                    'email' => $email,
                    'standard' => 0,
                    'signature' => '',
                    'html_signature' => 0
                ));
                $existing_emails[] = strtolower($email);
            }
        }

        return $args;
    }
}
