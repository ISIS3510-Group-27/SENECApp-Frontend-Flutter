# SENECApp (Flutter)

Discover student organizations at Universidad de los Andes. This app talks to the
[SENECApp backend](https://github.com/ISIS3510-Group-27/SENECApp-Backend); start it first (`docker compose up` in the backend repo).

## Running

```sh
flutter pub get
flutter run                     # Android emulator, dev sign-in, backend at http://10.0.2.2:8000
```

Build settings are passed with `--dart-define`:

| Setting | Default | Notes |
|---|---|---|
| `API_BASE_URL` | `http://10.0.2.2:8000/api/v1` on Android, `http://localhost:8000/api/v1` elsewhere | A physical phone needs the laptop's LAN IP, or a tunnel URL (`cloudflared tunnel --url http://localhost:8000`) on Uniandes Wi-Fi |
| `AUTH_MODE` | `dev` | `dev` or `firebase` (see below) |

```sh
flutter run --dart-define=API_BASE_URL=http://192.168.0.10:8000/api/v1
```

Debug builds allow plain HTTP to reach the local backend; release builds require HTTPS.

## Sign-in

- **`AUTH_MODE=dev`**: any `@uniandes.edu.co` email, no password. The app sends `dev:<email>` as the token, which the backend accepts only with `AUTH_PROVIDER=dev`. **Use demo student** signs in as Sofía Arango, the seeded student.
- **`AUTH_MODE=firebase`**: Firebase Authentication with email and password. New accounts must click the verification link before the backend lets them in.

To enable Firebase:

1. Create a Firebase project and enable **Authentication → Email/Password**.
2. Run `dart pub global activate flutterfire_cli`, then `flutterfire configure` in this folder (choose Android, package `co.edu.uniandes.senecapp`). It adds `google-services.json` and the Gradle plugin.
3. In the backend's `.env`: `AUTH_PROVIDER=firebase` and `FIREBASE_PROJECT_ID=<project id>`.
4. `flutter run --dart-define=AUTH_MODE=firebase`

## Push notifications

Push (Firebase Cloud Messaging) uses the same Firebase project, so it switches on with `AUTH_MODE=firebase`. Without it, notifications still reach the in-app inbox. To have the backend send pushes, follow "Push notifications" in the backend README (service-account key and `PUSH_PROVIDER=fcm`).

The app registers the phone after sign-in and unregisters it on sign-out. Tapping a push opens its event or group. Android 13+ asks the student for permission first.

## Sign in with Microsoft

Only with `AUTH_MODE=firebase`.

1. In Azure (portal.azure.com, App registrations), register an app for "Accounts in this organizational directory only" so only Uniandes accounts get in. Add the redirect URI that Firebase shows in the next step, and create a client secret.
2. In Firebase, Authentication, Sign-in method, enable **Microsoft** with that app's client ID and secret.
3. The app sends `tenant=uniandes.edu.co`. To use the tenant ID instead: `--dart-define=MICROSOFT_TENANT=<tenant id>`.

If Firebase marks the Microsoft email as unverified, the app sends the usual verification link once.

## Group photos (Firebase Storage)

Group admins change the cover photo from the group page (camera or gallery). It needs `AUTH_MODE=firebase` and Storage enabled in the Firebase project, with rules like:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /groups/{groupId}/{file} {
      allow read;
      allow write: if request.auth != null
        && request.resource.size < 5 * 1024 * 1024
        && request.resource.contentType.matches('image/.*');
    }
  }
}
```

## Leader tools, reminders and outdoor mode

- **Create event** (group admins): suggests the times when most members are out of class, weighted by past attendance (`GET /groups/{id}/insights/best-times`), and shows BQ3, the hours and buildings where suggested events get the most interaction (`GET /groups/{id}/insights/audience`).
- **Leave-time reminder** on an event page: a local notification at the time to leave, counting the walk from where the student is (or from the class before), and waiting for a class to end. Android only.
- **Outdoor mode** (Profile): the ambient light sensor turns on stronger contrast and bold text in direct sunlight. Android only, read through `MainActivity`.

## Tests

```sh
flutter test
```
