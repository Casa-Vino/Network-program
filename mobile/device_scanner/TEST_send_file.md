# Test: send a file from the phone to a computer

A step-by-step smoke test for the **Send files to a computer** feature. It
checks the whole path: pick a file on the phone → serve it over Wi-Fi →
download it in a computer's browser.

## Why not test against the cloud session?

The Claude cloud session can't be the receiver: it isn't on your Wi-Fi, and the
phone's little web server is only reachable on the local network. So the
receiving device must be a **computer on the same Wi-Fi as the phone** (e.g. the
Surface), using any browser.

## Preconditions

- The phone has the latest app installed (or updated via **Check for updates**).
- Phone **and** the receiving computer are on the **same Wi-Fi network**.
- The network does **not** isolate clients ("AP isolation" / "client
  isolation"). Most home networks are fine; some guest networks block this.
- You know the phone will stay awake — keep the sharing screen open.

## Steps

| # | On | Do this | Expect |
|---|----|---------|--------|
| 1 | Phone | Open the app → tap the **upload** icon (top-right) → **Send files to a computer**. | The send screen opens. |
| 2 | Phone | Tap **Pick files**, choose **one image** (a photo). | Button shows "1 file(s) selected"; the filename is listed. |
| 3 | Phone | Tap **Start sharing**. | A card appears with a **QR code** and a URL like `http://192.168.x.y:8080/abcde/`. |
| 4 | Computer | Type that URL into a browser (or scan the QR with the computer's camera / another phone). | A page titled "Files shared from the phone (1)" with the image filename as a link. |
| 5 | Computer | Click the filename. | The browser downloads the image. |
| 6 | Computer | Open the downloaded file. | It's the same photo, opens correctly, same size as shown on the phone. |
| 7 | Phone | Tap **Stop sharing**. | The card disappears; the URL no longer loads on the computer (refresh → fails). |

**Pass:** the image downloads at step 5 and opens correctly at step 6.

## Quick variant (command line, optional)

On the computer, instead of the browser you can confirm reachability with
`curl` (replace with your URL):

```bash
curl -s http://192.168.x.y:8080/abcde/            # should print the HTML listing
curl -L -o test.jpg http://192.168.x.y:8080/abcde/file/0   # downloads the first file
```

## If it doesn't work

| Symptom | Likely cause | Fix |
|---|---|---|
| Browser can't load the URL at all | Phone and computer on different networks, or **AP/client isolation** | Put both on the same Wi-Fi; try your main network, not guest Wi-Fi. |
| "Connection refused" | Sharing was stopped, or the phone screen locked and the server paused | Re-open the share screen, **Start sharing** again, keep the screen on. |
| Page loads but download fails / is 0 bytes | The picked file came from a cloud provider with no local path | Pick a file that's actually on the phone (a camera photo). |
| URL shows wrong IP (e.g. starts with 169.254) | Phone not actually on Wi-Fi | Connect the phone to Wi-Fi and retry. |

## What this exercises

`ui/send_files.dart` (pick + UI), `services/file_server.dart` (the HTTP server,
token routing, and file streaming), and `network_info_plus` (the phone's Wi-Fi
IP). A pass means the end-to-end transfer path works on your network.
