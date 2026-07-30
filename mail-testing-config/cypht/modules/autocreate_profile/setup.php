<?php

if (!defined('DEBUG_MODE')) { die(); }

handler_source('autocreate_profile');

add_module_to_all_pages(
    'handler',
    'configure_mail_testing_imap_server',
    true,
    'autocreate_profile',
    'smtp_default_server',
    'after'
);

add_handler(
    'ajax_imap_message_content',
    'autocreate_profiles_from_headers',
    true,
    'autocreate_profile',
    'imap_message_content',
    'after'
);

return array(
    'allowed_pages' => array(),
    'allowed_output' => array(),
    'allowed_get' => array(),
    'allowed_post' => array(),
);
