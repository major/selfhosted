# Changes Summary: CLUSTER_NAME for kwatch

## Problem Statement
The kwatch deployment manifest needed to be updated to include an environment variable named CLUSTER_NAME, with its value set to "selfhosted". Any alert logic should reference this variable so alerts contain the correct cluster name instead of leaving it empty.

## Solution Overview
Since kwatch reads its configuration from a YAML file (not directly from environment variables), we implemented an init container approach that:
1. Reads a configuration template containing `${CLUSTER_NAME}` placeholder
2. Substitutes the placeholder with the actual CLUSTER_NAME environment variable value
3. Writes the processed configuration to an emptyDir volume
4. kwatch then reads the final processed configuration

## Changes Made

### 1. deployment.yaml
**Added:**
- Init container `config-init` that performs environment variable substitution
- `CLUSTER_NAME` environment variable set to "selfhosted"
- Input validation to prevent shell injection attacks
- emptyDir volume for processed configuration

**Modified:**
- Changed config source from direct secret mount to two-step process:
  - `config-template` volume mounts the sealed secret (read-only)
  - `config` volume is an emptyDir where processed config is written

### 2. config-template.yaml (new file)
- Template configuration showing the expected format
- Uses `${CLUSTER_NAME}` placeholder instead of hardcoded value
- Serves as documentation for the configuration structure

### 3. update-sealed-config.sh (new script)
- Automates the process of regenerating sealed-config.yaml
- Fetches Discord webhook from flux-notifications secret
- Creates config with `${CLUSTER_NAME}` placeholder
- Seals the configuration using kubeseal
- Includes security improvements (umask 077)

### 4. README.md
**Updated sections:**
- Configuration section explains the new substitution approach
- Added "How It Works" section with step-by-step explanation
- Updated "Updating the Configuration" with script usage
- Clarified that cluster name is now dynamically injected

### 5. ACTION-REQUIRED.md (new file)
- Clear instructions for the user to regenerate sealed-config.yaml
- Explains why the change is needed
- Provides verification steps

## Security Considerations
✅ Added input validation for CLUSTER_NAME (alphanumeric, underscore, hyphen only)
✅ Added umask 077 to update script to protect temporary files
✅ Maintained sealed secret for sensitive Discord webhook URL
✅ Init container runs with minimal privileges (no special permissions needed)

## What the User Needs to Do
The user must run the update script to regenerate sealed-config.yaml with the ${CLUSTER_NAME} placeholder:

```bash
cd apps/infra/kwatch
./update-sealed-config.sh
git add sealed-config.yaml
git commit -m "Update kwatch config with cluster name placeholder"
git push
```

## Expected Behavior After Deployment
1. Init container starts and validates CLUSTER_NAME
2. Init container substitutes ${CLUSTER_NAME} with "selfhosted" in the config
3. Init container writes processed config.yaml to /config/
4. kwatch container starts and reads the processed configuration
5. All alerts sent by kwatch will include "Cluster: selfhosted" in the message

## Testing
To verify the change works:
1. Check init container logs: `kubectl logs -n kwatch -l app=kwatch -c config-init`
2. Create a test crash pod to trigger an alert
3. Verify Discord alert includes the cluster name
