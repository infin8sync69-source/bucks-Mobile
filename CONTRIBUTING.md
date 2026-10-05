# Working on Bucks (Android, iOS and the backend)

Bucks is one product with two native apps and one backend. They live in this one repository so a change to the product can land
on every layer in a single reviewed pull request, and so CI can check the layers against each other.

```
app/          Android app (Kotlin, Jetpack Compose)
ios/          iOS app (SwiftUI): BucksCore (logic), BucksUI (screens), App (Firebase glue), Tests
supabase/     the backend both apps call: schema.sql, migrations/, functions/, tests/
docs/         product and design notes; docs/PARITY.md tracks Android / iOS parity
.github/      CI (android-ci, ios-ci, database-ci) and the Android tester build (android-build)
```

## Branches

- `main` is the only long-lived branch. It must always build on both platforms and pass the database tests.
- Work happens on short-lived branches cut from `main` and merged back by pull request, ideally within a few days:
  - `feat/<name>`: a product feature, normally on both platforms (and the backend when needed),
  - `android/<name>`, `ios/<name>`: work on one app only (a platform fix, or the second half of a feature),
  - `db/<name>`: backend-only changes (migrations, functions, policies).
- Do not keep a separate long-lived branch per platform, and do not split the apps into separate repositories: the apps share the
  backend contract (RPC names, parameters, row shapes), and keeping them together is what lets one pull request change all three.
- Large work is split into stacked pull requests (each based on the one before) so every review stays readable. Merge from the bottom
  of the stack up; GitHub retargets the next one when its base branch is deleted on merge.

## Keeping the two apps identical

The apps are ports of each other, file by file: `ios/README.md` has the Android to iOS file map, and screens keep the same names,
copy, flows and navigation. To keep it that way:

1. A user-facing change ships on both platforms in the same pull request, or the pull request names the follow-up pull request or
   issue for the other platform and adds a row to `docs/PARITY.md`. Nothing reaches testers on one platform only without a tracked
   follow-up.
2. Use the same words. Copy, toasts and error messages are identical on both apps (iOS strings are ported from the Kotlin source).
3. Port behaviour, not just layout: the rules live in the state classes (`Dispatch.kt` / `Dispatch.swift`, `Commerce.kt` /
   `CommerceStore.swift`, ...), and the unit tests on both sides cover them.
4. Intentional differences (platform features one side does not have) are listed in `docs/PARITY.md` so they are not "fixed" by mistake.

## Backend changes

Both apps talk to the same Supabase project, and old app versions stay installed for weeks, so the backend must stay
backward compatible:

1. Change the backend first. New RPCs and columns are additive; never rename or remove one that a released app still calls.
   Remove it only after every supported app version has stopped using it.
2. Add a migration in `supabase/migrations/<name>.sql` (idempotent, `set search_path = public, extensions`, RLS on every new table),
   register it in `supabase/apply_all.sh`, and add scenarios in `supabase/tests/<name>_scenarios.sql`. Run everything with
   `supabase/tests/run_all.sh` (database-ci does the same on every pull request).
3. A function redefined by a later file (the `hardening_*.sql` files run last) must carry every earlier change to that function. The
   e-commerce scenarios exist because this was missed once.
4. Apply migrations to the live project before merging the app changes that need them.

## Pull requests and CI

Every pull request runs the checks for what it touches:

| Workflow | Runs when | What it does |
|---|---|---|
| `android-ci.yml` | `app/`, Gradle files | `assembleDebug` in live mode; Kotlin errors become annotations; the APK is kept as an artifact |
| `ios-ci.yml` | `ios/` | `swift build` and `swift test` for the packages, then an unsigned Simulator build of the whole app with Firebase |
| `database-ci.yml` | `supabase/` | applies the whole stack to PostgreSQL 16 + PostGIS and runs every scenario suite |
| `android-build.yml` | push to `main` / `pilot-release-fixes` | publishes the Android tester build as a GitHub release |

Before asking for review: CI is green, the pull request template is filled in, and the parity section says what happens on the
other platform. Recommended repository settings (Settings > Branches > `main`): require a pull request, require the three CI checks
above to pass, and require branches to be up to date before merging.

## Secrets

Nothing secret is committed. Android reads `local.properties`; iOS generates `ios/Config/Secrets.xcconfig` from it with
`ios/scripts/make_secrets.sh`; CI reads repository secrets (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `MAPBOX_TOKEN`, optional
`GOOGLE_SERVICES_JSON`). `firebase/google-services.json` is a client config and is committed for the tester build; the iOS
`ios/App/GoogleService-Info.plist` is gitignored.

## Working in parallel without collisions

Several people (and several Claude sessions) can work on the same repository at once. These rules keep them apart:

1. **One branch per task, one person (or session) per branch.** Never push to a branch someone else created. If you need their work, branch from it
   (`git switch -c ios/<name> origin/<their-branch>`) and open a pull request into theirs.
2. **Start from the latest.** `git fetch --all --prune` and look at `git branch -r` and `gh pr list` before you start: if the work already exists on
   another branch, build on that branch instead of redoing it.
3. **Stay inside your area.** Android is `app/`, iOS is `ios/`, the backend is `supabase/`. A pull request that touches two areas is a feature
   pull request (`feat/<name>`) and lists the follow-up for any platform it leaves out. Files outside your area are changed only when the
   feature needs them. `.github/CODEOWNERS` names the reviewer for each area.
4. **Shared contract files change first and alone.** An RPC name, parameter or row shape that both apps use is changed in a `db/<name>` pull request
   that merges before the app changes that depend on it.
5. **Rebase or merge `main` into your branch before asking for review**, never force-push a branch other people have pulled, and never force-push `main`.
6. **Do not commit generated or local files:** `ios/Bucks.xcodeproj`, `ios/Config/Secrets.xcconfig`, `ios/App/GoogleService-Info.plist`,
   `local.properties`, build folders. They are in `.gitignore`.
7. **Merge small and often.** A branch older than a few days is a branch that will conflict.

### Publishing to testers

- A push to `main` publishes the **Android** tester build (`android-build.yml`). Changes that only touch `ios/`, `docs/` or markdown are
  excluded from that trigger, so an iOS merge never publishes an APK.
- iOS builds are made on a Mac: see `docs/IOS_RELEASE.md` (signing, TestFlight, build numbers).
- Both apps take their build number from the same counter so a build number means the same commit on both platforms (`docs/IOS_RELEASE.md`).
