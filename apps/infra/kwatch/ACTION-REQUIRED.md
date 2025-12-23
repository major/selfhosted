# ⚠️ ACTION REQUIRED: Update kwatch Configuration

## Why This Change Is Needed

The kwatch deployment has been updated to use environment variable substitution for the cluster name. The sealed configuration needs to be regenerated to include a `${CLUSTER_NAME}` placeholder that will be replaced at runtime with the actual cluster name ("selfhosted").

Currently, alerts from kwatch may not include the cluster name, making it unclear which cluster has issues.

## What You Need to Do

The `sealed-config.yaml` file needs to be regenerated to include the `${CLUSTER_NAME}` placeholder instead of a hard-coded value.

### Option 1: Use the Update Script (Recommended)

Run the provided script on a machine with cluster access:

```bash
cd apps/infra/kwatch
./update-sealed-config.sh
git add sealed-config.yaml
git commit -m "Update kwatch config with cluster name"
git push
```

### Option 2: Manual Update

Follow the steps in README.md under "Updating the Configuration" section.

## Verification

After updating and deploying:

1. Check the kwatch logs to verify it loaded the configuration:
   ```bash
   kubectl --kubeconfig ~/.kube/k3s-psychz-config -n kwatch logs -l app=kwatch
   ```

2. Create a test failing pod to trigger an alert:
   ```bash
   kubectl --kubeconfig ~/.kube/k3s-psychz-config run test-crash \
     --image=busybox \
     --restart=Always \
     -- /bin/sh -c "exit 1"
   ```

3. Check Discord - the alert should now include "Cluster: selfhosted" in the message

4. Clean up the test pod:
   ```bash
   kubectl --kubeconfig ~/.kube/k3s-psychz-config delete pod test-crash
   ```

## Technical Details

The cluster name is configured in the `app.clusterName` field of the kwatch config.yaml:

```yaml
app:
  clusterName: selfhosted
```

This value is then included in all alert notifications sent to Discord.
