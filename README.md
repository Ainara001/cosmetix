# Cosmetix

Cosmetix is a mobile application built with Flutter for browsing cosmetic products, comparing prices, checking ingredients, and managing personal skincare routines.

The application combines a product catalog, local database, ingredient analysis, personalized recommendations, and an AI assistant. It was developed as an academic project based on a 22-screen Figma design.

Most features work offline using SQLite. An external Node.js proxy is used only for AI-related requests.

## Tech Stack

- **Flutter / Dart** — mobile application development
- **Provider** — state management
- **SQLite (sqflite)** — local data storage
- **Node.js** — AI proxy server
- **Gemini API / Claude API** — AI assistant
- **PBKDF2-HMAC-SHA256** — password hashing
- **Flutter Test / SQLite FFI** — automated testing

## Features

- Product catalog with search, filters, and sorting.
- Price comparison across multiple stores.
- Product details, ingredients, and reviews.
- Ingredient analysis and personal blacklist.
- Beauty profile with skin type, concerns, color type, and undertone.
- Product recommendations based on user preferences.
- AI assistant for questions about cosmetics and skincare.
- Shopping cart, order history, and favorites.
- Personal cosmetics collection and skincare routines.
- Skin reaction journal.
- Light and dark themes.
- Russian, English, and Kazakh interface.

## Architecture

The project uses a layered architecture to keep UI, application logic, and database operations separate.

```text
Screens
   |
Providers
   |
Repositories
   |
SQLite

Services
   |
Business Logic / AI Proxy
```

- `screens/` — application screens.
- `providers/` — state management using ChangeNotifier.
- `repositories/` — database queries and data operations.
- `services/` — ingredient analysis, recommendations, beauty tests, and AI communication.
- `database/` — SQLite schema, migrations, and demo data.
- `models/` — application data models.
- `widgets/` — reusable UI components.

## Database

SQLite is used to store application data locally.

The database includes tables for users, products, stores, prices, ingredients, favorites, cart items, orders, reviews, beauty profiles, skin reactions, and skincare routines.

Database migrations are used to update the schema while preserving existing data.

## AI Assistant

The AI assistant supports Gemini and Claude through a separate Node.js proxy.

The API key is stored in the server environment and is not included in the Flutter application.

The proxy handles requests, provider selection, rate limits, token limits, and API errors. AI functionality is optional; the rest of the application works without the server.

## Running the Project

### Requirements

- Flutter SDK
- Dart SDK
- Xcode for iOS development
- Android Studio for Android development

### Installation

```bash
git clone https://github.com/Ainara001/cosmetix.git
cd cosmetix
flutter pub get
flutter run
```

On the first launch, the application creates the SQLite database and inserts demonstration data.

### Running the AI Proxy (Optional)

```bash
cd server
cp .env.example .env
```

Add your Gemini or Claude API key to `.env`, then run:

```bash
node index.js
```

Configure the server address in the application settings.

## Testing

```bash
dart format .
flutter analyze
flutter test

cd server
node --test
```

The tests cover database operations, migrations, validation, repositories, recommendation logic, ingredient analysis, password hashing, and AI proxy requests.

## Notes

- Product prices, store availability, and purchasing operations use demonstration data.
- Google and Apple authentication and password recovery are local simulations.
- AI features require a separately configured proxy server.
- The application is intended for demonstration and educational purposes, not medical diagnosis or real online purchases.

---

**Project:** Academic / Personal Portfolio  
**Developer:** Ainara Rustemkyzy
