# Testing Guide: Dudenest v0.5.0 Alpha (Replica Mode)

This guide explains how to manually verify the new **Replica Strategy** and **Advanced Visualizer**.

## Prerequisites
1. Open the Dudenest App (v0.5.0).
2. Ensure you have **at least 3 Cloud accounts** connected (e.g., 3 different GDrive accounts or a mix of GDrive and Mega).
3. Access the app via `https://dudenest.com` (after CI deploy completes).

## Test 1: Strategy Selection & Upload
1. Go to **Settings**.
2. Toggle "Storage Strategy" to **Replica**.
3. Go to the **Upload** screen and upload a file (e.g., an image).
4. **Verification**:
   - The upload should finish successfully.
   - Go to **Cloud Accounts** -> **Visualizer**.
   - You should see the new file mapped to 3 different storage providers.

## Test 2: Transparent Failover (The "Solid Mechanism" Test)
1. In **Settings**, ensure you are still in **Replica** mode.
2. Go to **Cloud Accounts**.
3. **Manually disconnect** or "break" your primary GDrive account (e.g., revoke app access in Google Security settings or rename the `dudenest-relay` folder on GDrive).
4. In the app, try to **Open/View** the file you uploaded in Test 1.
5. **Verification**:
   - The file should open without any error.
   - Check Relay logs: you should see a "failover" log entry indicating that the main provider failed and a backup was used.

## Test 3: Visualization & Quota
1. Go to **Cloud Accounts** -> **Visualizer**.
2. Check the **Pie Chart**: It should show the proportional usage of each account.
3. Check the **Data Mapping**: It should visually link your files to multiple accounts.

## Disaster Recovery Verification
1. Uninstall the Relay or wipe its `/tmp/dudenest-maps` folder.
2. Re-log in with the same user credentials.
3. The app should pull the FileMap and restore your file list automatically.

---
**Author**: Dariusz Porczyński
