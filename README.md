# TU Ver 01 — JTCPL driver app

Driver app for **Jagdamba Transport Carriers Pvt Ltd (JTCPL)**: diesel entries, odometer readings and GPS every 5 minutes from the driver's own phone. Admin screens are in the same app.

## How it is built
- Flutter (Android app + website for desktop testing), Firebase Auth + Firestore on the free Spark plan, OpenStreetMap, Google ML Kit for slip scanning (phone only).
- Every push to `main` runs **Actions → Build TU Ver 01**:
  - the website is published to `https://jtcpl1947-jlo.github.io/tu-ver-01/`
  - the APK is attached to the run as `tu-ver-01-apk`

## One-time Firebase setup
1. Firestore Database created in `asia-south1`.
2. Authentication → Email/Password enabled.
3. Authentication → Settings → Authorized domains → add `jtcpl1947-jlo.github.io`.
4. Firestore → Rules → paste `firestore.rules` → Publish.
5. Settings → Pages → Source: **GitHub Actions**.

## First use
Open the website → **Admin login** → the first time it shows **First-time setup** to create the Admin. Then add trucks, pumps and drivers (each with a unique 6-digit PIN).

## Logins
- Driver: mobile number + PIN given by Admin.
- Admin / Manager: email + password (Manager is view only).

## Test-phase notes
- Photos are stored compressed in Firestore (`photos`). Move to free object storage before full rollout.
- Background GPS works in the Android app; the website records location only while the page is open.
