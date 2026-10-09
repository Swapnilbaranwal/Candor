# Candor Gemini proxy (Google Cloud Run)

A small Node service that sits between the app and the Gemini API. The app posts the same JSON it
would send to Gemini; the service adds the API key, which is held in Secret Manager, and forwards
the request. The key never ships inside the app.

```
iPhone app  ──POST /v1beta/models/<model>:generateContent──▶  Cloud Run  ──▶  Gemini API
                                                              (adds the key)
```

## What it does

- Forwards `POST /v1beta/models/<model>:generateContent` and returns Gemini's status and JSON unchanged.
- Accepts only the models in `ALLOWED_MODELS`.
- Rejects bodies over 6 MB and bodies that are not JSON.
- Allows 30 requests a minute per client address, per instance.
- `GET /healthz` answers `{"status":"ok"}`.

## Deploy

You need a Google Cloud project with billing on and the `gcloud` CLI signed in.
Run these from this folder. Replace `YOUR_PROJECT_ID`.

```sh
gcloud config set project YOUR_PROJECT_ID
gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com secretmanager.googleapis.com

# 1. Put the Gemini key in Secret Manager. Paste the key, press Enter, then Ctrl-D.
gcloud secrets create gemini-api-key --data-file=-

# 2. Let the Cloud Run service account read it.
PROJECT_NUMBER=$(gcloud projects describe YOUR_PROJECT_ID --format='value(projectNumber)')
gcloud secrets add-iam-policy-binding gemini-api-key \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# 3. Build and deploy. Mumbai is the closest region to Delhi.
gcloud run deploy candor-gemini-proxy --source . --region asia-south1 \
  --allow-unauthenticated \
  --set-secrets GEMINI_API_KEY=gemini-api-key:latest \
  --max-instances 2 --memory 256Mi
```

The last command prints the service URL, like `https://candor-gemini-proxy-xxxxx.asia-south1.run.app`.

Check it:

```sh
curl https://YOUR_SERVICE_URL/healthz
```

## Point the app at it

Paste the service URL into `Candor/App/Backend.swift`:

```swift
static let geminiProxyURL = "https://YOUR_SERVICE_URL"
```

With a URL there, the app sends Gemini requests to the proxy and needs no key of its own.
A key typed in *Me → AI settings* still takes priority, and goes straight to the Gemini API.

To try a proxy without rebuilding, launch the app with `-candor.geminiProxyURL https://YOUR_SERVICE_URL`.

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `GEMINI_API_KEY` | none | The Gemini API key. Set from Secret Manager at deploy. |
| `GOOGLE_MAPS_API_KEY` | none | A Google Maps Platform key with **Places API (New)** enabled, for the hotel search in persona setup. Add `--set-secrets GOOGLE_MAPS_API_KEY=google-maps-api-key:latest` at deploy. |
| `ALLOWED_MODELS` | `gemini-3.8-flash,gemini-3.5-flash,gemini-3.5-flash-lite` | Models the proxy will forward to. |
| `REQUESTS_PER_MINUTE` | `30` | Limit per client address, per instance. |
| `GEMINI_API_BASE` | `https://generativelanguage.googleapis.com` | Upstream address. Change it only for tests. |

## Run it locally

```sh
GEMINI_API_KEY=your-key npm start
curl -X POST localhost:8080/v1beta/models/gemini-3.8-flash:generateContent \
  -H 'Content-Type: application/json' \
  -d '{"contents":[{"role":"user","parts":[{"text":"Reply with the single word: ready"}]}]}'
```

## Google Maps place search

`POST /v1/places:searchText` forwards a Places API (New) Text Search to Google with the Maps key
and a fixed field mask (id, name, address, location). The app uses it to find the traveller's hotel.
For development without the proxy, set the `GOOGLE_MAPS_API_KEY` build setting in Xcode
(Candor target → Build Settings → add a user-defined setting), or launch with `-candor.googleMapsKey <key>`.

## Limits

The service is open: anyone who learns the URL can call it. What bounds the damage is the
per-address rate limit, the model list, the body size cap, and `--max-instances 2`. The rate limit
is counted per instance, so with two instances a client can get up to twice the limit.

The next step is to accept requests only from the real app, with Firebase App Check (App Attest
on iOS) verified in this service.
