# SENECApp-Frontend-Flutter

Frontend for SENECApp, developed in Flutter. SENECApp is a discovery app for
Registered Student Organizations (RSOs) at Universidad de los Andes.

This is the first working prototype, ported from the Figma design. All data is
seeded in memory - there is no backend yet.

## Requirements

- **Flutter 3.41+** with Dart 3.11+ (`flutter --version`)
- **Android Studio**, for the Android SDK, an emulator and the platform tools
- A device or emulator running **API 21 or higher**

Verify the toolchain with `flutter doctor`. Every line should be a check mark
except Visual Studio and Xcode, which are only needed for Windows and iOS
builds and are not used here.

## Running it

```bash
flutter pub get
flutter emulators --launch Pixel_8 # In my case I use an emulator and it's a Pixel_8
flutter run                 # Android device or emulator
flutter run -d chrome       # browser, no Android SDK needed
```

In the browser the app draws itself inside a 390x844 phone frame so the layout
matches the design instead of stretching across the window. On a device the
frame steps aside automatically.

```bash
flutter test                # widget tests
flutter analyze             # static analysis
```

## Project layout

```
lib/
  main.dart                 entry point; reads the asset manifest, sets system UI
  app.dart                  MaterialApp, theme and the state provider
  core/
    theme/                  palette, typography, radii, spacing
    widgets/                shared UI: cards, chips, badges, images
    assets/                 which images are bundled
  data/
    models/                 Rso, CampusEvent, AppNotification, StudentProfile
    repositories/           RsoRepository - the seeded catalogue
  state/
    app_state.dart          what the student changes: joins, likes, reads
  features/
    shell/                  bottom navigation and the per-tab navigators
    discover/  events/  my_rsos/  profile/
    rso_detail/  create_rso/  notifications/
```

The split that matters: the **repository** holds the catalogue, which never
changes, and **AppState** holds the student's relationship to it. Screens read
from both and own no data themselves, so replacing the repository with an API
client later does not touch the UI.

## Design

The palette, typography and navigation model come from the team's UI/UX
document.

| Role | Hex | Applied to |
|---|---|---|
| Base | `171A21` | App canvas, bottom nav bar |
| Contrast | `F0E2E7` | Primary text and icons |
| Accent 1 - brand | `A50104` | Active chip, active nav state, destructive actions |
| Accent 2 - action | `FFBA08` | Primary CTAs, "Official" badge, active filter pill |
| Accent 3 - surface | `1D3557` | Inactive chips, input backgrounds |

Type is **Bricolage Grotesque** for headings and **Nunito** for body and UI,
loaded through the `google_fonts` package. The first launch fetches and caches
them, so it needs a network connection; later launches do not.

Navigation is flat at the top level (four peers in a bottom bar) and
hierarchical inside each section, capped at two levels. Each tab owns its own
`Navigator`, which is what makes back *contextual*: an organization opened from
Events returns to Events, not to Discover.
