<?php

/**
 * Auto-create profiles from message To/Cc headers (Roundcube autocreate_identity equivalent).
 * @package modules
 * @subpackage autocreate_profile
 */

if (!defined('DEBUG_MODE')) { die(); }

require_once APP_PATH.'modules/profiles/hm-profiles.php';

/**
 * @subpackage autocreate_profile/handler
 */
class Hm_Handler_configure_mail_testing_imap_server extends Hm_Handler_Module {
    public function process() {
        list($success, $form) = $this->process_form(array('username', 'password'));
        if (!$success || !$this->module_is_supported('imap')) {
            return;
        }

        $server = $this->config->get('imap_auth_server', false);
        if (!$server) {
            return;
        }

        Hm_IMAP_List::init($this->user_config, $this->session);

        $imap_user = rtrim($form['username']);
        if (strpos($imap_user, '@') === false) {
            $domain = $this->config->get('default_email_domain');
            if ($domain) {
                $imap_user = $imap_user.'@'.$domain;
            }
        }

        $details = array(
            'name' => $this->config->get('imap_auth_name', $server),
            'default' => true,
            'server' => $server,
            'port' => $this->config->get('imap_auth_port', 143),
            'tls' => $this->config->get('imap_auth_tls', false),
            'user' => $imap_user,
            'pass' => $form['password'],
            'type' => 'imap',
        );

        $default_id = false;
        foreach (Hm_IMAP_List::getAll() as $id => $existing) {
            if (!empty($existing['default'])) {
                $default_id = $id;
            }
        }
        if (!$default_id) {
            Hm_IMAP_List::add($details);
        } else {
            Hm_IMAP_List::edit($default_id, $details);
        }
    }
}

/**
 * @subpackage autocreate_profile/handler
 */
class Hm_Handler_autocreate_profiles_from_headers extends Hm_Handler_Module {
    public function process() {
        if (!$this->module_is_supported('profiles')
            || !$this->module_is_supported('imap')
            || !$this->module_is_supported('smtp')) {
            return;
        }

        $msg_headers = $this->get('msg_headers');
        if (!$msg_headers || !is_array($msg_headers)) {
            return;
        }

        Hm_Profiles::init($this);

        $imap_servers = Hm_IMAP_List::dump();
        $smtp_servers = Hm_SMTP_List::dump();
        if (count($imap_servers) != 1 || count($smtp_servers) != 1) {
            return;
        }

        $imap_server = reset($imap_servers);
        $smtp_server = reset($smtp_servers);

        $existing_emails = array();
        foreach (Hm_Profiles::getAll() as $profile) {
            if (!empty($profile['address'])) {
                $existing_emails[] = strtolower($profile['address']);
            }
            if (!empty($profile['replyto'])) {
                $existing_emails[] = strtolower($profile['replyto']);
            }
        }

        $headers_lc = array();
        foreach ($msg_headers as $key => $val) {
            $headers_lc[strtolower($key)] = $val;
        }

        $recipients = array();
        foreach (array('to', 'cc') as $header) {
            if (empty($headers_lc[$header])) {
                continue;
            }
            foreach (process_address_fld($headers_lc[$header]) as $vals) {
                if (!empty($vals['email'])) {
                    $recipients[] = $vals;
                }
            }
        }

        foreach ($recipients as $recipient) {
            $email = strtolower($recipient['email']);
            if (in_array($email, $existing_emails, true)) {
                continue;
            }

            $name = trim($recipient['label'] ?? '');
            if (!$name) {
                $name = explode('@', $recipient['email'])[0];
            }

            Hm_Profiles::add(array(
                'default' => false,
                'name' => $name,
                'address' => $recipient['email'],
                'replyto' => $recipient['email'],
                'smtp_id' => $smtp_server['id'],
                'imap_id' => $imap_server['id'],
                'sig' => '',
                'rmk' => '',
                'type' => 'imap',
                'autocreate' => true,
                'user' => $imap_server['user'],
                'server' => $imap_server['server'],
            ));
            $existing_emails[] = $email;
        }
    }
}
