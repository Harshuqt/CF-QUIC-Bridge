#!/bin/bash

#####################################################################
# QUIC.cloud Cloudflare IP Whitelisting Script (Enhanced)
# Supports: API Tokens (Bearer) & Global API Keys
# Multi-zone support with configuration from secrets.env
#####################################################################


# --- CONFIGURATION ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="$SCRIPT_DIR/secrets.env"
LOG_FILE="$SCRIPT_DIR/cloudflare_quic_whitelist.log"
QUIC_CLOUD_IPS_URL="https://quic.cloud/ips?json"

# --- CHECK DEPENDENCIES ---
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Attempting to install jq..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y jq
    elif command -v yum &> /dev/null; then
        sudo yum install -y jq
    else
        echo "Error: Package manager not found. Please install jq manually."
        exit 1
    fi
fi

if ! command -v curl &> /dev/null; then
    echo "Error: curl is required but not installed."
    exit 1
fi

# --- LOGGING FUNCTION ---
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- LOAD CONFIGURATION ---
load_config() {
    if [ ! -f "$SECRETS_FILE" ]; then
        echo "ERROR: secrets.env file not found at $SECRETS_FILE"
        echo "Please create secrets.env with the following format:"
        echo ""
        echo "CF_EMAIL=\"your-email@example.com\""
        echo "CF_KEY=\"your-api-token-or-global-key\""
        echo "ZONE_IDS=\"zone_id_1 zone_id_2 zone_id_3\""
        echo "AUTH_TYPE=\"token\"  # or \"key\" for Global API Key"
        exit 1
    fi
    
    source "$SECRETS_FILE"
    
    # Validate required variables
    if [ -z "$CF_EMAIL" ] || [ -z "$CF_KEY" ] || [ -z "$ZONE_IDS" ]; then
        log_message "ERROR: Missing required variables in secrets.env"
        exit 1
    fi
    
    # Default to token auth if not specified
    AUTH_TYPE="${AUTH_TYPE:-token}"
    
    log_message "Configuration loaded successfully"
    log_message "Authentication Type: $AUTH_TYPE"
}

# --- CLOUDFLARE API CALL WRAPPER ---
cf_api_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    local headers=(-H "Content-Type: application/json")
    
    # Support both API Token (modern) and Global API Key (legacy)
    if [ "$AUTH_TYPE" = "token" ]; then
        headers+=(-H "Authorization: Bearer $CF_KEY")
    else
        headers+=(-H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_KEY")
    fi
    
    if [ -n "$data" ]; then
        curl -s -X "$method" "$endpoint" "${headers[@]}" --data "$data"
    else
        curl -s -X "$method" "$endpoint" "${headers[@]}"
    fi
}

# --- VALIDATE CREDENTIALS ---
validate_credentials() {
    local zone_id="$1"
    
    log_message "Validating credentials for Zone ID: $zone_id"
    
    response=$(cf_api_call "GET" "https://api.cloudflare.com/client/v4/zones/$zone_id")
    
    if echo "$response" | jq -e '.success == true' > /dev/null 2>&1; then
        log_message "✓ Credentials validated successfully"
        return 0
    else
        error_msg=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
        log_message "✗ Credential validation failed: $error_msg"
        return 1
    fi
}

# --- FETCH QUIC.CLOUD IPS ---
fetch_quic_ips() {
    log_message "Fetching QUIC.cloud IPs from $QUIC_CLOUD_IPS_URL"
    
    http_status=$(curl -s -o /dev/null -w "%{http_code}" "$QUIC_CLOUD_IPS_URL")
    
    if [ "$http_status" -ne 200 ]; then
        log_message "ERROR: Unable to access QUIC.cloud IPs (HTTP $http_status)"
        return 1
    fi
    
    QUIC_IPS=$(curl -s "$QUIC_CLOUD_IPS_URL" | jq -r '.[]')
    ip_count=$(echo "$QUIC_IPS" | wc -l)
    log_message "✓ Fetched $ip_count QUIC.cloud IPs"
    
    return 0
}

# --- GET MANAGED IPS FROM CLOUDFLARE ---
get_managed_ips() {
    local zone_id="$1"
    local page=1
    local ips=()
    
    while true; do
        response=$(cf_api_call "GET" \
            "https://api.cloudflare.com/client/v4/zones/$zone_id/firewall/access_rules/rules?page=$page&per_page=100")
        
        # Handle null response gracefully
        if ! echo "$response" | jq -e '.result' > /dev/null 2>&1; then
            log_message "WARNING: No firewall rules found or API returned null"
            break
        fi
        
        page_ips=$(echo "$response" | jq -r '.result[]? | select(.notes | test("QUIC\\.cloud IP")) | .configuration.value')
        
        if [ -z "$page_ips" ]; then
            break
        fi
        
        ips+=($page_ips)
        
        total_pages=$(echo "$response" | jq -r '.result_info.total_pages // 1')
        
        if [ "$page" -ge "$total_pages" ]; then
            break
        fi
        
        ((page++))
    done
    
    echo "${ips[@]}"
}

# --- GET RULE ID BY IP ---
get_rule_id_by_ip() {
    local zone_id="$1"
    local ip="$2"
    
    response=$(cf_api_call "GET" \
        "https://api.cloudflare.com/client/v4/zones/$zone_id/firewall/access_rules/rules?configuration.value=$ip")
    
    rule_id=$(echo "$response" | jq -r '.result[]? | select(.notes | test("QUIC\\.cloud IP")) | .id' | head -n1)
    
    echo "$rule_id"
}

# --- ADD IP TO WHITELIST ---
add_ip() {
    local zone_id="$1"
    local ip="$2"
    local current_date=$(date +%Y-%m-%d)
    
    payload=$(jq -n \
        --arg ip "$ip" \
        --arg date "$current_date" \
        '{
            mode: "whitelist",
            configuration: {
                target: "ip",
                value: $ip
            },
            notes: "QUIC.cloud IP, IP allowed on \($date)"
        }')
    
    response=$(cf_api_call "POST" \
        "https://api.cloudflare.com/client/v4/zones/$zone_id/firewall/access_rules/rules" \
        "$payload")
    
    if echo "$response" | jq -e '.success == true' > /dev/null 2>&1; then
        return 0
    else
        error=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
        log_message "  Failed to add $ip: $error"
        return 1
    fi
}

# --- REMOVE IP FROM WHITELIST ---
remove_ip() {
    local zone_id="$1"
    local rule_id="$2"
    
    response=$(cf_api_call "DELETE" \
        "https://api.cloudflare.com/client/v4/zones/$zone_id/firewall/access_rules/rules/$rule_id")
    
    if echo "$response" | jq -e '.success == true' > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# --- PROGRESS BAR ---
show_progress() {
    local current=$1
    local total=$2
    local action=$3
    
    if [ "$total" -eq 0 ]; then
        return
    fi
    
    local percent=$((current * 100 / total))
    local filled=$((current * 50 / total))
    local empty=$((50 - filled))
    
    printf "\r  %s: [" "$action"
    printf "%0.s#" $(seq 1 $filled)
    printf "%0.s-" $(seq 1 $empty)
    printf "] %d%% (%d/%d)" "$percent" "$current" "$total"
}

# --- PROCESS SINGLE ZONE ---
process_zone() {
    local zone_id="$1"
    
    log_message "=========================================="
    log_message "Processing Zone: $zone_id"
    log_message "=========================================="
    
    # Validate credentials
    if ! validate_credentials "$zone_id"; then
        log_message "Skipping zone $zone_id due to authentication failure"
        return 1
    fi
    
    # Fetch QUIC.cloud IPs
    if ! fetch_quic_ips; then
        log_message "Skipping zone $zone_id due to QUIC.cloud fetch failure"
        return 1
    fi
    
    # Get currently managed IPs
    log_message "Fetching existing QUIC.cloud rules..."
    current_ips=($(get_managed_ips "$zone_id"))
    log_message "Found ${#current_ips[@]} existing QUIC.cloud IPs"
    
    # Determine IPs to add
    ips_to_add=()
    for ip in $QUIC_IPS; do
        if ! printf '%s\n' "${current_ips[@]}" | grep -qx "$ip"; then
            ips_to_add+=("$ip")
        fi
    done
    
    # Determine IPs to remove
    ips_to_remove=()
    for ip in "${current_ips[@]}"; do
        if ! echo "$QUIC_IPS" | grep -qx "$ip"; then
            ips_to_remove+=("$ip")
        fi
    done
    
    log_message "IPs to add: ${#ips_to_add[@]}"
    log_message "IPs to remove: ${#ips_to_remove[@]}"
    
    # Add new IPs
    added=0
    if [ ${#ips_to_add[@]} -gt 0 ]; then
        log_message "Adding new IPs..."
        for i in "${!ips_to_add[@]}"; do
            ip="${ips_to_add[$i]}"
            if add_ip "$zone_id" "$ip"; then
                ((added++))
            fi
            show_progress $((i + 1)) ${#ips_to_add[@]} "Adding"
        done
        echo ""  # New line after progress bar
    else
        log_message "No new IPs to add"
    fi
    
    # Remove outdated IPs
    removed=0
    if [ ${#ips_to_remove[@]} -gt 0 ]; then
        log_message "Removing outdated IPs..."
        for i in "${!ips_to_remove[@]}"; do
            ip="${ips_to_remove[$i]}"
            rule_id=$(get_rule_id_by_ip "$zone_id" "$ip")
            
            if [ -n "$rule_id" ] && [ "$rule_id" != "null" ]; then
                if remove_ip "$zone_id" "$rule_id"; then
                    ((removed++))
                fi
            fi
            show_progress $((i + 1)) ${#ips_to_remove[@]} "Removing"
        done
        echo ""  # New line after progress bar
    else
        log_message "No outdated IPs to remove"
    fi
    
    log_message "✓ Zone $zone_id completed: Added $added, Removed $removed"
    return 0
}

# --- DELETE ALL MODE ---
delete_all_quic_ips() {
    local zone_id="$1"
    
    log_message "=========================================="
    log_message "DELETING ALL QUIC.cloud IPs from Zone: $zone_id"
    log_message "=========================================="
    
    if ! validate_credentials "$zone_id"; then
        log_message "Skipping zone $zone_id due to authentication failure"
        return 1
    fi
    
    current_ips=($(get_managed_ips "$zone_id"))
    total_ips=${#current_ips[@]}
    
    if [ "$total_ips" -eq 0 ]; then
        log_message "No QUIC.cloud IPs found to delete"
        return 0
    fi
    
    log_message "Found $total_ips QUIC.cloud IPs to delete"
    
    deleted=0
    for i in "${!current_ips[@]}"; do
        ip="${current_ips[$i]}"
        rule_id=$(get_rule_id_by_ip "$zone_id" "$ip")
        
        if [ -n "$rule_id" ] && [ "$rule_id" != "null" ]; then
            if remove_ip "$zone_id" "$rule_id"; then
                ((deleted++))
            fi
        fi
        show_progress $((i + 1)) $total_ips "Deleting"
    done
    
    echo ""
    log_message "✓ Deleted $deleted QUIC.cloud IPs from zone $zone_id"
    return 0
}

# --- MAIN EXECUTION ---
main() {
    echo "=================================================="
    echo "  QUIC.cloud Cloudflare IP Whitelisting Script"
    echo "=================================================="
    echo "" >> "$LOG_FILE"
    log_message "Script execution started"
    
    # Load configuration
    load_config
    
    # Parse zone IDs
    IFS=' ' read -r -a zone_array <<< "$ZONE_IDS"
    log_message "Processing ${#zone_array[@]} zone(s)"
    
    # Check for delete mode
    delete_mode=false
    if [[ "$1" == "delete" ]]; then
        delete_mode=true
        log_message "DELETE MODE ENABLED"
    fi
    
    # Process each zone
    success_count=0
    fail_count=0
    
    for zone in "${zone_array[@]}"; do
        if [ "$delete_mode" = true ]; then
            if delete_all_quic_ips "$zone"; then
                ((success_count++))
            else
                ((fail_count++))
            fi
        else
            if process_zone "$zone"; then
                ((success_count++))
            else
                ((fail_count++))
            fi
        fi
    done
    
    log_message "=========================================="
    log_message "Execution Summary"
    log_message "=========================================="
    log_message "Total Zones: ${#zone_array[@]}"
    log_message "Successful: $success_count"
    log_message "Failed: $fail_count"
    log_message "Script execution completed"
    
    echo ""
    echo "Log file: $LOG_FILE"
}

# Run main function
main "$@"
