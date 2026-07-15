# CF-QUIC-Bridge: Cloudflare & QUIC.cloud Integration Toolkit

A lightweight toolkit to seamlessly integrate Cloudflare CDN with QUIC.cloud and LiteSpeed Cache for WordPress.

When routing traffic through Cloudflare to a QUIC.cloud/LiteSpeed server, you often encounter two main issues: Cloudflare blocking QUIC.cloud node IPs, and WordPress logging Cloudflare's proxy IPs instead of the real visitor's IP. This repository solves both problems.

## 📂 Repository Index

This project is divided into two independent parts. You can use one or both depending on your server setup.

Click the links below to view the detailed instructions and setup guides for each tool:

### 1. 🛡️ [QUIC.cloud IP Allowlist Script](./quickcloud-wishlist/README.md "null")

**Location:** `/quickcloud-wishlist/`

An automated bash script that fetches the latest QUIC.cloud server IP addresses and allowlists them in your Cloudflare Firewall. This ensures your caching nodes are never blocked by Cloudflare's security measures.

- 📖 [**Read the Setup Guide & Instructions here ➔**](./quickcloud-wishlist/README.md "null")
    

### 2. 🌐 [Cloudflare Real IP Restore (WordPress)](./mu-plugins/README.md "null")

**Location:** `/mu-plugins/`

A Must-Use (MU) WordPress plugin that restores the real visitor IP address when your site is proxied through Cloudflare. This is critical for analytics, security plugins, and LiteSpeed Cache to function correctly.

- 📖 [**Read the Installation Instructions here ➔**](./mu-plugins/README.md "null")
    

**Author:** Harshal Machhi

**Version:** 1.0