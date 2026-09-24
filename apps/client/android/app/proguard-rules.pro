# R8 rules for the release build.
# Flutter and the plugins used by CalSnap ship their own consumer rules; keep this file
# for project-specific additions and verify them against a release build.

# Flutter deferred components reference Play Core classes that are not part of this app.
-dontwarn com.google.android.play.core.**
