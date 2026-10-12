# NextStep Database (iOS)

NextStep Database is a native iPhone app that helps students in grades 6–12 find STEM opportunities: competitions, research programs, internships, camps and scholarships. It is the iOS companion to the [NextStep Database website](https://www.nextstepdatabase.fyi).

## Related code

- [Website, server API, storage schemas and discovery jobs](https://github.com/Paoloop6/STEMPath-Finder-website)
- [Live website](https://www.nextstepdatabase.fyi/)

The iPhone app and website call a server API backed by DynamoDB, S3 and PostgreSQL. Opportunity discovery uses AWS Lambda, Exa and DeepSeek; the separate video ingestion job uses the YouTube Data API and DeepSeek. See the website repository for the exact code layout and deployment limitations.

## Why we built it

Information about STEM programs is spread across hundreds of separate websites, each with its own deadlines, eligibility rules and costs. That makes it hard for students to find programs that fit them, especially students who don't have someone pointing them in the right direction. NextStep Database puts these programs in one place and helps each student find the ones that match their grade, interests and budget.

## Features

- **Discover**: a home screen with category shortcuts and featured opportunities from the real data.
- **Browse**: search by title, organization or description, filter the results, and see a live result count.
- **Match**: answer a short form (grade, interests, opportunity type, location, format, cost). The app shows an instant on-device ranking, then AI-analyzed matches from the NextStep backend, each with a reason it fits.
- **Map**: a map with a pin for every opportunity that has a real address.
- **Saved**: save opportunities. Saves stay on the device and survive relaunching the app.
- **Opportunity details**: eligibility, deadline, cost, grade levels, format and a link to the original listing. If the data doesn't include something, the app says so instead of guessing.
- **Student stories**: public YouTube videos where students explain the activities that helped them get into college.
- **Feedback survey**: an optional short survey offered after you close your match results.
- **Works on a weak connection**: the last downloaded list loads instantly from a cache, and a clearly labeled demo list appears if the server can't be reached.

## Tech stack

- Swift and SwiftUI
- MapKit and Core Location (`CLGeocoder`) for maps and for turning addresses into coordinates
- `URLSession` for the NextStep backend API
- No third-party packages

Requires Xcode 26 or later. The deployment target is iOS 26.5.

## Running the app

1. Clone the repo and open `nextstepdatabase.xcodeproj` in Xcode.
2. Choose an iPhone simulator and press **Run** (⌘R).
3. To run on a real iPhone, choose your own team under **Signing & Capabilities**.

Optional: launch with the argument `-startTab browse` (or `match`, `map`, `saved`) to open a specific tab.

## Project structure

| File | What it does |
|---|---|
| `RootView.swift` | Tab bar: Discover, Browse, Match, Map, Saved |
| `DiscoverView.swift` | Home screen |
| `BrowseView.swift` | Search and filters |
| `MatchView.swift`, `Match.swift` | Match form, on-device ranking, backend matching |
| `MapViews.swift`, `GeocodeService.swift` | Maps and cached, rate-limited geocoding |
| `OpportunityDetailView.swift` | Full details for one opportunity |
| `Opportunity.swift`, `OpportunityService.swift`, `OpportunityStore.swift` | Data model, networking, caching |
| `SavedStore.swift`, `SavedView.swift` | Saved opportunities |
| `StudentVideo.swift`, `StudentVideosView.swift` | Student stories |
| `SurveyStore.swift`, `SurveyView.swift` | Optional feedback survey |
| `Components.swift`, `Theme.swift` | Shared UI pieces and styling |
| `SelfTests.swift` | Debug-only checks for filtering and saved items (`SelfTests.runAll()`) |

## Data, services and credits

- Opportunity listings, matching and the student video list come from the NextStep Database backend at `nextstepdatabase.fyi`. The backend source snapshots are in the [website/server repository](https://github.com/Paoloop6/STEMPath-Finder-website); its [preserved student-video route](https://github.com/Paoloop6/STEMPath-Finder-website/blob/original-public-main/artifacts/api-server/src/routes/student-videos.ts) is on `original-public-main`.
- Matching uses DeepSeek, an AI model, which runs on the backend server. The app sends the Match form answers. It doesn't send a name, email or account.
- Maps use Apple MapKit, and addresses are converted to coordinates with Apple's geocoder.
- Student videos are public YouTube videos owned by their creators. They are shown with YouTube's privacy-enhanced embed (`youtube-nocookie.com`).

## AI use

- **In the app**: the Match feature uses DeepSeek on the server to analyze opportunities and explain each match.
- **In development**: we used Claude (Anthropic) to help develop the app's UI (user interface) and to edit our demo video.
