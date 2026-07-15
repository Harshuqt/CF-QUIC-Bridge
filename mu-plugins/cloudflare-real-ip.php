<?php
/**
 * Plugin Name: Cloudflare Real IP Restore
 * Description: Automatically restores real visitor IP from Cloudflare for QUIC.cloud compatibility
 * Version: 1.0
 * Author: Harshal Machhi
 */

// Restore real IP from Cloudflare
if (isset($_SERVER['HTTP_CF_CONNECTING_IP'])) {
    $_SERVER['REMOTE_ADDR'] = $_SERVER['HTTP_CF_CONNECTING_IP'];
}

// Also set for X-Forwarded-For if needed
if (isset($_SERVER['HTTP_X_FORWARDED_FOR'])) {
    $forwarded = explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']);
    if (!isset($_SERVER['HTTP_CF_CONNECTING_IP'])) {
        $_SERVER['REMOTE_ADDR'] = trim($forwarded[0]);
    }
}