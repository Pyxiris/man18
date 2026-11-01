<?php

/**
 * Sign in to the local devel mailbox whenever Roundcube has no session.
 *
 * Adapted from Roundcube's sample autologon plugin. The sample only runs
 * from 127.0.0.1 with ?_autologin=1 and fixed sample credentials, which
 * never matches this container. Credentials default to the devel mailbox
 * and can be overridden with MAILBOX_USER, MAILBOX_DOMAIN, and ADMIN_PASSWORD.
 */
class devel_autologon extends rcube_plugin
{
    public $task = 'login';

    public function init()
    {
        $this->add_hook('startup', [$this, 'startup']);
        $this->add_hook('authenticate', [$this, 'authenticate']);
    }

    /**
     * Turn an anonymous request into a login so the form is never shown.
     * A live session, including logout, is left alone; the next request logs in.
     */
    public function startup($args)
    {
        if (empty($_SESSION['user_id'])) {
            $args['task'] = 'login';
            $args['action'] = 'login';
        }

        return $args;
    }

    /**
     * Supply the devel mailbox. valid skips the CSRF token the login form
     * would have posted; cookiecheck is skipped because this request has
     * not received a session cookie yet.
     */
    public function authenticate($args)
    {
        $user = getenv('MAILBOX_USER') ?: 'admin';
        $domain = getenv('MAILBOX_DOMAIN') ?: 'mailserver';
        $password = getenv('ADMIN_PASSWORD') ?: 'admin';

        $args['user'] = $user . '@' . $domain;
        $args['pass'] = $password;
        $args['cookiecheck'] = false;
        $args['valid'] = true;

        return $args;
    }
}
