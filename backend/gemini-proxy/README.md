# Candor backend (Google Cloud Run)

One small Node service that does four jobs:

| Job | Route | Google Cloud |
|---|---|---|
| Gemini proxy for the iPhone app (the key never ships in the app) | `POST /v1beta/models/<model>:generateContent` | Cloud Run + Secret Manager |
| Fair-price agent for the web demo (Gemini tool calling) | `POST /v1/check` | Cloud Run + Gemini |
| Community prices and scam reports | `/v1/community/prices`, `/v1/community/reports`, `/v1/community/hotspots` | Firestore |
| Brief for a tourism office, written by Gemini from the reports | `GET /v1/community/insights?city=Delhi` | Gemini |
| The web version of the app (Home, Trip, Check, Ask Candor) | `GET /` (`public/`) | Cloud Run |
| Ask Candor, the place guide and the Interpreter for the web app | `POST /v1/ask`, `GET /v1/place`, `POST /v1/place/ask`, `POST /v1/translate` (`web.js`) | Gemini + Places API |
| Trip maps for the web app, drawn on the server so the key stays private | `GET /v1/staticmap` | Maps Static API |
| Hotel search for the app | `POST /v1/places:searchText` | Places API |

```
iPhone app ─┐                         ┌─▶ Gemini API (tool calling, vision)
            ├──▶ Cloud Run service ───┼─▶ Firestore (prices, reports)
Web demo  ──┘    (this folder)        └─▶ Places API
```

## Deploy (about 15 minutes)

You need a Google Cloud project with billing turned on and the `gcloud` CLI signed in
(`gcloud auth login`). At hackathon traffic this stays inside the free tiers of Cloud Run and Firestore.
Run everything from this folder and replace `YOUR_PROJECT_ID`.

```sh
gcloud config set project YOUR_PROJECT_ID
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  secretmanager.googleapis.com firestore.googleapis.com places.googleapis.com static-maps-backend.googleapis.com

# 1. Firestore database (once). Mumbai is closest to Delhi.
gcloud firestore databases create --location=asia-south1

# 2. Put the Gemini key in Secret Manager. Paste the key, press Enter, then Ctrl-D.
gcloud secrets create gemini-api-key --data-file=-
#    Optional, for hotel search: the Google Maps key.
gcloud secrets create google-maps-api-key --data-file=-

# 3. Let the Cloud Run service account read the secrets and use Firestore.
PROJECT_NUMBER=$(gcloud projects describe YOUR_PROJECT_ID --format='value(projectNumber)')
SA="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
gcloud secrets add-iam-policy-binding gemini-api-key --member="$SA" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding google-maps-api-key --member="$SA" --role="roles/secretmanager.secretAccessor"
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID --member="$SA" --role="roles/datastore.user"

# 4. Build and deploy.
gcloud run deploy candor --source . --region asia-south1 --allow-unauthenticated \
  --set-secrets GEMINI_API_KEY=gemini-api-key:latest,GOOGLE_MAPS_API_KEY=google-maps-api-key:latest \
  --max-instances 3 --memory 512Mi
```

The last command prints the service URL, like `https://candor-xxxxx.asia-south1.run.app`.
(Skip the Maps secret and drop it from `--set-secrets` if you don't need hotel search.)

### Check it

```sh
URL=https://YOUR_SERVICE_URL
curl $URL/healthz                       # {"status":"ok","store":"firestore"}
open $URL                               # the web demo
curl -X POST $URL/v1/check -H 'Content-Type: application/json' \
  -d '{"city":"Delhi","question":"Auto from Connaught Place to India Gate, 4 km","askedINR":300}'
```

### Point the app at it

Paste the URL into `Candor/App/Backend.swift`:

```swift
static let geminiProxyURL = "https://YOUR_SERVICE_URL"
```

Then the app sends Gemini requests through Cloud Run, shares price checks and matched tricks
anonymously, and its agent gains the `community_prices` tool. To try a URL without rebuilding,
launch the app with `-candor.geminiProxyURL https://YOUR_SERVICE_URL`.

## Run it locally

```sh
npm install
STORE=memory GEMINI_API_KEY=your-key npm start     # http://localhost:8080
```

`STORE=memory` keeps community data in memory instead of Firestore (lost on restart).

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `GEMINI_API_KEY` | none | The Gemini API key, from Secret Manager. |
| `GOOGLE_MAPS_API_KEY` | none | Google Maps key with Places API (New), for hotel search. |
| `ALLOWED_MODELS` | `gemini-3.8-flash,gemini-3.6-flash,gemini-3.5-flash,gemini-3.5-flash-lite,gemini-3.1-flash-lite,gemini-3-flash-preview` | Models it will call, in fallback order. Keep in step with `GeminiClient.fallbackModels` in the app. |
| `REQUESTS_PER_MINUTE` | `30` | Limit per client address, per instance (Gemini calls and community writes). |
| `STORE` | Firestore | `memory` for local runs. |

## Privacy

Community rows hold only: city, item, amounts, and for reports the trick and a location rounded
to two decimals (about 1 km). No name, account, device id or IP address is stored. The app lets
travellers turn sharing off (Me → Preferences → Share my checks anonymously).

## Limits and next steps

The service is open: anyone with the URL can call it. The rate limit, model list, body size cap and
`--max-instances` bound the cost. Next: Firebase App Check (App Attest) so only the real app can call it,
and moderation of community rows (outliers are already softened by using medians).
