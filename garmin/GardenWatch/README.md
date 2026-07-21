# GardenWatch — AgentGarden mirror for Garmin (no-touch)

A tiny Connect IQ watch-app that mirrors AgentGarden on your wrist: it polls
`GET /approvals` on GardenServer and shows whether any tool is waiting for you,
buzzing once when a new approval appears. It **does not** approve or type — you
still act on the phone. This is the "feel it on my wrist while the phone is in
my pocket" piece.

> **Two honest limits (read before investing):**
> 1. **Real-time only while the app is open on the watch.** Connect IQ
>    background services are capped at ~5 min, but an approval times out at
>    ~280 s, so a background check would miss it. For truly hands-free
>    real-time buzzing, a phone push relay (ntfy/Pushover → Garmin relays the
>    phone notification over Bluetooth) beats this. This app is the on-wrist
>    *mirror*, not a background pager.
> 2. **Reachability is unproven.** On a real watch, `makeWebRequest` goes out
>    through the phone's Garmin Connect relay, which may not route to a private
>    Tailscale `100.x` address. **This project is first and foremost a SPIKE to
>    find out.** If the watch shows `no link`, the native route is a dead end
>    and we fall back to the phone-push relay.

## 1. Install the Connect IQ SDK (one-time)

1. Make a free Garmin developer account, then install the **Connect IQ SDK
   Manager** from developer.garmin.com/connect-iq/sdk. Open it and download the
   latest SDK **and** your Forerunner device (e.g. `fr265`, `fr965`).
2. Install **VS Code**, then the **Monkey C** extension (publisher: Garmin).
3. Generate a developer key (VS Code command palette →
   *Monkey C: Generate a Developer Key*). This signs your builds.
4. Point the Monkey C extension at the SDK if it asks (SDK path from step 1).

## 2. Configure

Edit `source/Config.mc`:

- `GARDEN_URL`   — already pre-filled with `http://100.97.203.85:4141` (your
  Tailscale IP at the time of writing). Confirm it matches the host in the app's
  **🔗 copy phone link**.
- `GARDEN_TOKEN` — paste the whole token from `~/.agent-garden-token`
  (`cat ~/.agent-garden-token`). Without it every call gets `HTTP 401`.

## 3. Run in the simulator

1. Open **this folder** (`garmin/GardenWatch`) in VS Code.
2. Trim `manifest.xml`'s `<iq:products>` to the exact model you downloaded.
3. Command palette → *Monkey C: Build for Device* / *Run App* (F5). Pick your
   Forerunner. The Connect IQ simulator launches.
4. With the Mac app running + armed, trigger an approval (ask an agent to edit a
   file). The sim should flip to red **"1 butuh approval"** and buzz.

⚠ **The simulator runs on the Mac**, so it reaches `100.x` trivially — a green
result in the sim does **not** prove a real watch can. The real spike is step 4.

## 4. Sideload to the watch (the real spike)

1. Build a `.prg` (command palette → *Monkey C: Build for Device*).
2. Plug the watch via USB; it mounts as a drive. Copy the `.prg` into
   `GARMIN/APPS/` on the watch. Unplug.
3. Open the **Garden** app from the watch's app list. Watch the status line:
   - **green "idle" / red "N butuh approval"** → 🎉 reachable, it works.
   - **"HTTP 401"** → reachable but wrong/missing token (fix `GARDEN_TOKEN`).
   - **"no link"** → the watch can't reach the Mac over Tailscale. Native route
     is out; use the phone-push relay instead.

## Files

- `source/Config.mc` — the two things you edit (URL + token).
- `source/GardenView.mc` — polling + drawing + vibrate.
- `source/GardenApp.mc`, `source/GardenDelegate.mc` — app shell + BACK to exit.
- `manifest.xml` — app id, Forerunner products, `Communications` permission.
