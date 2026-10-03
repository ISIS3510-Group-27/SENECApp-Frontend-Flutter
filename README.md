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

## Tests

```sh
flutter test
```
