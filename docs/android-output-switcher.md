# Android output switcher

Kalinka's existing `KalinkaMediaService` owns the sole `MediaSessionCompat` (`KaiMediaSession`) and notification (ID 1001). `KalinkaMediaPlugin` enables/disables that service from Flutter and reports foreground volume-key activity back to the UI. There is no `audio_service`, `just_audio`, second media session, or local audio playback in this integration. Metadata, artwork, position, and queue transport callbacks remain in that service.

## Routing and volume ownership

`KalinkaRouting` registers a service-lifetime AndroidX callback and associates the existing session using `MediaRouter.setMediaSessionCompat`. **MediaRouter alone configures the session's volume provider.** On Android 11+ its MediaRouter2 bridge supplies the routing controller's ID as the volume control ID. A renderer UUID is only a provider route ID; it is never a volume control ID.

The provider is a manifest-declared `KalinkaRouteProviderService` with both `android.media.MediaRouteProviderService` and `android.media.MediaRoute2ProviderService` intent actions. AndroidX handles the platform bridge. The provider is not registered using `addProvider` in production. It shares the media service's process, publishes no routes without that service, and does not start Flutter, networking, or a foreground service itself.

The manifest's non-exported `MediaTransferReceiver`, enabled transfer parameter, and `org.kalinka.kalinka.RENDERER` selector opt into system routing. Provider routes include that category and `CATEGORY_REMOTE_PLAYBACK`, without advertising generic URL playback actions. Selection is restricted to Kalinka; API 34+ routes also use package-restricted visibility. Transfer to phone/Bluetooth is disabled because this Android app has no audio renderer. API 30–33 omits unavailable rows, since the platform bridge cannot present them as disabled. API 34+ listing preferences rank the current renderer first and explain offline/incompatible entries.

AndroidX 1.8.1 is the stable dependency. The project's Flutter-provided minimum SDK remains unchanged (24 with the current SDK). Android 24–29 uses static route controllers; Android 30+ uses a dynamic routing session containing exactly one renderer. It advertises transfers, never grouping or removing individual members. This allows confirmed renderer changes to update an existing routing session. On a new Android routing controller, the same media session is re-associated: 1.8.1 otherwise reuses a volume provider when two outputs have equal volume ranges, potentially retaining the old controller ID.

## Controller synchronization

The native service consumes `renderers_changed`, `current_renderer_changed`, and the renderer fields in the existing `/queue/ws` replay. This is the same server-discovered inventory used by Flutter's `rendererListProvider`; there is no new mDNS or renderer discovery. `/renderer/list` seeds state and confirms transfers. For servers predating topology events it also refreshes every 15 seconds while the service is enabled. Generation/revision checks reject stale HTTP snapshots.

System selection issues one `PUT /renderer/active` with `renderer_id`, matching Flutter's existing operation. It does not clear, restart, or reconstruct the queue. Actual `current_renderer_id`/`active` state confirms a transfer, not a successful response to the pin request. Duplicate callbacks and member-controller creation cannot send duplicate selections. Failures clear connecting state and retain/reconcile the last confirmed destination. Another client's choice follows the same event path, without sending an echo command.

`/device/ws` and `/device/get_volume` provide `supported`, `current_volume`, and `max_volume` for the current output. Absolute and relative Android requests use the existing `PUT /device/set_volume?volume=...` API. Values are clamped, slider/key bursts are coalesced, and writes are serialized. Server volume updates are never discarded during a timed suppression window. Instead, ordering decides: an accepted request is the base for the next relative change (a key press), a read overtaken by a newer request is dropped, and device events that arrive while a burst of requests is still being sent are skipped, because the burst ends with a fresh read. A new renderer invalidates the old volume and triggers a fresh read, because device events have no renderer ID. Queued volume requests cannot carry over to a different renderer.

AndroidX creates a dynamic session's individual volume controllers with empty `RouteControllerOptions`: the client package is the empty string, not null. The provider accepts these bridge calls while rejecting explicitly foreign packages. Rejecting the empty string previously left the system picker with a slider but no controller (`MR2ProviderService: onSetRouteVolume: Couldn't find a controller`). Both member and session volume callbacks use the same command path.

While Kalinka's Activity is resumed and has focus, volume-up/down key presses and hold repeats go directly to that same remote-volume path. Matching key-up events are consumed as well, so Android's local volume panel does not appear. Fixed or temporarily unknown remote volume does not adjust the phone's volume. Without a connected renderer, while playback does not hold it, and while backgrounded, normal Android key dispatch applies; background remote volume remains assigned by Android.

The foreground UI shows the kiosk volume control on an opaque panel at full scale, 280 logical pixels high, on the right edge. Each key press passes its requested level to Flutter, so the bar moves on the press rather than on the server's echo. Only key presses and touches on it bring it up (volume changes from elsewhere do not), and it fades two seconds after the last of them. Key presses show it even at the volume limits. Background events do not show it on resume, and kiosk mode keeps its existing larger indicator. Notification initialization lives at the app root so launching directly into kiosk also enables native remote controls.

The controller list does not expose every inactive renderer's volume state. Inactive/unknown outputs therefore expose fixed volume with range zero until selected and queried; Kalinka does not invent a range or show a stale volume from another output. A reported `supported: false` always remains fixed. Volume is also fixed, and the app shows no volume control, unless the player is playing, buffering or paused: only playback holds the renderer, and its volume means nothing otherwise.

## Release and lifecycle

Releasing a route controller never sends stop, pause, or `renderer_id: null`. Android's **Stop casting** detaches this phone's routing/media presentation and removes its notification; shared controller playback and its renderer pin continue. A subsequent renderer change restores the presentation while connected. The existing notification transport **Stop** command still stops the queue explicitly. Transfer releases and renderer disappearance are handled separately from an intentional client detach.

The router callback and native sockets live in the service while the Activity is backgrounded. Either socket failing or starting a close handshake disables the native service, removes its notification/session, and clears routes. Flutter also disables it as soon as the connection leaves `connected`, including `reconnecting`. Automatic reconnection does not restore media controls. Returning to the app from the background, explicitly retrying, or selecting a server requests a new notification lifetime once connected; closing the notification shade alone does not. Disabling during a pending service bind cancels the queued enable as well as the binding. Disabling, changing servers, task removal, and destruction cancel requests and clear routes. Existing exclusive playback behavior continues to release Kalinka's media session.

The notification is published only once there is a confirmed, associated remote output and a current track. Servers without renderer inventory cannot supply a truthful destination and do not produce a routed media notification. No privileged `setRemotePlaybackInfo`, fabricated notification extras, or hidden Android APIs are used.

The remote output is attached before the media session becomes active. On notification removal or disable, the session is deactivated before routing is detached: AndroidX resets a detached session to local playback. This ordering avoids advertising an active phone output during startup and teardown. Stopping routing also releases the selected remote route immediately, before asynchronous descriptor removal, so a subsequent enable cannot reuse the old routing controller's volume-control ID.

On API 30+, an application-context observer with an empty selector and no discovery flags remains registered between connections. AndroidX 1.8.1 removes released platform controllers from its cache in the asynchronous `onStop` callback; unregistering its last observer too early loses that callback and lets later connections reuse a stale controller. This passive observer keeps release acknowledgements flowing while the service's routes, discovery, sockets, and media session are all cleared on disconnect.

## Automated checks

```sh
flutter build apk --debug
cd android
./gradlew :app:testDebugUnitTest :app:lintDebug
cd ..
flutter test test/renderer_switcher_test.dart test/now_playing_exclusive_test.dart test/queue_zone_exclusive_test.dart
flutter test test/foreground_volume_overlay_test.dart test/volume_control_slider_test.dart test/kiosk_test.dart test/widget_test.dart
flutter test test/media_notification_provider_test.dart test/connection_reconnect_test.dart
```

Native tests cover descriptor identity/capabilities, manifest registration, callback translation, asynchronous HTTP success/refusal, duplicate selections, controller-driven selection, fixed/clamped volume, coalescing, disappearance, reconnection, and non-destructive release. Robolectric checks do not verify SystemUI, the platform MediaRouter2 binder bridge, or hardware-key assignment. Regression tests also cover empty bridge options before/after a transfer, real HTTP volume writes from member and hardware-key callbacks, key holds/releases, fixed-volume outputs, limit feedback, and foreground overlay lifecycle/timeout.

Single-renderer tests cover initial session association and reselection without a server write. Provider bridge tests on API 30 and 34 verify the named routing session with no transfer targets, late volume updates, and adding/removing a second renderer. Media service tests record the framework calls to check that activation and teardown do not advertise active local playback.

Disconnect tests cover closure of either socket, abrupt socket failure, notification/session removal without native retries, explicit re-enable, synchronous release of the selected route, passive observation without discovery between connections, and disabling during service binding. A new Flutter engine claims ownership when enabling controls, so teardown of the previous engine cannot disable them; a regression test covers that overlap. Flutter tests cover immediate dismissal, suppressed automatic restoration, explicit retry, and app resume both before and after reconnection.

## Device verification

Use two connected renderers with distinct names, one fixed-volume renderer, and a second Kalinka client. Include the reported Pixel Android 17 build, an Android 11–13 device, and a pre-30 device for compatibility (the native system output picker itself starts at Android 11).

Install and connect normally, then start a known queue:

```sh
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell dumpsys media_session > media-session-before.txt
adb shell dumpsys media_router > media-router-before.txt
adb shell dumpsys activity service org.kalinka.kalinka/.KalinkaMediaService > media-service-before.txt
adb shell dumpsys notification --noredact > notifications-before.txt
adb logcat -s KalinkaMedia KalinkaRouting MediaRouter MR2ProviderService
```

1. Check there is one active `KaiMediaSession`, one Kalinka media notification, correct artwork/track/position, and a chip naming the **renderer**, even when the controller is on a differently named machine.
   Repeat with only one renderer available, including a cold app start and selecting that same renderer in the picker. Check both debug and release APKs. If the chip shows **This phone**, capture the dumps before switching outputs or restarting; include `adb shell dumpsys activity service com.android.systemui/.SystemUIService` to compare SystemUI's cached device with the media session and router.
2. In `media_router`, find `KalinkaRouteProviderService`, both renderer route IDs, and a routing session for `org.kalinka.kalinka`. Its selected route must match the renderer. In `media_session`, check remote playback, current/max volume, and (where printed by that Android build) that the volume control ID matches the routing session/controller ID, not the renderer UUID.
3. Open the native picker. Check names, availability, selected row, speaker icon, and volume. Select the other renderer. Verify playback follows existing controller transfer semantics, the queue is preserved, and transport commands still work. Compare dumps before/after: media-session identity should persist through an ordinary output switch.
4. Switch from Flutter, then from the second client. Check Android follows each confirmed output without an extra `/renderer/active` request. Controller HTTP logs can establish exact command counts. Pre-topology-event servers can take up to the 15-second inventory refresh interval.
5. Drag the picker volume and press volume keys while Android has assigned them to Kalinka. Check the renderer, Flutter slider, and Android values agree. Change volume from the second client immediately afterward. Test at both limits and switch to the fixed-volume renderer; its slider must not issue commands. Bring Kalinka to the foreground and press/hold both volume buttons: only the compact in-app indicator should appear, including at a volume limit. Drag it, wait for its fade, then check kiosk mode shows only its larger indicator. In the background, verify SystemUI volume still reaches the selected renderer and no missing-controller warning appears in logcat.
6. Repeat with Kalinka backgrounded and the screen locked. Disconnect Wi-Fi and verify the notification, session, and routes disappear once connection loss is detected. Restore Wi-Fi and verify the notification stays absent. Reopen the app and check that controls return with a volume-control ID matching the new routing session. Repeat a drop/reconnect with the app foregrounded: automatic reconnection must leave controls hidden until an explicit retry or a return from the background. Separately, take the selected renderer offline and restore it, and force a refused transfer (for example an output owned by another Core). Check connecting state clears, the confirmed destination wins, and old volume requests do not reach the new output.
7. Use Stop casting. The phone detaches while shared playback continues. Change renderer from another client to reattach. Swipe Kalinka from recents and check its session, notification, and routes are removed without stopping the server.

Capture the same two dumps after each case:

```sh
adb shell dumpsys media_session > media-session-after.txt
adb shell dumpsys media_router > media-router-after.txt
```

The renderer chip, SystemUI ordering, volume-key assignment, and Android 17 behavior must be checked on physical devices; a successful build is not evidence of those.

The service dump reports whether controls are enabled, whether playback has a track, and whether routing is ready or detached. It also prints the selected route and associated session route, without server addresses or track metadata.

## Official references reviewed

- [Android media routing and output switcher](https://developer.android.com/media/routing)
- [MediaRouteProvider overview](https://developer.android.com/media/routing/mediarouteprovider)
- [MediaRouter session association and listing preferences](https://developer.android.com/reference/androidx/mediarouter/media/MediaRouter)
- [MediaTransferReceiver configuration and background callbacks](https://developer.android.com/reference/androidx/mediarouter/media/MediaTransferReceiver)
- [MediaRouterParams.Builder](https://developer.android.com/reference/androidx/mediarouter/media/MediaRouterParams.Builder)
- [AndroidX MediaRouter releases](https://developer.android.com/jetpack/androidx/releases/mediarouter)
- [AndroidX routing demo manifest (both provider service actions)](https://github.com/androidx/androidx/blob/androidx-main/samples/MediaRoutingDemo/src/main/AndroidManifest.xml)
- [AndroidX 1.8.1 source archive](https://dl.google.com/dl/android/maven2/androidx/mediarouter/mediarouter/1.8.1/mediarouter-1.8.1-sources.jar)
- [Activity key dispatch](https://developer.android.com/reference/android/app/Activity#dispatchKeyEvent(android.view.KeyEvent))
