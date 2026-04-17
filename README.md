# PromptShield

**Protecting AI conversations with smart safety checks.**

PromptShield is a Flutter-based chat application that acts as an AI safety gateway. It detects sensitive data and unsafe prompts before sending user input to an AI model, helping ensure safer and more responsible AI interactions.

---

## 🚀 Features

* 🔐 **Sensitive Data Detection**
  Detects email, phone numbers, passwords, OTP, and more

* 🧠 **Prompt Injection Detection**
  Identifies unsafe inputs like “ignore instructions”, “act as”, etc.

* ⚠️ **Risk Scoring System**
  Classifies input as SAFE / MEDIUM / HIGH

* 🤖 **AI Integration (Gemini)**
  Sends only validated input to AI model

* 🎨 **Modern Chat UI**
  Clean, responsive Flutter interface

---

## 📱 Tech Stack

* Flutter (Dart)
* Gemini API
* HTTP package

---

## ▶️ Run the App

```bash
flutter pub get
flutter run --dart-define=API_KEY=YOUR_API_KEY
```

---
## 🎥 Demo Video

Watch the demo here:
https://drive.google.com/file/d/1zIZ5I0MfSKkhadultW4AR8AZ8I5oAAxb/view?usp=drive_link

The app demonstrates:

* Detection of unsafe prompts before AI interaction
* Warning alerts for risky inputs
* Option to override and send anyway

---

## 🔐 Security Note

API keys are not included in this repository.
Use `--dart-define` to securely pass your API key at runtime.

---

## 📌 Project Purpose

This project showcases how a lightweight safety layer can be implemented in front of AI systems to improve trust, security, and user awareness.

---

## 👤 Author

Shafna Jasnin
