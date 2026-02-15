Tiki - Twilio OTP changes (files only)

How to apply:
1) Unzip this file over your project root (the folder that contains firebase.json, functions/, lib/).
2) Open functions/.env and fill:
   - TWILIO_ACCOUNT_SID
   - TWILIO_AUTH_TOKEN
3) Install function deps:
   cd functions
   npm i
4) Deploy:
   cd ..
   firebase deploy --only functions

Changed files included:
- functions/.env
- functions/index.js
- functions/package.json
- lib/core/state/auth_state.dart
- lib/features/auth/presentation/phone_login_screen.dart
