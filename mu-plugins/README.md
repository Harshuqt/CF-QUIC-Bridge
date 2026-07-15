# **Cloudflare Real IP Restore**

A lightweight, essential WordPress Must-Use (MU) plugin that automatically restores the real visitor IP address when your site is proxied through Cloudflare.

This is especially critical for ensuring seamless compatibility with caching and security services like **QUIC.cloud**, LiteSpeed Cache, popular security plugins, and server analytics.

**Author:** Harshal Machhi

**Version:** 1.0

## **⚠️ Why a "Must-Use" (MU) Plugin?**

For this code to work properly, it **must** be installed as an MU-Plugin (`mu-plugins`), rather than a standard WordPress plugin.

**Here is why:**

Standard WordPress plugins load *after* WordPress core has initialized. By the time a standard plugin runs, security tools, caching plugins, and analytics might have already logged Cloudflare's server IP instead of the user's real IP.

By placing this code in the `mu-plugins` directory, WordPress is forced to execute it **first**—before any other standard plugins or themes are loaded. This ensures that the real visitor IP is successfully overwritten globally and is available to every other system on your site from the very beginning of the page load.

## **🚀 Installation Instructions**

Because this is a Must-Use plugin, you will not install it through the standard WordPress dashboard installer. Follow these simple steps via FTP or your hosting File Manager:

1. **Download the plugin file:** Download the `cloudflare-real-ip.php` file from this GitHub repository.  
2. **Access your website files** using FTP, SFTP, or your web host's File Manager (like cPanel or Plesk).  
3. **Navigate to the `wp-content` directory** of your WordPress installation.  
4. **Find or create the `mu-plugins` folder:** Look for a folder named `mu-plugins`.  
   * *Note: If the `mu-plugins` folder does not exist, simply create a new folder and name it exactly `mu-plugins`.*  
5. **Upload the file:** Upload the `cloudflare-real-ip.php` file you downloaded in Step 1 directly into the `mu-plugins` folder.

### **Activation**

You're done\! **There is no need to activate this plugin from the WordPress dashboard.**

WordPress automatically executes all PHP files placed directly inside the `mu-plugins` directory. You can verify it is active by going to your WordPress Dashboard \> Plugins \> Must-Use.

## **⚙️ How It Works**

When traffic passes through Cloudflare, the `REMOTE_ADDR` variable is changed to Cloudflare's proxy IP. However, Cloudflare passes the true visitor IP in a special HTTP header.

This script:

1. Checks for the `HTTP_CF_CONNECTING_IP` header (Cloudflare's default header for passing the real IP).  
2. Checks for `HTTP_X_FORWARDED_FOR` as a fallback.  
3. Overwrites the PHP `$_SERVER['REMOTE_ADDR']` variable with the real IP address, tricking WordPress and all subsequent plugins into reading the correct visitor IP.