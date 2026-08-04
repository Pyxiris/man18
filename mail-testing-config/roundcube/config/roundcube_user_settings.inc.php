<?php
// Always use HTML editor
$config['htmleditor'] = 1;

// Reply above the quote
$config['reply_mode'] = 1;

// Turn off SMTP authentication: Roundcube sends on the inbound mailgate
// port (13525), allowed via docker-mailserver mynetworks.
// Unfortunately, we cannot set this via environment variables. See:
// https://github.com/roundcube/roundcubemail-docker/blob/9fd84b3e4f7943c7b2046d0a443a39d1a702edf2/fpm/docker-entrypoint.sh#L177-#L188
$config['smtp_user'] = '';
$config['smtp_pass'] = '';

$config['default_list_mode'] = 'threads';
$config['autoexpand_threads'] = 0;  // or 2 for unread only
$config['imap_force_caps'] = true;  // Dovecot advertises THREAD only after login
